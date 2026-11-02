# Sarpanch Social Connect

Approval-first social publishing for Gram Panchayats. Flutter + Firebase Spark + one Cloudflare Worker + Gemini API.

## Architecture

- Flutter: Android, iOS and GitHub Pages web app.
- Firebase Spark: Phone Authentication, Firestore and Storage.
- Cloudflare Workers Free: one TypeScript HTTPS API for Gemini, authorization, captions, transliteration and social publishing.
- Gemini API: captions and Hindi transliteration. The key stays in Worker secrets.
- No Firebase Cloud Functions, no Blaze upgrade, no D1, no Queues and no Cloud KMS.

The Worker verifies Firebase ID tokens through Firebase Authentication accounts:lookup. Privileged Firestore writes use a dedicated Google service account with the Cloud Datastore User role. Store its JSON key only as a Worker secret. Firestore rules deny client access to private social credentials and admin records.

## Worker endpoints

All endpoints except GET /health require Authorization: Bearer <Firebase ID token>.

| Endpoint | Purpose |
|---|---|
| POST /api/posts/generate | Generate three captions for an owned pending_ai post |
| POST /api/posts/more-options | Generate three new captions; maximum five refreshes |
| POST /api/profile/transliterate | Transliterate an Indian name into Devanagari |
| POST /api/posts/approve-and-publish | Save edited caption, approve and publish |
| POST /api/posts/reject | Reject an owned pending post |
| POST /api/posts/retry | Retry AI generation or failed social publishing |
| POST /api/social/credentials | Encrypt and store social tokens privately |
| POST /api/admin/bootstrap | Allowlisted development-admin bootstrap |

AI captions support English, Hindi, Marathi, Telugu, Tamil and Gujarati. Free users have three initial AI caption generations per India calendar month; the existing five-refresh limit remains separate. Publishing is explicitly user-initiated after approval. Facebook supports text/image, Instagram requires an image, and X currently publishes text.

## One-time setup

### Firebase Spark

Keep the project on Spark. Enable Phone Authentication, Firestore and Storage. Do not deploy Functions.

Create a dedicated service account in the existing Google Cloud project, for example sarpanch-worker-firestore. Grant only Cloud Datastore User (roles/datastore.user). Create a JSON key. The Worker uses it for Firestore REST operations. Do not grant Owner or Editor.

Copy the Firebase Web API key from lib/firebase_options.dart (web apiKey).

### Cloudflare Worker Free

From worker/:

```bash
npm install
npx wrangler login
npx wrangler secret put FIREBASE_WEB_API_KEY
npx wrangler secret put GOOGLE_SERVICE_ACCOUNT_JSON
npx wrangler secret put GEMINI_API_KEY
openssl rand -base64 32
npx wrangler secret put SOCIAL_ENCRYPTION_KEY
npx wrangler secret put ADMIN_BOOTSTRAP_UID
npm run check
npm run deploy
```

For GOOGLE_SERVICE_ACCOUNT_JSON, enter the complete service-account JSON as one value. For SOCIAL_ENCRYPTION_KEY, use the output of openssl rand -base64 32. ADMIN_BOOTSTRAP_UID is only needed for the one-time development admin bootstrap; remove it afterward.

Set META_GRAPH_VERSION in worker/wrangler.toml to a Graph API version supported by your Meta app. The Worker URL will be https://sarpanch-social-connect-api.<your-subdomain>.workers.dev.

### Firebase rules

Deploy only the products still in use:

```bash
firebase deploy --only firestore:rules,storage
```

Do not deploy Functions. Confirm Firebase Console remains on Spark.

### Flutter

```bash
flutter pub get
flutter run -d chrome --dart-define=BACKEND_API_URL=https://sarpanch-social-connect-api.<your-subdomain>.workers.dev
```

Pass the same BACKEND_API_URL define to the GitHub Pages Flutter build and Android/iOS builds. This URL is public configuration, not a secret.

## Social credentials

The Worker accepts Facebook Page token/Page ID, Instagram account ID and X bearer token. Access tokens are encrypted with AES-GCM using the Worker-only SOCIAL_ENCRYPTION_KEY and stored at users/{uid}/private/socialTokens. Flutter cannot read this document.

Provider OAuth consent and token refresh are not yet implemented. Until then, credentials must be supplied through a trusted authenticated integration using the Worker endpoint. Never put provider tokens in Flutter or public profile documents.

## Limits and safety

- Cloudflare, Gemini, Meta and X each have independent quotas and policies.
- This request-driven design does not promise unattended scheduled publishing.
- Firestore update-time preconditions reject stale concurrent writes. A client disconnect can still occur after an external API has started processing.
- Service-account JSON, Gemini keys, social tokens and encryption keys must never be committed or pasted into chat.
- Firebase Cloud Functions source and deployment configuration are removed from this branch.

## Checks

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib
flutter analyze
flutter test
cd worker && npm install && npm run check
```
