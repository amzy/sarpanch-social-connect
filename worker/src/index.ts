export interface Env {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_WEB_API_KEY: string;
  GOOGLE_SERVICE_ACCOUNT_JSON: string;
  GEMINI_API_KEY: string;
  SOCIAL_ENCRYPTION_KEY: string;
  META_GRAPH_VERSION?: string;
  ADMIN_BOOTSTRAP_UID?: string;
  ALLOWED_ORIGINS?: string;
}

type Json = Record<string, unknown>;
type FirestoreDocument = { name: string; fields?: Record<string, unknown>; updateTime?: string };
const LANGUAGES = new Set(["English", "Hindi", "Marathi", "Telugu", "Tamil", "Gujarati"]);
const encoder = new TextEncoder();
let cachedAccessToken: { token: string; expiresAt: number } | undefined;

function response(data: unknown, status = 200, origin = "*"): Response {
  return new Response(JSON.stringify(data), { status, headers: {
    "content-type": "application/json; charset=utf-8",
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "authorization, content-type",
    "vary": "Origin",
  }});
}
function fail(message: string, status = 400): never { throw Object.assign(new Error(message), { status }); }
function b64url(bytes: Uint8Array): string {
  let binary = ""; for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
function pemBytes(pem: string): Uint8Array {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  return Uint8Array.from(atob(body), c => c.charCodeAt(0));
}
async function googleAccessToken(env: Env): Promise<string> {
  if (cachedAccessToken && cachedAccessToken.expiresAt > Date.now() + 60_000) return cachedAccessToken.token;
  const account = JSON.parse(env.GOOGLE_SERVICE_ACCOUNT_JSON) as { client_email: string; private_key: string; token_uri?: string };
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(encoder.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claim = b64url(encoder.encode(JSON.stringify({
    iss: account.client_email, scope: "https://www.googleapis.com/auth/datastore",
    aud: account.token_uri ?? "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  })));
  const unsigned = header + "." + claim;
  const key = await crypto.subtle.importKey("pkcs8", pemBytes(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, arrayBuffer(encoder.encode(unsigned))));
  const assertion = unsigned + "." + b64url(signature);
  const tokenResponse = await fetch(account.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  const tokenData = await tokenResponse.json() as { access_token?: string; expires_in?: number; error_description?: string };
  if (!tokenResponse.ok || !tokenData.access_token) throw new Error(tokenData.error_description ?? "Google service authentication failed.");
  cachedAccessToken = { token: tokenData.access_token, expiresAt: Date.now() + (tokenData.expires_in ?? 3600) * 1000 };
  return tokenData.access_token;
}
async function verifyUser(request: Request, env: Env): Promise<{ uid: string; phoneNumber?: string }> {
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) fail("Sign in is required.", 401);
  const lookup = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(env.FIREBASE_WEB_API_KEY)}`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ idToken: authorization.slice(7) }),
  });
  const result = await lookup.json() as { users?: Array<{ localId?: string; phoneNumber?: string }> };
  const user = result.users?.[0];
  if (!lookup.ok || !user?.localId) fail("Your session is invalid or expired. Sign in again.", 401);
  return { uid: user.localId, phoneNumber: user.phoneNumber };
}
function decodeValue(value: any): any {
  if (!value || typeof value !== "object") return value;
  if ("stringValue" in value) return value.stringValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("booleanValue" in value) return value.booleanValue;
  if ("timestampValue" in value) return value.timestampValue;
  if ("nullValue" in value) return null;
  if ("arrayValue" in value) return (value.arrayValue.values ?? []).map(decodeValue);
  if ("mapValue" in value) return decodeFields(value.mapValue.fields ?? {});
  return value;
}
function decodeFields(fields: Record<string, any>): Json {
  return Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, decodeValue(value)]));
}
function encodeValue(value: any): any {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encodeValue) } };
  if (typeof value === "object") {
    if (value.__timestamp) return { timestampValue: value.__timestamp };
    return { mapValue: { fields: encodeFields(value) } };
  }
  return { stringValue: String(value) };
}
function encodeFields(fields: Json): Record<string, unknown> {
  return Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, encodeValue(value)]));
}
function docUrl(env: Env, path: string): string {
  return `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${path}`;
}
async function getDoc(env: Env, path: string): Promise<{ data: Json; updateTime: string; name: string }> {
  const token = await googleAccessToken(env);
  const result = await fetch(docUrl(env, path), { headers: { authorization: `Bearer ${token}` } });
  if (result.status === 404) fail("Record not found.", 404);
  if (!result.ok) throw new Error(`Firestore read failed (${result.status}): ${(await result.text()).slice(0, 300)}`);
  const doc = await result.json() as FirestoreDocument;
  return { data: decodeFields(doc.fields ?? {}), updateTime: doc.updateTime!, name: doc.name };
}
async function patchDoc(env: Env, path: string, fields: Json, updateTime?: string): Promise<void> {
  const token = await googleAccessToken(env);
  const url = new URL(docUrl(env, path));
  for (const key of Object.keys(fields)) url.searchParams.append("updateMask.fieldPaths", key);
  if (updateTime) url.searchParams.set("currentDocument.updateTime", updateTime);
  const body: Json = { fields: encodeFields(fields) };
  const result = await fetch(url, { method: "PATCH", headers: {
    authorization: `Bearer ${token}`, "content-type": "application/json",
  }, body: JSON.stringify(body) });
  if (result.status === 409 || result.status === 412) fail("This record changed in another request. Refresh and try again.", 409);
  if (!result.ok) throw new Error(`Firestore update failed (${result.status}): ${(await result.text()).slice(0, 300)}`);
}
async function createDoc(env: Env, path: string, fields: Json): Promise<void> {
  const token = await googleAccessToken(env);
  const url = new URL(docUrl(env, path));
  url.searchParams.set("currentDocument.exists", "false");
  const result = await fetch(url, { method: "PATCH", headers: {
    authorization: `Bearer ${token}`, "content-type": "application/json",
  }, body: JSON.stringify({ fields: encodeFields(fields) }) });
  if (!result.ok) throw new Error(`Firestore create failed (${result.status}): ${(await result.text()).slice(0, 300)}`);
}
async function gemini(env: Env, prompt: string, temperature = 0.55, maxOutputTokens = 700): Promise<string> {
  const result = await fetch("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=" + encodeURIComponent(env.GEMINI_API_KEY), {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }], generationConfig: { temperature, maxOutputTokens } }),
  });
  const data = await result.json() as any;
  if (!result.ok) throw new Error(data.error?.message ?? "Gemini request failed.");
  const text = data.candidates?.[0]?.content?.parts?.map((part: any) => part.text ?? "").join("").trim();
  if (!text) throw new Error("Gemini returned an empty response.");
  return text;
}
function jsonFromModel(text: string): any {
  const cleaned = text.replace(/^\s*```(?:json)?\s*/i, "").replace(/\s*```\s*$/, "");
  return JSON.parse(cleaned);
}
function monthKey(): string {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kolkata", year: "numeric", month: "2-digit" }).formatToParts(new Date());
  return `${parts.find(p => p.type === "year")?.value}-${parts.find(p => p.type === "month")?.value}`;
}
function captionPrompt(post: Json, user: Json, language: string, refresh = false): string {
  return [
    "Act as a professional public relations writer for an Indian village Gram Panchayat Sarpanch.",
    "Write an impactful, humble, factual public update. Do not invent achievements, budgets, dates, names, statistics, approvals or promises.",
    `Write entirely in ${language}. Preserve supplied proper nouns and numbers. Preserve exact user-provided Hindi spellings.`,
    "Use a respectful, accessible tone. Avoid partisan attacks, inflammatory language, requests for votes, or unsupported political claims.",
    `Post type: ${String(post.type ?? "development")}.`,
    `Sarpanch (English): ${String(user.sarpanchName ?? "")}; Sarpanch (Hindi): ${String(user.sarpanchNameHindi ?? "")}; Panchayat (English): ${String(user.panchayatName ?? "")}; Panchayat (Hindi): ${String(user.panchayatNameHindi ?? "")}; District: ${String(user.district ?? "")}; State: ${String(user.state ?? "")}.`,
    `User notes: ${String(post.rawNotes ?? "").trim()}.`,
    refresh ? "Generate three NEW options, different in wording and approach from previous options." : "Create exactly THREE distinct options: concise, warm/community-focused, and formal/informative.",
    "Return valid JSON only: {\"captions\":[\"option 1\",\"option 2\",\"option 3\"]}.",
  ].join("\n");
}
async function generateForPost(env: Env, uid: string, postId: string, refresh: boolean): Promise<Json> {
  const path = `posts_queue/${postId}`;
  const current = await getDoc(env, path);
  if (current.data.uid !== uid) fail("Post not found.", 404);
  if (refresh) {
    if (current.data.status !== "pending_approval") fail("Post is not awaiting approval.", 409);
    if (Number(current.data.captionRefreshCount ?? 0) >= 5) fail("Maximum of five refreshes reached.", 429);
  } else {
    if (current.data.status !== "pending_ai") fail("Post is not waiting for AI generation.", 409);
  }
  const user = await getDoc(env, `users/${uid}`);
  if (user.data.billingStatus !== "active") fail("Your account is not active for AI generation.", 403);
  const language = String(current.data.contentLanguage ?? user.data.primaryLanguage ?? "Hindi");
  if (!LANGUAGES.has(language)) fail("Unsupported content language.", 400);
  const plan = String(user.data.plan ?? "free").toLowerCase();
  const usage = (user.data.usage ?? {}) as Json;
  const aiUsage = (usage.aiGenerations ?? {}) as Json;
  const month = monthKey();
  if (!refresh && plan !== "premium" && Number(aiUsage[month] ?? 0) >= 3) {
    await patchDoc(env, path, { status: "failed", failureCode: "FREE_MONTHLY_LIMIT_REACHED" }, current.updateTime);
    fail("FREE_MONTHLY_LIMIT_REACHED", 429);
  }
  if (refresh) {
    await patchDoc(env, path, { status: "generating_more" }, current.updateTime);
  } else {
    await patchDoc(env, path, { status: "processing_ai" }, current.updateTime);
  }
  try {
    if (!refresh) {
      await patchDoc(env, `users/${uid}`, {
        usage: { ...usage, aiGenerations: { ...aiUsage, [month]: Number(aiUsage[month] ?? 0) + 1 }, lastAiGenerationAt: { __timestamp: new Date().toISOString() } },
      }, user.updateTime);
    }
    const text = await gemini(env, captionPrompt(current.data, user.data, language, refresh));
    const parsed = jsonFromModel(text) as { captions?: unknown };
    const captions = Array.isArray(parsed.captions) ? parsed.captions.map(String).map(s => s.trim()).filter(Boolean).slice(0, 3) : [];
    if (captions.length !== 3) throw new Error("Gemini did not return exactly three caption options.");
    const latestPost = await getDoc(env, path);
    const refreshCount = Number(latestPost.data.captionRefreshCount ?? 0) + (refresh ? 1 : 0);
    await patchDoc(env, path, {
      aiCaptions: captions, aiCaption: captions[0], status: "pending_approval",
      aiGeneratedAt: { __timestamp: new Date().toISOString() },
      aiLanguage: language, captionRefreshCount: refreshCount,
    }, latestPost.updateTime);
    return { captions, refreshCount };
  } catch (error) {
    const latest = await getDoc(env, path).catch(() => null);
    if (latest) await patchDoc(env, path, { status: refresh ? "pending_approval" : "failed", failureCode: "AI_GENERATION_FAILED", failureMessage: String(error).slice(0, 400) }, latest.updateTime).catch(() => undefined);
    throw error;
  }
}
function fromB64(value: string): Uint8Array { return Uint8Array.from(atob(value), c => c.charCodeAt(0)); }
function toB64(value: ArrayBuffer): string {
  const bytes = new Uint8Array(value); let binary = ""; bytes.forEach(b => binary += String.fromCharCode(b)); return btoa(binary);
}
async function cryptoKey(env: Env): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", arrayBuffer(fromB64(env.SOCIAL_ENCRYPTION_KEY)), "AES-GCM", false, ["encrypt", "decrypt"]);
}
async function encryptSecret(env: Env, value: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt({ name: "AES-GCM", iv: arrayBuffer(iv) }, await cryptoKey(env), arrayBuffer(encoder.encode(value)));
  return `${toB64(arrayBuffer(iv))}.${toB64(encrypted)}`;
}
async function decryptSecret(env: Env, value: string): Promise<string> {
  const [iv, encrypted] = value.split(".");
  const clear = await crypto.subtle.decrypt({ name: "AES-GCM", iv: arrayBuffer(fromB64(iv)) }, await cryptoKey(env), arrayBuffer(fromB64(encrypted)));
  return new TextDecoder().decode(clear);
}
async function readSocial(env: Env, uid: string): Promise<Json> {
  try {
    const doc = await getDoc(env, `users/${uid}/private/socialTokens`);
    const result: Json = {};
    for (const key of ["facebookPageToken", "twitterToken"]) if (typeof doc.data[key] === "string") result[key] = await decryptSecret(env, String(doc.data[key]));
    for (const key of ["facebookPageId", "instagramId"]) if (typeof doc.data[key] === "string") result[key] = doc.data[key];
    return result;
  } catch { return {}; }
}
async function graphPost(url: string, body: URLSearchParams): Promise<string> {
  const result = await fetch(url, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body });
  const data = await result.json() as any;
  if (!result.ok) throw new Error(data.error?.message ?? `Social API error ${result.status}`);
  return String(data.post_id ?? data.id ?? "");
}
async function publish(env: Env, uid: string, postId: string): Promise<Json> {
  const path = `posts_queue/${postId}`;
  const post = await getDoc(env, path);
  if (post.data.uid !== uid) fail("Post not found.", 404);
  if (!["approved_to_publish", "failed"].includes(String(post.data.status))) fail("Post is not approved for publishing.", 409);
  const user = await getDoc(env, `users/${uid}`);
  if (String(user.data.plan ?? "").toLowerCase() !== "premium" || String(user.data.billingStatus ?? "").toLowerCase() !== "active") fail("Premium subscription is required for automatic publishing.", 403);
  const caption = String(post.data.aiCaption ?? "").trim();
  if (!caption) fail("The approved caption is empty.", 400);
  const credentials = await readSocial(env, uid);
  const imageUrl = String(post.data.finalCompositedImage ?? "");
  const prior = (post.data.publishResults ?? {}) as Json;
  const results: Json = { ...prior };
  await patchDoc(env, path, { status: "publishing", publishStartedAt: { __timestamp: new Date().toISOString() } }, post.updateTime);
  const version = env.META_GRAPH_VERSION || "v23.0";
  const attempts: Array<Promise<void>> = [];
  if (credentials.facebookPageToken && credentials.facebookPageId && !(prior.facebook as any)?.ok) {
    attempts.push((async () => {
      try {
        const hasImage = imageUrl.trim().length > 0;
        const id = await graphPost(`https://graph.facebook.com/${version}/${encodeURIComponent(String(credentials.facebookPageId))}/${hasImage ? "photos" : "feed"}`,
          new URLSearchParams(hasImage ? { url: imageUrl, caption, access_token: String(credentials.facebookPageToken) } : { message: caption, access_token: String(credentials.facebookPageToken) }));
        results.facebook = { ok: true, id };
      } catch (error) { results.facebook = { ok: false, error: String(error).slice(0, 400) }; }
    })());
  }
  if (credentials.facebookPageToken && credentials.instagramId && imageUrl && !(prior.instagram as any)?.ok) {
    attempts.push((async () => {
      try {
        const base = `https://graph.facebook.com/${version}/${encodeURIComponent(String(credentials.instagramId))}`;
        const container = await graphPost(`${base}/media`, new URLSearchParams({ image_url: imageUrl, caption, access_token: String(credentials.facebookPageToken) }));
        const id = await graphPost(`${base}/media_publish`, new URLSearchParams({ creation_id: container, access_token: String(credentials.facebookPageToken) }));
        results.instagram = { ok: true, id };
      } catch (error) { results.instagram = { ok: false, error: String(error).slice(0, 400) }; }
    })());
  }
  if (credentials.twitterToken && !(prior.x as any)?.ok) {
    attempts.push((async () => {
      try {
        const result = await fetch("https://api.x.com/2/tweets", { method: "POST", headers: { authorization: `Bearer ${credentials.twitterToken}`, "content-type": "application/json" }, body: JSON.stringify({ text: caption }) });
        const data = await result.json() as any;
        if (!result.ok || !data.data?.id) throw new Error(data.detail ?? "X publishing failed.");
        results.x = { ok: true, id: data.data.id };
      } catch (error) { results.x = { ok: false, error: String(error).slice(0, 400) }; }
    })());
  }
  await Promise.all(attempts);
  const success = Object.values(results).some((value: any) => value?.ok);
  const configured = Boolean(credentials.facebookPageToken && credentials.facebookPageId) || Boolean(credentials.facebookPageToken && credentials.instagramId && imageUrl) || Boolean(credentials.twitterToken);
  const latest = await getDoc(env, path);
  const hasFailures = Object.values(results).some((value: any) => value && value.ok === false);
  const status = success && !hasFailures ? "published" : "failed";
  await patchDoc(env, path, {
    status, publishResults: results,
    publishedAt: success ? { __timestamp: new Date().toISOString() } : null,
    failureCode: success ? null : (configured ? "ALL_CHANNELS_FAILED" : "NO_CHANNELS_CONFIGURED"),
    publishCompletedAt: { __timestamp: new Date().toISOString() },
    publisherDisplayName: String(user.data.sarpanchName ?? ""),
  }, latest.updateTime);
  return { status, publishResults: results };
}
async function handle(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const requestOrigin = request.headers.get("origin");
  const allowedOrigins = (env.ALLOWED_ORIGINS ?? "").split(",").map(value => value.trim()).filter(Boolean);
  if (requestOrigin && allowedOrigins.length > 0 && !allowedOrigins.includes(requestOrigin)) {
    return response({ error: "Origin not allowed." }, 403, "null");
  }
  const origin = requestOrigin ?? "*";
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: {
    "access-control-allow-origin": origin, "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "authorization, content-type", "access-control-max-age": "86400",
  }});
  if (url.pathname === "/health" && request.method === "GET") return response({ ok: true, service: "sarpanch-social-connect-api" }, 200, origin);
  if (request.method !== "POST" || !url.pathname.startsWith("/api/")) return response({ error: "Not found." }, 404, origin);
  try {
    const user = await verifyUser(request, env);
    const body = await request.json() as Json;
    if (url.pathname === "/api/posts/generate") {
      const postId = String(body.postId ?? "");
      if (!postId) fail("postId is required.");
      const result = await generateForPost(env, user.uid, postId, false);
      return response(result, 200, origin);
    }
    if (url.pathname === "/api/posts/more-options") {
      const postId = String(body.postId ?? "");
      if (!postId) fail("postId is required.");
      return response(await generateForPost(env, user.uid, postId, true), 200, origin);
    }
    if (url.pathname === "/api/profile/transliterate") {
      const text = String(body.text ?? "").trim();
      if (!text || text.length > 120) fail("Enter a name up to 120 characters.");
      const suggestion = (await gemini(env, [
        "Transliterate this Indian proper name from English letters into Devanagari Hindi script.",
        "Do phonetic transliteration only; do not translate, explain, add titles or invent details.",
        "Return only the Devanagari name, without quotes or commentary.", "Name: " + text,
      ].join("\n"), 0.1, 100)).replace(/^[\"']|[\"']$/g, "").trim();
      if (!suggestion) throw new Error("Hindi transliteration returned an empty result.");
      return response({ hindi: suggestion }, 200, origin);
    }
    if (url.pathname === "/api/posts/approve-and-publish") {
      const postId = String(body.postId ?? "");
      const caption = String(body.caption ?? "").trim();
      if (!postId || !caption) fail("postId and caption are required.");
      const path = `posts_queue/${postId}`;
      const post = await getDoc(env, path);
      if (post.data.uid !== user.uid) fail("Post not found.", 404);
      if (post.data.status !== "pending_approval") fail("Post is not awaiting approval.", 409);
      const owner = await getDoc(env, `users/${user.uid}`);
      if (String(owner.data.plan ?? "").toLowerCase() !== "premium" || String(owner.data.billingStatus ?? "").toLowerCase() !== "active") fail("Premium subscription is required for automatic publishing. You can still use Share to publish manually.", 403);
      await patchDoc(env, path, { aiCaption: caption, status: "approved_to_publish" }, post.updateTime);
      return response(await publish(env, user.uid, postId), 200, origin);
    }
    if (url.pathname === "/api/posts/reject") {
      const postId = String(body.postId ?? "");
      const post = await getDoc(env, `posts_queue/${postId}`);
      if (post.data.uid !== user.uid) fail("Post not found.", 404);
      if (post.data.status !== "pending_approval") fail("Post is not awaiting approval.", 409);
      await patchDoc(env, `posts_queue/${postId}`, { status: "rejected" }, post.updateTime);
      return response({ rejected: true }, 200, origin);
    }
    if (url.pathname === "/api/posts/retry") {
      const postId = String(body.postId ?? "");
      const post = await getDoc(env, `posts_queue/${postId}`);
      if (post.data.uid !== user.uid) fail("Post not found.", 404);
      if (post.data.status === "pending_approval") {
        return response({ status: "pending_approval", captions: post.data.aiCaptions ?? [] }, 200, origin);
      }
      if (post.data.status === "pending_ai") {
        return response(await generateForPost(env, user.uid, postId, false), 200, origin);
      }
      if (["AI_GENERATION_FAILED", "FREE_MONTHLY_LIMIT_REACHED", "BILLING_INACTIVE", "UNSUPPORTED_LANGUAGE"].includes(String(post.data.failureCode ?? ""))) {
        await patchDoc(env, `posts_queue/${postId}`, { status: "pending_ai", failureCode: null, failureMessage: null }, post.updateTime);
        return response(await generateForPost(env, user.uid, postId, false), 200, origin);
      }
      return response(await publish(env, user.uid, postId), 200, origin);
    }
    if (url.pathname === "/api/social/credentials") {
      const allowed = ["facebookPageToken", "facebookPageId", "instagramId", "twitterToken"];
      if (Object.keys(body).some(key => !allowed.includes(key))) fail("Unsupported credential field.");
      const current = await getDoc(env, `users/${user.uid}`).catch(() => null);
      if (!current) fail("Complete your profile first.", 404);
      const saved: Json = {};
      for (const key of allowed) {
        const value = body[key];
        if (typeof value === "string" && value.trim()) {
          saved[key] = ["facebookPageId", "instagramId"].includes(key) ? value.trim() : await encryptSecret(env, value.trim());
        }
      }
      saved.updatedAt = { __timestamp: new Date().toISOString() };
      const privatePath = `users/${user.uid}/private/socialTokens`;
      const old = await getDoc(env, privatePath).catch(() => null);
      if (old) await patchDoc(env, privatePath, saved, old.updateTime);
      else await createDoc(env, privatePath, saved);
      return response({ saved: true }, 200, origin);
    }
    if (url.pathname === "/api/admin/bootstrap") {
      if (!env.ADMIN_BOOTSTRAP_UID || user.uid !== env.ADMIN_BOOTSTRAP_UID || user.phoneNumber !== "+91900165600") fail("Not authorized.", 403);
      const adminPath = `admins/${user.uid}`;
      const existingAdmin = await getDoc(env, adminPath).catch(() => null);
      if (!existingAdmin) await createDoc(env, adminPath, { uid: user.uid, role: "admin", createdAt: { __timestamp: new Date().toISOString() } });
      return response({ isAdmin: true, alreadyConfigured: Boolean(existingAdmin) }, 200, origin);
    }
    return response({ error: "Not found." }, 404, origin);
  } catch (error) {
    const status = Number((error as any)?.status ?? 500);
    return response({ error: error instanceof Error ? error.message : "Unexpected server error." }, status >= 400 && status < 600 ? status : 500, origin);
  }
}
export default { fetch: handle };
