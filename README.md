# Sarpanch Social Connect

AI-assisted, approval-first social publishing for Gram Panchayats. Flutter (Android-first/iOS-compatible) + Firebase + Gemini.

## Architecture

- Flutter feature-first app with Riverpod, Firebase Auth, Firestore, Storage, image compression and share intents.
- Cloud Functions v2 (Node.js 22 + TypeScript) for AI generation, usage enforcement, credential encryption and publishing dispatch.
- Firestore documents follow the requested `users` and `posts_queue` field names. Social credentials are deliberately kept in a separate server-only document and encrypted with Cloud KMS; they are never placed in the client-readable user profile.
- Multi-tenant isolation is enforced by Firebase rules using the authenticated UID.

## Repository structure

```text
lib/
  core/                 app theme, localization, Firebase bootstrap
  features/auth/        phone OTP sign-in
  features/profile/     Sarpanch and Panchayat profile
  features/posts/       composer, before/after canvas, approval queue
  features/share/       local share intent
  services/             image compression and retry queue
functions/src/          AI, billing, KMS credentials, Meta/X dispatch
firestore.rules         tenant isolation and field-level writes
storage.rules           user-owned object paths
firebase.json           Firebase deployment configuration
```

## Prerequisites

- Flutter stable with Android and iOS toolchains
- Node.js 22 and npm
- Firebase CLI (`npm i -g firebase-tools`)
- A Firebase project with Authentication (Phone), Firestore, Storage, Cloud Functions v2 and Secret Manager enabled
- Gemini API key
- Cloud KMS key ring/key for encrypting per-user social credentials
- Meta app with Facebook Page and Instagram Graph API permissions; X developer app with user-context write access

## Configure

1. Create a Firebase project and run `firebase login`.
2. Run `flutter create --platforms=android,ios .` to generate platform projects if they are not present, then run `flutterfire configure --project=<your-project-id>` from the repository root. This replaces the placeholder `lib/firebase_options.dart` with project-specific options.
3. Set the project alias: `firebase use --add`.
4. Set function secrets and parameters:

```bash
firebase functions:secrets:set GEMINI_API_KEY
firebase functions:secrets:set KMS_KEY_NAME
```

`KMS_KEY_NAME` must be a fully qualified Cloud KMS CryptoKey resource. Grant the deployed Functions service account permission to encrypt/decrypt with that key. Set `META_GRAPH_VERSION` in an untracked `.env.<project-id>` file to the currently supported Graph API version enabled for your Meta app (for example, `META_GRAPH_VERSION=vXX.0`).

5. Install dependencies:

```bash
flutter pub get
cd functions && npm install && npm run build && npm test
```

6. Deploy rules and functions:

```bash
firebase deploy --only firestore:rules,storage,functions
```

7. Run the app:

```bash
flutter run
```

## Social credentials

The client must not write access tokens to `users/{uid}`. After a provider OAuth flow, send tokens to the authenticated callable `saveSocialCredentials` (accepts `facebookPageToken`, `facebookPageId`, `instagramId`, and `twitterToken`). The function encrypts access tokens with Cloud KMS and stores ciphertext at `users/{uid}/private/socialTokens`; non-secret provider IDs are stored as identifiers. Firestore rules deny all client reads/writes to this private path. This scaffold does not implement Meta/X OAuth consent screens or token refresh; those provider-specific OAuth flows must be configured before production publishing.

## Important product behavior

- Free plan: three AI generations per calendar month (Asia/Kolkata). Premium with `billingStatus == active` has no generation cap and may use direct publishing.
- Every AI caption moves to `pending_approval`; the app never auto-publishes an AI-generated caption.
- Publishing only starts on the explicit `approved_to_publish` transition and only for Premium accounts. Facebook and Instagram publish the composited image; the current X adapter publishes caption text only.
- Firestore events are at-least-once. Function handlers use transactional claims/idempotency markers and should be treated as retryable.
- Image selection/compression happens locally; the app targets a maximum of 1 MB per uploaded image.
- Firestore persistence is enabled where supported. Failed image/post submissions are recorded in a local retry queue.
- WhatsApp broadcast is a manual share workflow; the app saves the final image to the device gallery, copies the caption and opens the native share sheet with the image attached.

## Validation status

This is a generated project scaffold. It has not been connected to a real Firebase project, provider OAuth apps, billing provider, or KMS key. Run the setup and verification commands above before deployment. Never commit Firebase service-account keys, provider tokens, or generated Firebase configuration containing environment-specific credentials.
