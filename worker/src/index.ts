export interface Env {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_WEB_API_KEY: string;
  GOOGLE_SERVICE_ACCOUNT_JSON: string;
  AI: { run(model: string, inputs: Json): Promise<any> };
  AI_MODEL?: string;
  SOCIAL_ENCRYPTION_KEY: string;
  META_GRAPH_VERSION?: string;
  ADMIN_BOOTSTRAP_UID?: string;
  ALLOWED_ORIGINS?: string;
  MEDIA_BUCKET: {
    put(key: string, value: ArrayBuffer, options?: { metadata?: { contentType: string } }): Promise<void>;
    getWithMetadata(key: string, type: "arrayBuffer"): Promise<{ value: ArrayBuffer | null; metadata: { contentType?: string } | null }>;
  };
}

type Json = Record<string, unknown>;
type FirestoreDocument = { name: string; fields?: Record<string, unknown>; updateTime?: string };
const LANGUAGES = new Set(["English", "Hindi", "Marathi", "Telugu", "Tamil", "Gujarati"]);
const POST_TYPES = new Set(["festival", "development", "announcement", "project", "event", "public_service"]);
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
async function parseJsonResponse<T = any>(result: Response, source: string): Promise<T> {
  const raw = await result.text();
  try {
    return JSON.parse(raw) as T;
  } catch {
    throw new Error(source + " returned incomplete or invalid JSON (HTTP " + result.status + "; " + raw.length + " bytes).");
  }
}
function b64url(bytes: Uint8Array): string {
  let binary = ""; for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
function arrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(copy).set(bytes);
  return copy;
}
function pemBytes(pem: string): ArrayBuffer {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\\s/g, "");
  return arrayBuffer(Uint8Array.from(atob(body), c => c.charCodeAt(0)));
}
async function googleAccessToken(env: Env): Promise<string> {
  if (cachedAccessToken && cachedAccessToken.expiresAt > Date.now() + 60_000) return cachedAccessToken.token;
  let account: { client_email: string; private_key: string; token_uri?: string };
  try {
    account = JSON.parse(env.GOOGLE_SERVICE_ACCOUNT_JSON);
  } catch {
    throw new Error("Worker configuration error: GOOGLE_SERVICE_ACCOUNT_JSON is not valid JSON. Re-add the complete service-account JSON as the Cloudflare Worker secret; do not paste it into the app or chat.");
  }
  if (typeof account.client_email !== "string" || !account.client_email.includes("@") ||
      typeof account.private_key !== "string" || !account.private_key.includes("PRIVATE KEY")) {
    throw new Error("Worker configuration error: GOOGLE_SERVICE_ACCOUNT_JSON is missing client_email or private_key. Re-add the complete service-account JSON as the Cloudflare Worker secret.");
  }
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
  const tokenData = await parseJsonResponse<{ access_token?: string; expires_in?: number; error_description?: string }>(tokenResponse, "Google OAuth token endpoint");
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
  const result = await parseJsonResponse<{
    users?: Array<{ localId?: string; phoneNumber?: string }>;
    error?: { message?: string; status?: string; errors?: Array<{ message?: string; reason?: string }> };
  }>(lookup, "Firebase Identity Toolkit");
  const user = result.users?.[0];
  if (!lookup.ok || !user?.localId) {
    const reason = result.error?.message ??
      result.error?.errors?.map(item => item.reason ?? item.message).filter(Boolean).join(", ") ??
      "TOKEN_VERIFICATION_FAILED";
    // Keep the Firebase response code, but never return the submitted token or API key.
    fail(`Firebase sign-in verification failed (${reason}). Refresh the session and try again. If this persists, verify the Worker's FIREBASE_WEB_API_KEY matches the web app's Firebase project.`, 401);
  }
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
  const doc = await parseJsonResponse<FirestoreDocument>(result, "Firestore document read");
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
const DEFAULT_AI_MODEL = "@cf/zai-org/glm-4.7-flash";

async function workersAi(env: Env, prompt: string, temperature = 0.55, maxOutputTokens = 700): Promise<string> {
  const model = env.AI_MODEL?.trim() || DEFAULT_AI_MODEL;
  let result: any;
  try {
    result = await env.AI.run(model, {
      messages: [
        { role: "system", content: "You are a precise multilingual assistant. Follow the instructions exactly. Do not invent facts." },
        { role: "user", content: prompt },
      ],
      temperature,
      max_tokens: maxOutputTokens,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error("Cloudflare Workers AI request failed (" + model + "): " + message.slice(0, 300));
  }
  const output = typeof result === "string" ? result :
    typeof result?.response === "string" ? result.response :
    typeof result?.output_text === "string" ? result.output_text : "";
  if (!output.trim()) throw new Error("Cloudflare Workers AI returned an empty response (" + model + ").");
  return output.trim();
}
function jsonFromModel(text: string): any {
  const cleaned = text.replace(/^\s*```(?:json)?\s*/i, "").replace(/\s*```\s*$/, "");
  return JSON.parse(cleaned);
}

// Workers AI does not guarantee schema-constrained JSON for every model.
// Validate locally and retry once with an explicit JSON-only schema instruction.
async function workersAiJson(
  env: Env, prompt: string, maxOutputTokens: number, responseSchema: Json,
): Promise<any> {
  for (let attempt = 0; attempt < 2; attempt++) {
    const retryPrompt = attempt === 0 ? prompt : [
      prompt,
      "IMPORTANT: Your previous response was incomplete or invalid JSON.",
      "Return one complete JSON object matching this JSON schema: " + JSON.stringify(responseSchema),
      "Do not use markdown fences, comments, or text outside the JSON object.",
      "Keep every string concise and close all quotes, arrays, and braces.",
    ].join("\n");
    try {
      const output = await workersAi(env, retryPrompt, 0.25, maxOutputTokens);
      try {
        return jsonFromModel(output);
      } catch (error) {
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const retryable = message.includes("output limit") ||
        message.includes("HTTP response was incomplete or invalid JSON");
      if (!retryable) throw error;
    }
  }
  throw new Error("Cloudflare Workers AI returned incomplete structured data twice. No caption was saved. Please retry in a moment.");
}
function monthKey(): string {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kolkata", year: "numeric", month: "2-digit" }).formatToParts(new Date());
  return `${parts.find(p => p.type === "year")?.value}-${parts.find(p => p.type === "month")?.value}`;
}
function captionPrompt(post: Json, user: Json, language: string, refresh = false): string {
  const profile = [
    user.sarpanchName ? "Name: " + String(user.sarpanchName) : "",
    user.sarpanchNameHindi ? "Hindi name: " + String(user.sarpanchNameHindi) : "",
    user.panchayatName ? "Panchayat: " + String(user.panchayatName) : "",
    user.panchayatNameHindi ? "Hindi panchayat: " + String(user.panchayatNameHindi) : "",
    user.district ? "District: " + String(user.district) : "",
    user.state ? "State: " + String(user.state) : "",
  ].filter(Boolean).join("; ");
  return [
    "Write 3 short, ready-to-post public updates in " + language + " for an Indian Gram Panchayat.",
    "Tone: humble, clear, respectful, non-partisan. No vote requests or attacks.",
    "Use only supplied facts. Never invent achievements, figures, dates, names, approvals or promises. Preserve names, numbers and Hindi spellings exactly.",
    "Return exactly 3 distinct captions: concise; warm/community-focused; formal/informative. No labels or explanations.",
    refresh ? "Make all options fresh and different from earlier captions." : "",
    "Type: " + String(post.type ?? "development"),
    profile ? "Profile: " + profile : "",
    "Details: " + String(post.promptNotes ?? post.rawNotes ?? "").trim(),
  ].filter(Boolean).join("\n");
}
async function generateForPost(env: Env, uid: string, postId: string, refresh: boolean, trace: { requestId: string; stage: string }): Promise<Json> {
  const path = `posts_queue/${postId}`;
  trace.stage = "read_post";
  const current = await getDoc(env, path);
  if (current.data.uid !== uid) fail("Post not found.", 404);
  if (!POST_TYPES.has(String(current.data.type ?? ""))) fail("Unsupported post type.", 400);
  if (String(current.data.rawNotes ?? "").length > 5000) fail("Post description is too long.", 400);
  if (refresh) {
    if (current.data.status !== "pending_approval") fail("Post is not awaiting approval.", 409);
    if (Number(current.data.captionRefreshCount ?? 0) >= 5) fail("Maximum of five refreshes reached.", 429);
  } else {
    if (current.data.status !== "pending_ai") fail("Post is not waiting for AI generation.", 409);
  }
  trace.stage = "read_user";
  const user = await getDoc(env, `users/${uid}`);
  if (user.data.billingStatus !== "active") {
    if (!refresh) await patchDoc(env, path, { status: "failed", failureCode: "BILLING_INACTIVE" }, current.updateTime);
    fail("Your account is not active for AI generation.", 403);
  }
  const language = String(current.data.contentLanguage ?? user.data.primaryLanguage ?? "Hindi");
  if (!LANGUAGES.has(language)) {
    if (!refresh) await patchDoc(env, path, { status: "failed", failureCode: "UNSUPPORTED_LANGUAGE" }, current.updateTime);
    fail("Unsupported content language.", 400);
  }
  const plan = String(user.data.plan ?? "free").toLowerCase();
  const usage = (user.data.usage ?? {}) as Json;
  const aiUsage = (usage.aiGenerations ?? {}) as Json;
  const month = monthKey();
  const alreadyClaimed = current.data.aiUsageClaimed === true;
  trace.stage = "check_monthly_limit";
  if (!refresh && !alreadyClaimed && plan !== "premium" && Number(aiUsage[month] ?? 0) >= 3) {
    await patchDoc(env, path, { status: "failed", failureCode: "FREE_MONTHLY_LIMIT_REACHED", failureMessage: "The app's free allowance of 3 successful AI generations for this month has been reached." }, current.updateTime);
    const limitError = Object.assign(new Error("FREE_MONTHLY_LIMIT_REACHED"), { status: 429, stage: trace.stage });
    throw limitError;
  }
  trace.stage = "set_processing_status";
  if (refresh) {
    await patchDoc(env, path, { status: "generating_more" }, current.updateTime);
  } else {
    await patchDoc(env, path, { status: "processing_ai" }, current.updateTime);
  }
  let usageClaimedThisAttempt = false;
  try {
    trace.stage = "workers_ai_generate_and_parse";
    const parsed = (await workersAiJson(env, captionPrompt(current.data, user.data, language, refresh), 1800, { type: "OBJECT", properties: { captions: { type: "ARRAY", minItems: 3, maxItems: 3, items: { type: "STRING" } } }, required: ["captions"] })) as { captions?: unknown };
    const captions = Array.isArray(parsed.captions) ? parsed.captions.map(String).map(s => s.trim()).filter(Boolean).slice(0, 3) : [];
    if (captions.length !== 3) throw new Error("AI did not return exactly three caption options.");
    // Charge the app allowance only after Workers AI has returned valid captions.
    // Failed API calls, malformed output, and timeouts must not consume a slot.
    if (!refresh && !alreadyClaimed) {
      trace.stage = "claim_monthly_usage";
      const latestUser = await getDoc(env, `users/${uid}`);
      const latestUsage = (latestUser.data.usage ?? {}) as Json;
      const latestAiUsage = (latestUsage.aiGenerations ?? {}) as Json;
      await patchDoc(env, `users/${uid}`, {
        usage: { ...latestUsage, aiGenerations: { ...latestAiUsage, [month]: Number(latestAiUsage[month] ?? 0) + 1 }, lastAiGenerationAt: { __timestamp: new Date().toISOString() } },
      }, latestUser.updateTime);
      usageClaimedThisAttempt = true;
      const claimedPost = await getDoc(env, path);
      await patchDoc(env, path, { aiUsageClaimed: true, aiUsageMonth: month }, claimedPost.updateTime);
    }
    trace.stage = "read_post_before_save";
    const latestPost = await getDoc(env, path);
    const refreshCount = Number(latestPost.data.captionRefreshCount ?? 0) + (refresh ? 1 : 0);
    trace.stage = "save_captions_and_approval_status";
    await patchDoc(env, path, {
      aiCaptions: captions, aiCaption: captions[0], status: "pending_approval",
      aiGeneratedAt: { __timestamp: new Date().toISOString() },
      aiLanguage: language, captionRefreshCount: refreshCount,
    }, latestPost.updateTime);
    return { captions, refreshCount };
  } catch (error) {
    const failedStage = trace.stage;
    if (usageClaimedThisAttempt) {
      // Best-effort refund if a later Firestore save failed after captions were generated.
      const latestUser = await getDoc(env, `users/${uid}`).catch(() => null);
      if (latestUser) {
        const latestUsage = (latestUser.data.usage ?? {}) as Json;
        const latestAiUsage = (latestUsage.aiGenerations ?? {}) as Json;
        const currentCount = Number(latestAiUsage[month] ?? 0);
        await patchDoc(env, `users/${uid}`, {
          usage: { ...latestUsage, aiGenerations: { ...latestAiUsage, [month]: Math.max(0, currentCount - 1) } },
        }, latestUser.updateTime).catch(() => undefined);
      }
    }
    const latest = await getDoc(env, path).catch(() => null);
    if (latest) await patchDoc(env, path, {
      status: refresh ? "pending_approval" : "failed",
      failureCode: "AI_GENERATION_FAILED",
      failureMessage: String(error).slice(0, 400),
      ...(usageClaimedThisAttempt ? { aiUsageClaimed: false, aiUsageMonth: null } : {}),
    }, latest.updateTime).catch(() => undefined);
    trace.stage = "save_generation_failure";
    console.error(JSON.stringify({ event: "post_generation_failed", requestId: trace.requestId, stage: failedStage, error: error instanceof Error ? error.message : String(error), postId }));
    if (error && typeof error === "object" && !(error as any).stage) (error as any).stage = failedStage;
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
  } catch (error) {
    if ((error as any)?.status === 404) return {};
    throw error;
  }
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
  if (url.pathname.startsWith("/media/") && request.method === "GET") {
    const key = decodeURIComponent(url.pathname.slice("/media/".length));
    if (!/^[A-Za-z0-9_-]{1,128}\/[A-Za-z0-9_-]{1,64}\/[A-Za-z0-9_.-]{1,160}$/.test(key)) return new Response("Not found", { status: 404 });
    const object = await env.MEDIA_BUCKET.getWithMetadata(key, "arrayBuffer");
    if (!object.value) return new Response("Not found", { status: 404 });
    return new Response(object.value, { headers: {
      "content-type": object.metadata?.contentType ?? "application/octet-stream",
      "cache-control": "public, max-age=31536000, immutable",
      "access-control-allow-origin": "*",
      "cross-origin-resource-policy": "cross-origin",
    }});
  }
  if (request.method !== "POST" || !url.pathname.startsWith("/api/")) return response({ error: "Not found." }, 404, origin);
  let requestId = request.headers.get("x-request-id") ?? crypto.randomUUID();
  let stage = "authenticate_request";
  try {
    const user = await verifyUser(request, env);
    if (url.pathname === "/api/media/upload") {
      const body = await request.json() as Json;
      const key = String(body.path ?? "");
      const contentType = String(body.contentType ?? "");
      const encoded = String(body.data ?? "");
      if (!/^[A-Za-z0-9_-]{1,128}\/[A-Za-z0-9_-]{1,64}\/[A-Za-z0-9_.-]{1,160}$/.test(key) || !key.startsWith(user.uid + "/")) fail("Invalid media path.", 400);
      if (!["image/jpeg", "image/png", "image/webp"].includes(contentType)) fail("Unsupported image format.", 400);
      if (!encoded || encoded.length > 11_200_000) fail("Image must be smaller than 8 MB.", 413);
      const binary = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
      if (binary.byteLength > 8 * 1024 * 1024) fail("Image must be smaller than 8 MB.", 413);
      // KV stores media bytes directly. Keep uploads below 8 MiB to stay within
      // the Workers Free KV value-size limit and avoid unexpected paid services.
      await env.MEDIA_BUCKET.put(key, arrayBuffer(binary), { metadata: { contentType } });
      return response({ url: new URL("/media/" + key.split("/").map(encodeURIComponent).join("/"), request.url).toString(), size: binary.byteLength }, 201, origin);
    }
    stage = "parse_request_body";
    const body = await request.json() as Json;
    if (url.pathname === "/api/posts/generate") {
      const postId = String(body.postId ?? "");
      if (!/^[A-Za-z0-9_-]{1,128}$/.test(postId)) fail("A valid postId is required.");
      requestId = String(body.requestId ?? requestId).slice(0, 100);
      const trace = { requestId, stage: "start_generation" };
      const result = await generateForPost(env, user.uid, postId, false, trace);
      return response({ ...result, requestId }, 200, origin);
    }
    if (url.pathname === "/api/posts/more-options") {
      const postId = String(body.postId ?? "");
      if (!/^[A-Za-z0-9_-]{1,128}$/.test(postId)) fail("A valid postId is required.");
      const trace = { requestId, stage: "start_caption_refresh" };
      const result = await generateForPost(env, user.uid, postId, true, trace);
      return response({ ...result, requestId }, 200, origin);
    }
    if (url.pathname === "/api/posts/generate-image") {
      const postType = String(body.postType ?? "");
      const notes = String(body.notes ?? "").trim();
      const contentLanguage = String(body.contentLanguage ?? "Hindi");
      if (!POST_TYPES.has(postType)) fail("Choose a valid post type.");
      if (!LANGUAGES.has(contentLanguage)) fail("Choose a supported content language.");
      if (!notes || notes.length > 5000) fail("Post details must be between 1 and 5000 characters.");
      const profile = await getDoc(env, `users/${user.uid}`);
      const sourceProfile = {
        sarpanchName: String(profile.data.sarpanchName ?? ""),
        sarpanchNameHindi: String(profile.data.sarpanchNameHindi ?? ""),
        panchayatName: String(profile.data.panchayatName ?? ""),
        panchayatNameHindi: String(profile.data.panchayatNameHindi ?? ""),
        district: String(profile.data.district ?? ""),
        state: String(profile.data.state ?? ""),
      };
      let localizedProfile: Json;
      if (contentLanguage === "English") {
        localizedProfile = {
          sarpanchName: sourceProfile.sarpanchName || sourceProfile.sarpanchNameHindi,
          panchayatName: sourceProfile.panchayatName || sourceProfile.panchayatNameHindi,
          district: sourceProfile.district,
          state: sourceProfile.state,
        };
      } else {
        const translated = await workersAiJson(env, [
          "Localise the following Indian public representative and Gram Panchayat profile details into " + contentLanguage + ".",
          "Return the person's name and place names in the natural native writing system used for " + contentLanguage + ". Transliterate proper names; do not translate their meanings or add honorifics. Use both English and Hindi spellings as clues. Keep names faithful and recognisable.",
          "Do not add any facts. If a field is blank, return an empty string for it. Return JSON only.",
          "Source profile: " + JSON.stringify(sourceProfile),
        ].join("\\n"), 300, {
          type: "OBJECT",
          properties: {
            sarpanchName: { type: "STRING" },
            panchayatName: { type: "STRING" },
            district: { type: "STRING" },
            state: { type: "STRING" },
          },
          required: ["sarpanchName", "panchayatName", "district", "state"],
        });
        localizedProfile = {
          sarpanchName: String(translated.sarpanchName ?? ""),
          panchayatName: String(translated.panchayatName ?? ""),
          district: String(translated.district ?? ""),
          state: String(translated.state ?? ""),
        };
      }
      const name = String(localizedProfile.sarpanchName || sourceProfile.sarpanchName || sourceProfile.sarpanchNameHindi || "Sarpanch");
      const panchayat = String(localizedProfile.panchayatName || sourceProfile.panchayatName || sourceProfile.panchayatNameHindi || "Gram Panchayat");
      const district = String(localizedProfile.district || sourceProfile.district);
      const state = String(localizedProfile.state || sourceProfile.state);
      const name = String(profile.data.sarpanchNameHindi || profile.data.sarpanchName || "Sarpanch");
      const panchayat = String(profile.data.panchayatNameHindi || profile.data.panchayatName || "Gram Panchayat");
      const district = String(profile.data.district || "");
      const state = String(profile.data.state || "");
      const prompt = [
        "Create a premium, modern Indian Gram Panchayat social-media poster artwork in a stylish hand-sketched editorial illustration style.",
        "Portrait 4:5 composition, rich layered pencil and ink textures, refined watercolor washes, contemporary graphic design, strong visual hierarchy, warm natural light and polished print finish.",
        "The central scene must visually communicate the supplied community update. Use a dignified, welcoming rural Indian setting and culturally appropriate details.",
        "Leave clean negative space for typography to be added by the app. Do not render any letters, words, numbers, logos, watermarks, seals, flags, political party symbols or fake official marks.",
        "Do not invent facts, completed works, public benefits or achievements. Depict the topic as an illustrative concept, not as documentary proof.",
        "Sarpanch profile context: " + name + ". Gram Panchayat: " + panchayat + ". Location: " + [district, state].filter(Boolean).join(", ") + ".",
        "Post category: " + postType + ".",
        "Content prompt: " + notes,
      ].join("\n");
      let generated: any;
      try {
        generated = await env.AI.run("@cf/black-forest-labs/flux-1-schnell", { prompt });
      } catch (error) {
        throw new Error("Cloudflare image generation failed: " + (error instanceof Error ? error.message : String(error)).slice(0, 260));
      }
      if (typeof generated?.image !== "string" || !generated.image) {
        throw new Error("Cloudflare image model returned no image data.");
      }
      const imageBytes = fromB64(generated.image);
      if (imageBytes.byteLength === 0 || imageBytes.byteLength > 8 * 1024 * 1024) {
        fail("Generated artwork is empty or exceeds the 8 MB media limit.", 502);
      }
      const key = `${user.uid}/artwork/${crypto.randomUUID()}.jpg`;
      await env.MEDIA_BUCKET.put(key, arrayBuffer(imageBytes), { metadata: { contentType: "image/jpeg" } });
      const imageUrl = new URL("/media/" + key.split("/").map(encodeURIComponent).join("/"), request.url).toString();
      return response({ imageUrl, localizedProfile, contentLanguage, model: "@cf/black-forest-labs/flux-1-schnell" }, 200, origin);
    }
    if (url.pathname === "/api/posts/suggest-frame") {
      const postType = String(body.postType ?? "");
      const notes = String(body.notes ?? "").trim();
      if (!POST_TYPES.has(postType)) fail("Choose a valid post type.");
      if (!notes || notes.length > 5000) fail("Post details must be between 1 and 5000 characters.");
      const prompt = [
        "You are a visual art director creating a dignified public-service poster frame for an Indian Gram Panchayat.",
        "Choose the best matching frame design from this exact list only: classic, celebration, development, announcement, minimal, tricolor.",
        "Match the visual mood to the post content and type. Keep it readable, respectful, non-partisan and suitable for a government community update.",
        "Do not invent text, names, symbols, claims or achievements. Return valid JSON only with one field: frameStyle.",
        "Post type: " + postType,
        "Post details: " + notes,
      ].join("\n");
      const suggestion = await workersAiJson(env, prompt, 160, { type: "OBJECT", properties: { frameStyle: { type: "STRING", enum: ["classic", "celebration", "development", "announcement", "minimal", "tricolor"] } }, required: ["frameStyle"] }) as { frameStyle?: unknown };
      const frameStyle = String(suggestion.frameStyle ?? "");
      if (!["classic", "celebration", "development", "announcement", "minimal", "tricolor"].includes(frameStyle)) {
        fail("AI returned an unsupported frame style.", 502);
      }
      return response({ frameStyle }, 200, origin);
    }
    if (url.pathname === "/api/profile/transliterate") {
      const text = String(body.text ?? "").trim();
      if (!text || text.length > 120) fail("Enter a name up to 120 characters.");
      const suggestion = (await workersAi(env, [
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
        const trace = { requestId, stage: "start_retry_generation" };
        const result = await generateForPost(env, user.uid, postId, false, trace);
        return response({ ...result, requestId }, 200, origin);
      }
      if (["AI_GENERATION_FAILED", "FREE_MONTHLY_LIMIT_REACHED", "BILLING_INACTIVE", "UNSUPPORTED_LANGUAGE", "CLIENT_GENERATION_REQUEST_FAILED"].includes(String(post.data.failureCode ?? ""))) {
        await patchDoc(env, `posts_queue/${postId}`, { status: "pending_ai", failureCode: null, failureMessage: null }, post.updateTime);
        const trace = { requestId, stage: "start_retry_generation" };
        const result = await generateForPost(env, user.uid, postId, false, trace);
        return response({ ...result, requestId }, 200, origin);
      }
      return response(await publish(env, user.uid, postId), 200, origin);
    }
    if (url.pathname === "/api/posts/whatsapp-delivery") {
      const postId = String(body.postId ?? "");
      const destination = String(body.destination ?? "");
      const confirmed = body.confirmed === true;
      if (!/^[A-Za-z0-9_-]{1,128}$/.test(postId)) fail("A valid postId is required.");
      if (!["group", "channel"].includes(destination)) fail("Choose a valid WhatsApp destination.");
      if (!confirmed) fail("Delivery can only be recorded after explicit confirmation.");
      const path = `posts_queue/${postId}`;
      const post = await getDoc(env, path);
      if (post.data.uid !== user.uid) fail("Post not found.", 404);
      const previous = (post.data.whatsappDelivery ?? {}) as Json;
      const delivery = {
        ...previous,
        [destination]: {
          status: "confirmed_by_admin",
          confirmedAt: { __timestamp: new Date().toISOString() },
          confirmedBy: user.uid,
        },
      };
      await patchDoc(env, path, { whatsappDelivery: delivery }, post.updateTime);
      return response({ saved: true, destination, status: "confirmed_by_admin" }, 200, origin);
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
    const message = error instanceof Error ? error.message : "Unexpected server error.";
    const failedStage = String((error as any)?.stage ?? stage);
    console.error(JSON.stringify({ event: "api_request_failed", requestId, stage: failedStage, path: url.pathname, status, error: message }));
    return response({ error: message, requestId, stage: failedStage }, status >= 400 && status < 600 ? status : 500, origin);
  }
}
export default { fetch: handle };
