# Development Plan

## Milestone 1 — Foundation & design system
- Centralized six-theme palette and semantic Material 3 light/dark themes.
- Persist theme and appearance preference.
- English-only app locale; keep post content language independent.
- Shared branding and design standards.
- Appearance settings screen.

## Milestone 2 — Core application
- Authentication and onboarding.
- Panchayat profile and official branding settings.
- Dashboard and primary navigation.
- Role and tenant access model.

## Milestone 3 — Content studio
- Post categories and reusable forms.
- Before/after image compositor and media library.
- AI caption generation with content-language control.
- Poster templates, review and approval.

## Milestone 4 — Social media manager
- OAuth account connection and capability discovery.
- Secure server-side credential storage.
- Multi-destination publishing jobs and delivery records.
- Calendar, retry handling and platform analytics.

## Milestone 5 — Government information hub
- Official source registry.
- Jobs, schemes, programs and notifications ingestion.
- Geographic filtering, deduplication, revisions and expiry.
- Source-grounded AI summaries and post conversion.

## Milestone 6 — Village development & citizen services
- Project tracker, evidence and status history.
- Citizen service directory and awareness workflows.
- Public engagement with privacy controls.

## Milestone 7 — AI intelligence and release
- Content suggestions, profile health and analytics.
- Security, accessibility, integration and device testing.
- Firebase deployment and store readiness.

## Engineering gates
- Every milestone must pass static analysis and relevant automated tests.
- No production secrets or OAuth tokens in client-readable documents.
- Government information must preserve official source references and verification dates.
- AI-generated content requires human approval before publishing.
- Platform deliveries are tracked independently and retried idempotently.
