# Mobile Security and Employee Privacy Review

**Scope:** static review of the Flutter repository and checked-in configuration snapshots. This is not a live Directus authorization test, mobile binary inspection, or legal/privacy compliance determination. No code/config changes were made.

## Summary

Positive controls include secure-storage-backed token persistence (`lib/state/session.dart`), Directus bearer-token refresh with a single-flight path (`lib/services/directus_client.dart`), HTTPS defaults in `lib/config/app_config.dart`, Android cleartext traffic disabled, and camera/microphone purpose strings/permissions on iOS/Android. Main concerns are sensitive identifiers and local file paths in debug output, a bearer token sent from the app to a separate AI host, inconsistent token refresh for that host, uncertain media retention, and the inability to verify deployed role policies from checked-in snapshots.

## Findings

| Priority | Area | Evidence and risk | Minimal recommendation |
|---|---|---|---|
| P0 | Scan idempotency / cost abuse | `lib/services/scan_finalize_service.dart` dispatch tracking is in-memory; `/process` accepts a scan ID but client-side code has no durable outcome or proof of server idempotency. A timeout can conceal successful acceptance. | Persist state and reconcile server status before retry. Require backend owner confirmation that scan ID is an idempotency key; maintain existing API shape until a compatible server contract is approved. |
| P1 | Logs contain employee/device data | `lib/utils/video_compress_io.dart` logs full local paths and errors. `lib/services/member_identity_service.dart` has logs containing profile/member IDs and relation data; scan-flow output includes scan/workspace/membership IDs. `safe_debug_log.dart` is not used by every direct `debugPrint` call. | Remove path, email, member/profile, scan, and response-body values from routine logs; use allow-listed structured fields and gate diagnostic logs by build mode. Review crash breadcrumbs for the same fields. |
| P1 | Cross-host bearer token exposure surface | `lib/services/scan_service.dart` `triggerAiServerProcess` sends the Directus access token as a bearer credential to `AppConfig.aiServerUrl`, a distinct host. TLS is enabled by default, but any alternate configured host and the AI service’s token validation/scope are outside mobile proof. | Confirm the AI host is trusted and validates audience, role, tenant and scan ownership. Prefer a narrowly scoped short-lived process credential or authenticated app/API proxy in a future coordinated design; never embed secrets in the app. |
| P1 | AI dispatch does not use Directus refresh behavior | `/process` uses a raw Dio with 15s/30s timeouts, unlike `DirectusClient`’s 401 refresh flow. A stale access token can fail while the rest of the app refreshes successfully. Blind retry after refresh is unsafe until server idempotency is established. | Route authorization through a shared, audience-correct auth abstraction; on 401 refresh once, then reconcile scan state before any dispatch retry. Do not send a Directus token to a different audience unless explicitly accepted by backend security. |
| P1 | Deployed authorization cannot be verified | `backend/directus/permissions/directus-permissions-app-collections.commit-safe.json` contains intended employee self-scoped filters for wellness scans/results/media and broader manager/HR/owner scopes. It also includes an AI Server Access policy with broad collection permissions for its assigned role. Checked-in snapshots do not prove what is deployed or which roles are assigned. | Verify deployed role-policy bindings and test as employee, manager, HR, owner, and AI service. Ensure employee cannot enumerate other users’ scans/media/results; verify tenant boundaries on every read/write and asset download. |
| P1 | Media retention/local copies | `lib/utils/video_compress_io.dart` configures `deleteOrigin:false`; scan flow and upload helpers use temporary video/audio artifacts, and cleanup is not evident on success, failure, or retake. Biometric-like video/audio is sensitive even if not stored in app database. | Inventory exact plugin cache/temp paths per platform, purge after upload/cancel, bound offline retention, protect files with app-private storage, and provide documented server retention/deletion behavior. Avoid persisting raw media for background retry unless encrypted and consented. |
| P1 | Shared request retry risk | `lib/services/directus_client.dart` retries transient requests broadly; `lib/services/scan_service.dart` retries video upload on 502. Replayed creates/uploads can create duplicate or orphan data. | Classify retry safety per operation; automatically retry reads only. Reconcile ambiguous writes; add explicit deduplication only where the deployed server supports it. |
| P2 | Token storage and lifecycle verification | `lib/state/session.dart` uses `FlutterSecureStorage` for access and refresh tokens, which is preferable to preferences. Platform secure-storage plugin configuration, Android backup exclusions, iOS Keychain accessibility, logout invalidation and refresh-token rotation should be validated in built artifacts. | Confirm backup behavior excludes secrets, use appropriate Keychain accessibility, clear local job bindings on logout/account switch, and test refresh-token rotation and revocation. |
| P2 | Central crash reporting absent | `lib/main.dart` logs top-level Flutter/platform errors; `pubspec.yaml` lacks a crash-reporting dependency. | Select/enable a privacy-approved crash service with redaction and retention controls; never attach raw scan payloads, tokens, paths, email, or media. |
| P2 | Network transport | Android manifest disables cleartext and AppConfig defaults are HTTPS. Runtime `--dart-define`/environment overrides still need deployment validation; no certificate pinning assessment was performed. | Enforce HTTPS at configuration validation and monitor endpoint changes; do not add pinning without rotation/recovery plan. |

## Privacy/data handling questions requiring owner confirmation

- What are server retention and deletion windows for raw video/audio, thumbnails, `scan_media`, scan metadata and AI results?
- Are AI providers/subprocessors, regions, retention, and employee notice/consent represented in deployment policy? This repository alone cannot establish them.
- Are local files backed up by OS/device backup or included in support/crash attachments?
- Are IDs in device logs collected centrally by MDM/support tooling, and what is their retention?
- Is consent captured before both camera and microphone capture and revocable before upload? Verify full UX/platform behavior, not just persisted scan flags.

## Security regression checks

1. Authorization matrix against the deployed API: employee A cannot read employee B’s scan, result, or media by guessing IDs; cross-tenant IDs fail; management roles see only assigned scope.
2. Transport: cleartext endpoints rejected; production config points only to approved HTTPS hosts; AI service validates intended audience and tenant/scan ownership.
3. Token: refresh rotation, simultaneous 401 single-flight, revoked refresh token, logout/account switch, and stale token during AI dispatch. Assert no token appears in logs.
4. Privacy logging: seed test email/member/profile IDs and local paths; assert no values appear in debug/release logs, crash breadcrumbs, or error messages.
5. Media: inspect Android/iOS temp/cache/backup behavior; test success, cancel, crash, failed upload and re-login cleanup; assert retention bounds.
6. Retry: simulate server accepting then dropping response for scan create, media upload, and AI process; assert no blind duplicate work.
