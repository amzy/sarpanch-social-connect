# Production readiness checklist

- [ ] Run `flutterfire configure` and register Android/iOS app IDs.
- [ ] Enable Phone Auth, Firestore, Storage, Functions v2 and App Check in Firebase.
- [ ] Configure KMS key, IAM encrypt/decrypt permissions and function secrets.
- [ ] Add a trusted billing webhook/admin function; client onboarding is constrained to Free only.
- [ ] Implement Meta and X OAuth consent/callback flows, refresh-token handling, revocation and permission review.
- [ ] Confirm Meta Graph API version, Page permissions, Instagram professional account linkage and public image URL requirements.
- [ ] Confirm X OAuth 2.0 user-context scopes and token refresh; current X adapter publishes text only (image attachment is not implemented).
- [ ] Decide whether scheduling uses Cloud Tasks or a scheduled dispatcher; `scheduledTime` is stored but current approval dispatch is immediate.
- [ ] Add App Check initialization and enforce it on callable functions after platform registration.
- [ ] Add integration tests against Firebase Emulator Suite and provider mocks.
- [ ] Add retry worker for local queued uploads and server-side failed channel dispatches.
- [ ] Review consent, privacy notice, data retention, audit logs and account deletion workflows.
- [ ] Verify image compression and share flows on physical low-memory Android devices and iOS devices.
