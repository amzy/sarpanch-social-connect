# Firestore data model

## `users/{uid}`

Client-readable profile fields:

- `uid`, `sarpanchName`, `panchayatName`, `district`, `state`
- `primaryLanguage` (`English`, `Hindi`, `Marathi`, `Telugu`, `Tamil`, `Gujarati`)
- `imageUrl`, `sealUrl`, `createdAt`
- server-managed `plan`, `billingStatus`, `usage.aiGenerations.{YYYY-MM}`

The initial profile flow can create only the `free` plan. Billing webhooks/admin functions must be the only writer that grants Premium or changes billing status after onboarding. Do not allow clients to update `plan`, `billingStatus`, or usage counters.

## `users/{uid}/private/socialTokens`

Server-only credential record. Access tokens are Cloud KMS ciphertext; page/account IDs are identifiers. Firestore rules deny all client access. Do not copy this document into the public profile.

## `posts_queue/{postId}`

Client-created fields: `postId`, `uid`, `type`, `creationTimestamp`, `rawNotes`, `beforeImageUrl`, `afterImageUrl`, `finalCompositedImage`, `status`, `scheduledTime`.

Server-managed fields include `aiCaption`, `aiLanguage`, `aiGeneratedAt`, `aiUsageClaimed`, `aiUsageMonth`, `publishClaimed`, `publishResults`, `publishedAt`, `failureCode`, `failureMessage`.

Allowed status lifecycle:

```text
pending_ai -> pending_approval -> approved_to_publish -> published
      |               |                    |
      v               v                    v
    failed          rejected              failed
```

A user must review the caption and explicitly approve it. `published` means at least one configured channel succeeded; inspect `publishResults` for per-channel outcomes.
