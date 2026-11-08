# Sarpanch Social Connect

Approval-first social publishing for Gram Panchayats. Flutter + Firebase Spark + one Cloudflare Worker + Gemini API.

## Architecture

- Flutter: Android, iOS and GitHub Pages web app. Post creation supports both the existing AI-assisted poster composer and uploading a ready-made JPG, PNG or WebP image from Files or the device camera/gallery; both paths enter the same caption approval queue.
- Firebase Spark: Phone Authentication and Firestore.
- Cloudflare Workers Free: one TypeScript HTTPS API for Gemini, authorization, captions, transliteration, media uploads and social publishing. Cloudflare Workers KV stores profile and post media within free-tier limits.
- Gemini API: captions and Hindi transliteration. The key stays in Worker secrets.
- No Firebase Cloud Functions, no Blaze upgrade, no Firebase Storage dependency, no D1, no Queues and no Cloud KMS.

The Worker verifies Firebase ID tokens through Firebase Authentication accounts:lookup. Privileged Firestore writes use a dedicated Google service account with the Cloud Datastore User role. Store its JSON key only as a Worker secret. Firestore rules deny client access to private social credentials and admin records.

## Worker endpoints

All endpoints except GET /health require Authorization: Bearer <Firebase ID token>.

| Endpoint | Purpose |
|---|---|
| POST /api/posts/generate | Generate three captions for an owned pending_ai post |
| POST /api/media/upload | Authenticated owner-scoped upload to Workers KV |
| POST /api/posts/more-options | Generate three new captions; maximum five refreshes |
| POST /api/profile/transliterate | Transliterate an Indian name into Devanagari |
| POST /api/posts/approve-and-publish | Save edited caption, approve and publish |
| POST /api/posts/reject | Reject an owned pending post |
| POST /api/posts/manual-share | Record a user-confirmed manual share to a social destination |
| POST /api/posts/retry | Retry AI generation or failed social publishing |
| POST /api/social/credentials | Legacy encrypted credential storage |\n| POST /api/social/connect | Start a per-user Facebook, Instagram or Threads OAuth connection |\n| POST /api/social/accounts | List the signed-in user’s connected account metadata |\n| GET /api/social/oauth/callback | Validate OAuth state, exchange authorization codes and store encrypted tokens |\n| POST /api/posts/publish-selected | Publish an approved post to explicitly selected connected accounts |
| POST /api/admin/bootstrap | Allowlisted development-admin bootstrap |

AI captions support English, Hindi, Marathi, Telugu, Tamil and Gujarati. Free users have three initial AI caption generations per India calendar month; the existing five-refresh limit remains separate. Direct publishing is explicitly user-initiated after approval. Facebook supports text/image, Instagram requires an image, and X currently publishes text. The approval queue also offers manual sharing to Facebook, Instagram, Threads, WhatsApp Groups, WhatsApp Channels and other installed apps through the native share sheet. Manual sharing is recorded only after the user confirms completing the post in the destination app; opening or dismissing the share sheet is never treated as successful delivery.

## One-time setup

### Firebase Spark

Keep the project on Spark. Enable Phone Authentication and Firestore. Do not initialize Firebase Storage and do not deploy Functions.

Create a dedicated service account in the existing Google Cloud project, for example sarpanch-worker-firestore. Grant only Cloud Datastore User (roles/datastore.user). Create a JSON key. The Worker uses it for Firestore REST operations. Do not grant Owner or Editor.

Copy the Firebase Web API key from lib/firebase_options.dart (web apiKey).

### Cloudflare Worker Free + Workers KV

No paid plan or billing details are required for the intended free-tier setup. The GitHub Actions deployment workflow automatically finds or creates the Workers KV namespace named `sarpanch-social-connect-media`, injects its namespace ID into the deployment configuration, and deploys the Worker. No R2 bucket is used. Uploaded profile images and post visuals are served through the Worker `/media/` route. Uploads are limited to 8 MB per file; keep usage within Cloudflare Workers KV free-tier storage and operation quotas. KV is suitable for this small app's low-volume media, but it is not a substitute for a dedicated large-media object store.

For local `wrangler dev`, create the namespace once with `npx wrangler kv namespace create sarpanch-social-connect-media`, then replace `__KV_NAMESPACE_ID__` in your local `wrangler.toml` with the returned ID. Do not commit a placeholder or secret.

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
firebase deploy --only firestore:rules
```

Do not deploy Functions. Confirm Firebase Console remains on Spark.

### Flutter

```bash
flutter pub get
flutter run -d chrome --dart-define=BACKEND_API_URL=https://sarpanch-social-connect-api.<your-subdomain>.workers.dev
```

Pass the same BACKEND_API_URL define to the GitHub Pages Flutter build and Android/iOS builds. This URL is public configuration, not a secret.

## Social account OAuth and publishing

Each signed-in Sarpanch connects their own accounts from Settings → Social accounts. The Worker starts an OAuth authorization-code flow, validates a short-lived one-time state value, exchanges the code server-side, discovers the authorized account/Page, and stores the provider token encrypted with AES-GCM in users/{uid}/private/socialTokens. The Flutter app receives only account IDs, provider names and display names; it never receives access tokens.

Configure these Worker secrets before enabling account connections:

```bash
npx wrangler secret put META_APP_ID
npx wrangler secret put META_APP_SECRET
npx wrangler secret put INSTAGRAM_CLIENT_ID
npx wrangler secret put INSTAGRAM_CLIENT_SECRET
npx wrangler secret put THREADS_APP_ID
npx wrangler secret put THREADS_APP_SECRET
npx wrangler secret put APP_RETURN_URL
```

Register this exact callback URL in the relevant Meta OAuth products:
`https://sarpanch-social-connect-api.<your-subdomain>.workers.dev/api/social/oauth/callback`

Set APP_RETURN_URL to the deployed Flutter web app URL, including its GitHub Pages repository path. Configure the Facebook Login, Instagram Login and Threads redirect allowlists with the callback above. Facebook Page publishing requires Page permissions and a Page the authorizing user manages. Instagram API publishing supports professional Business/Creator accounts; personal accounts are not eligible. Threads uses its own OAuth app credentials and scopes. Meta App Review/Advanced Access is required before unrelated public users can authorize permissions that are still in Development mode.

The approval card displays the user's connected Facebook Pages, Instagram professional accounts and Threads profile. The user selects specific accounts and explicitly confirms publishing. Each selected destination is processed separately and per-account results are stored on the post. The existing manual share flow remains available, including WhatsApp Groups and Channels. Tokens are never returned by the account-list endpoint. Provider token refresh/re-authorization handling and mobile deep-link return still require validation before production rollout.

## Limits and safety

- Cloudflare Workers and KV, Gemini, Meta and X each have independent quotas and policies. The media upload path is intentionally capped at 8 MB per file; large-volume media hosting is outside this free-tier design.
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
