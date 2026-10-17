# Flutter V2 Minimal Acceptance

**Date:** 2026-10-16  
**Scope:** Read-only review of `D:\flutter_app\wellar-flutter-app` against `D:\flutter\last\wellar-ai-v2`. No Flutter application source, V2 backend, Directus, legacy AI service, or private pilot data was edited or contacted. The requested Android build generated its normal debug build outputs.

## Decision

**The existing app can call standalone Wellar V2 without source edits**, provided the staging API uses Directus authentication and the mobile build receives the three V2 compile-time defines. No live staging endpoint was configured or exercised, so end-to-end staging acceptance is pending.

The feature flag defaults off. With it off or the signed-in Directus user absent from the allowlist, the existing scan flow continues into its legacy Directus scan path. With a valid HTTPS base URL, the flag on, and an allowlisted user ID, the flow switches to the direct V2 processing/result screens; that branch does not call the legacy AI URL or create a Directus scan record.

## Verified current behavior

- `lib/config/app_config.dart` defines `ENABLE_WELLAR_V2_SCANS` as false by default, plus `WELLAR_V2_BASE_URL` and comma-separated `WELLAR_V2_TEST_USER_ALLOWLIST`.
- `WellarV2Feature.enabledFor` requires the flag, a nonempty matching Directus user ID, and a valid HTTPS URL with no credentials, query, or fragment.
- `lib/screens/scan_flow_impl_normalized.dart` chooses mono 44.1 kHz PCM WAV when V2 is active; with V2 inactive it keeps AAC-LC recording and legacy finalization. After capture validation and consent, it pushes `WellarV2ProcessingScreen`; it does not send that scan through the legacy pipeline.
- `WellarV2Client` uploads raw JPEG, MP4, and WAV bytes with matching MIME types to `POST /api/v1/media/{image|video|audio}`; applies 5 MiB / 20 MiB / 8 MiB client limits and format checks; submits schema 1.0 with fixed `media_processing=true`, `research_use=false`, opaque media refs and an idempotency key; and omits caller-supplied tenant/subject IDs.
- The client sends `Session.instance.accessToken` as a bearer token, uses the existing Directus refresh once after a 401, and retries once with the refreshed token. Retryable ambiguous scan submission reuses the same idempotency key.
- The processing screen polls status every 1.2 seconds for up to two minutes, fetches the terminal result, then deletes uploaded media. If accepted work is cancelled or polling fails, media is retained for the worker/retention policy. There is no cancel-scan API.
- Result parsing is separate from legacy `ScanResult`. The UI shows unavailable/null targets and the non-predictive disclaimer; it does not translate V2 output into legacy readiness or risk scores.
- Backend `DirectusAuthenticator` validates the supplied token through Directus `/users/me`, requires an active user and active business profile, and verifies exactly one active matching `business_profile_members` record. The backend also supports OIDC, but its documented OIDC mode is incompatible with this app's Directus access token unless a separate OIDC token provider is added. Configure staging for `WELLAR_AUTH_MODE=directus`.

## Test and build results

- `rtk C:\flutter\bin\flutter.bat test --no-pub test\wellar_v2_client_test.dart --reporter expanded --timeout 20s` — **PASS, 14 tests**. Covers default-off flag, media bytes/MIME, rejected media, missing token, Directus refresh, scan contract, idempotency retry, cancellation, sanitized errors, status/result parsing, and media deletion.
- `rtk C:\flutter\bin\flutter.bat test --no-pub test\scan_service_projection_test.dart test\scan_result_model_test.dart --reporter expanded --timeout 20s` — **PASS, 5 tests**. Legacy projection/result parsing regressions pass.
- `rtk C:\flutter\bin\flutter.bat build apk --debug --no-pub` — **PASS**. Produced `build\app\outputs\flutter-apk\app-debug.apk`. This build used default compile-time values, so V2 remained disabled in that APK.
- No live staging request, authenticated Directus-to-V2 journey, physical Android camera/microphone capture, or Android install/interaction was run. Client tests use a fake HTTP adapter; they establish client contract behavior, not network acceptance.

The Flutter checkout contained numerous pre-existing modified and untracked files. They were preserved; no reset, restore, merge, dependency resolution, or source edit was performed.

## Exact configuration for isolated EasyPanel staging

Use a new HTTPS EasyPanel staging API origin, for example `https://<new-v2-staging-host>` (origin only; no `/api/v1`, path, query, credentials, or trailing slash). Build with:

```text
--dart-define=ENABLE_WELLAR_V2_SCANS=true
--dart-define=WELLAR_V2_BASE_URL=https://<new-v2-staging-host>
--dart-define=WELLAR_V2_TEST_USER_ALLOWLIST=<exact-active-Directus-user-id>
```

The allowlisted identity must have an active Directus user, active business profile, and exactly one active matching membership. The client allowlist is only a rollout gate; backend authentication/authorization remains authoritative.

Configure the isolated V2 service with at least:

```text
WELLAR_ENV=staging
WELLAR_QUEUE_BACKEND=postgres
WELLAR_POSTGRES_DSN=<staging-only TLS DSN with sslmode=verify-full>
WELLAR_POSTGRES_AUTO_MIGRATE=false
WELLAR_MEDIA_BACKEND=s3
WELLAR_S3_BUCKET=<new V2 staging bucket>
WELLAR_S3_REGION=<bucket region>
WELLAR_S3_ENDPOINT_URL=https://<private staging object-store endpoint>
AWS_ACCESS_KEY_ID=<staging-only secret>
AWS_SECRET_ACCESS_KEY=<staging-only secret>
WELLAR_AUTH_MODE=directus
WELLAR_DIRECTUS_URL=https://<Directus API origin>
WELLAR_MODEL_INFERENCE_ENABLED=false
```

Set remaining PostgreSQL/S3/auth secrets and limits in EasyPanel's secret/config store. Do not reuse production or legacy databases, buckets, credentials, or volumes. V2 currently has no validated model release, so accepted/completed work is expected to render insufficient-evidence/unavailable. This staging flow verifies integration, not fatigue inference.

On Android, use the HTTPS hostname with a valid publicly trusted certificate. No cleartext exception or source edit is required.

## Defects and remaining gate

No unavoidable Flutter source defect was found for a correctly configured staging service; **no source change is required**. The minimum blocker to live acceptance is an available isolated EasyPanel endpoint configured for Directus authentication and a test user with the required active membership. Until provisioned, the auth handshake and real-device upload/poll/result path remain unverified.
