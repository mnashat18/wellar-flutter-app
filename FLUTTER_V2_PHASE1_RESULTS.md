# Flutter ↔ Wellar AI V2 Phase 1 Results

Date: 2026-10-14  
Scope: additive Flutter client integration for an explicitly enabled local V2 development path. No V2/backend source, production environment, legacy AI service, or Directus service was modified or contacted.

## 1. Canonical Repositories and Git Baseline

- Flutter root: `D:\flutter_app\wellar-flutter-app` (owner-confirmed). Git root is this path, branch `main`, tracking `origin/main`.
- Standalone V2 root: `D:\flutter\last\wellar-ai-v2` (owner-confirmed). The root has no `.git` metadata, so a Git status/commit baseline is unavailable. Its local `.venv`, source tree, tests and dependency artifacts were present. Python in that environment reported 3.10.11 during tests.
- Flutter already had extensive modified and untracked work before this task. Among the pre-existing changes were `lib/config/app_config.dart`, `lib/screens/scan_flow_impl_normalized.dart`, `lib/services/scan_service.dart`, `lib/services/scan_finalize_service.dart`, the Directus/auth/workspace screens and services, `pubspec.yaml`/lockfile, platform manifests, tests, and several untracked audit documents including `FLUTTER_COMPLETE_SYSTEM_AUDIT.md`. These were preserved; no reset, stash, checkout, cleanup or restore was performed.
- Baseline Flutter tests were attempted before edits, but the Flutter tool did not produce output while Dart could not start its child process in the sandbox. The baseline suite therefore did not complete before implementation. Subsequent regression results are reported separately; they are not presented as a baseline comparison.

## 2. Exact Source Files Changed for Phase 1

Implementation changes in this task:

1. `lib/config/app_config.dart` — added disabled-by-default local V2 compile-time configuration.
2. `lib/services/wellar_v2_client.dart` — new isolated authenticated V2 HTTP client.
3. `lib/models/wellar_v2_result.dart` — new V2-specific, nullable result model.
4. `lib/screens/scan_flow_impl_normalized.dart` — additive consent, WAV capture selection, no-legacy/no-Directus-preupload branch and local V2 handoff.
5. `lib/screens/wellar_v2_processing_screen.dart` — new upload/submit/poll/cancel/cleanup workflow.
6. `lib/screens/wellar_v2_result_screen.dart` — new V2-only non-predictive result display.
7. `test/wellar_v2_client_test.dart` — new adapter-backed tests.
8. `android/app/src/debug/AndroidManifest.xml` and new `android/app/src/debug/res/xml/wellar_v2_debug_network_security_config.xml` — debug-only cleartext exceptions restricted to local development hosts. The main/release manifest still disallows cleartext.
9. This report.

No package/dependency changes were made. No V2 files were modified.

## 3. Actual V2 API Contracts Inspected

Contract evidence is in `app/api/v1.py`, `app/scans/schemas.py`, `app/scans/service.py`, `app/media/storage.py`, `app/security/auth.py`, `app/media/contracts.py`, `app/workers/worker.py`, and `tests/test_api.py` in the V2 root.

| Route | Verified request/response behavior |
|---|---|
| `POST /api/v1/media/{video,image,audio}` | Authenticated raw request body; modality-specific `Content-Type`; returns HTTP 201 with opaque `media_ref`, modality, content type and byte count. Current V2 storage accepts MP4/AVI, JPEG/PNG and WAV (`audio/wav` or `audio/x-wav`) and checks signatures. Local default caps are video 20 MiB, image 5 MiB, audio 8 MiB; deployment configuration can change them. |
| `DELETE /api/v1/media?media_ref=...` | Authenticated owner-scoped delete; HTTP 204 on success, 404 if unavailable. The V2 media store binds refs to authenticated tenant and subject. |
| `POST /api/v1/scans` | Authenticated JSON, required `Idempotency-Key` (service caps key length at 128), returns HTTP 202 with `scan_id`, status and whether created; `Location` points to status route. Payload schema is `schema_version: "1.0"`, `media_refs`, optional `reaction_task`, and consent. With media, both `media_processing` and `research_use` must be true. Duplicate modality/ref validation is server-side. |
| `GET /api/v1/scans/{scan_id}` | Authenticated tenant/subject-scoped status response with `scan_id`, status, timestamps and retryable flag. Current queue states include queued, processing, completed and failed. |
| `GET /api/v1/scans/{scan_id}/result` | Authenticated result; 404 `result_unavailable` until available. Schema version 2.0. Current worker returns `insufficient_evidence`, null model version, `not_invoked_no_validated_model`, unavailable/null target values, quality/features and explanatory message. |

V2 development auth maps an opaque bearer token to a configured principal. OIDC auth validates signature, issuer, audience, required time/subject/tenant claims and configured asymmetric algorithms. V2 never treats client-supplied tenant/subject fields as identity. Flutter sends neither field.

Reaction-task schema requires `schema_version`, task type and ordered per-trial stimulus/response timestamps. Current Flutter focus UI does not yield this compatible event series; it is omitted from V2 requests.

## 4. Flutter Capture Compatibility Findings

- Video source is `ScanFlowScreen` (`lib/screens/scan_flow_impl_normalized.dart`): camera plugin, front lens when available, video capture, followed by `compressVideo`. Compression requests 1280×720/30fps profile; the source path is treated as MP4 and processing may return the original when compression fails. Mobile code does not inspect H.264 codec metadata. V2 accepts MP4 by container/signature and worker decoding remains authoritative. Client checks for MP4 `ftyp` signature and the documented local 20 MiB cap; this does not certify codec quality or scientific usability.
- Audio baseline was AAC-LC in an `.m4a` path, incompatible with V2 WAV intake. When local V2 is requested, the recorder now checks `AudioRecorder.isEncoderSupported(AudioEncoder.wav)`, requests WAV, and uses a `.wav` name. If the device does not support WAV, the flow stops with a clear error. Before upload, client verifies RIFF/WAVE, PCM encoding value 1, 16-bit samples and the V2 8 MiB cap. Runtime plugin output still needs device verification; mislabeled AAC cannot pass this validation.
- Flutter’s existing thumbnail is derived from the captured video. It is not uploaded as an image because the V2 demonstration must not fabricate an independent image input. No standalone image capture path exists in this scan flow.
- The existing focus game is bypassed in the V2 route. No aggregate tap count or fabricated trial timestamps are submitted. No PVT/scientific validity is claimed.
- Consent is explicit: when V2 is requested, the user must accept a distinct local research-use checkbox as well as the existing consent. The updated copy explains local video/WAV transfer, no focus task, no Directus history write, and no validated fatigue/vigilance prediction.

## 5. Identity and Authentication Design

- The V2 client uses a distinct compile-time `WELLAR_V2_DEV_TOKEN`. It never reads `Session.accessToken`, never shares `DirectusClient`, and does not attempt Directus refresh against V2.
- The V2 client adds only the bearer token to requests. It never sends `tenant_id` or `subject_id`; V2 derives both from its authenticated principal.
- Local mode requires explicit dev declarations `WELLAR_V2_DEV_TENANT=synthetic-tenant` and `WELLAR_V2_DEV_SUBJECT=synthetic-user`; V2 itself must map the provided temporary token to exactly that principal through `WELLAR_DEV_AUTH_TOKENS_JSON`. Client-side declarations are a guard and are not treated as authorization proof.
- No real OIDC issuer/audience/JWKS configuration or verified V2-compatible Directus identity exchange was available offline. Production identity integration is therefore blocked; Directus JWTs must not be reused. Local synthetic mapping is the only supported Phase 1 identity mode.
- API errors/logging do not print token, media bytes, media refs, scan IDs or response bodies. API diagnostics are limited to sanitized event/status/modality.

## 6. Feature Flag and Safe Defaults

`ENABLE_LOCAL_WELLAR_V2` defaults to `false`. Setting it alone does not allow V2: the build must be non-release, the base URL must be an HTTP(S) loopback or Android emulator host alias (`localhost`, `127.0.0.1`, `::1`, `10.0.2.2`), a separate token must exist, and the explicit synthetic identity declarations must match. When the flag is requested but configuration is invalid, the scan shows an error and does not fall back to the legacy path. Release builds always reject this local auth mode.

The V2 base URL defaults to `http://127.0.0.1:8000`. No production or release URL was configured. Android’s debug-only Network Security Config permits cleartext only to listed local hosts; `src/main/AndroidManifest.xml` remains `usesCleartextTraffic=false`. iOS has no debug-specific ATS exception in this project, so local HTTP is not enabled there.

## 7. Implemented V2 API Operations

`WellarV2Client` implements raw video/audio byte uploads, scan submission, status retrieval, result retrieval and media deletion. It uses 20-second connect/send/receive bounds and a Dio cancellation token. It does not retry non-idempotent media upload/delete. Scan submission retries at most once for retryable/ambiguous transport/server conditions, with the same request body and idempotency key. The key is generated once per in-memory flow using secure random bytes. GET polling is bounded by a two-minute screen deadline and 1.2-second interval; `result_unavailable` is retried by the polling loop until deadline. `failed` is terminal. Errors are mapped to bounded codes and generic safe messages.

Media uploads that have known refs are deleted on definitive pre-acceptance failure and after terminal completion/failure. If scan acceptance is ambiguous (connection timeout, HTTP 408/429/5xx) refs are retained to avoid deleting media that an accepted worker may consume; V2 retention is the fallback. If the app is cancelled after acceptance, V2 has no scan-cancel route, so processing can continue and server retention applies. A lost upload response can leave an unknown ref until server retention. No durable client retry queue or cross-restart idempotency store was added.

## 8. End-to-End Workflow Diagram

```mermaid
sequenceDiagram
    actor User
    participant Flutter as Flutter scan flow
    participant Device as Camera / record plugin
    participant Temp as Local temporary files
    participant V2 as Local Wellar AI V2 API
    participant Worker as V2 worker
    User->>Flutter: Enable local flag, accept V2 research consent
    Flutter->>Device: Capture short MP4 video
    Device->>Temp: Write video
    Flutter->>Temp: Compress/check video; no thumbnail upload
    Flutter->>Device: Check WAV encoder, capture PCM WAV
    Device->>Temp: Write WAV
    Flutter->>V2: POST /api/v1/media/video (raw video/mp4)
    V2-->>Flutter: opaque media_ref
    Flutter->>V2: POST /api/v1/media/audio (raw audio/wav)
    V2-->>Flutter: opaque media_ref
    Flutter->>V2: POST /api/v1/scans + consent + Idempotency-Key
    V2-->>Flutter: 202 scan_id/status
    V2->>Worker: queued scan (V2 internal)
    loop bounded polling
        Flutter->>V2: GET /api/v1/scans/{scan_id}
        V2-->>Flutter: queued/processing/completed/failed
    end
    Flutter->>V2: GET /api/v1/scans/{scan_id}/result
    V2-->>Flutter: V2 schema 2.0; insufficient_evidence/null targets
    Flutter->>V2: DELETE /api/v1/media?media_ref (terminal result)
    Flutter-->>User: V2-specific non-predictive result
```

No Directus or legacy AI participant is involved in this branch. The worker is shown because V2 source defines queued processing and the backend self-test exercises it; no particular model inference is implied. V2's current worker explicitly returns insufficient evidence.

## 9. Directus Workflows Preserved

With the flag off (default), existing scan behavior is unchanged: the established Directus + legacy processor path remains. With V2 requested, the Flutter scan flow branches before `createWellnessScan`; Directus media prefinalization is explicitly skipped, Directus scan/media/result records are not created or patched, and the legacy `triggerAiServerProcess` path is not reached. Existing Directus auth, profiles, workspaces, requests, dashboards, history and reports are not replaced.

Cross-system integration gap: V2 results are displayed in the V2-specific screen but are not durable in Directus history/company reporting, and a request-linked scan is not reconciled or marked completed in Directus. Solving that requires a separately designed durable reconciliation contract; Phase 1 intentionally does not use fragile client dual writes or manufacture legacy `scan_results`/readiness scores.

## 10. Legacy Endpoint Avoidance Verification

The V2 branch skips both Directus scan finalization and `_startWorkflowIfNeeded`, where `ScanFinalizeService` would call `ScanService.triggerAiServerProcess`. Its code only references the V2 client. The local V2 client has no import/reference to `ScanService`, `DirectusClient`, `AI_SERVER_URL` or `/process`. `AI_SERVER_URL` remains unchanged for the disabled legacy path; there is no silent fallback or dual processing.

V2 client tests assert all exercised paths are under `/api/v1`, verify missing token sends no request, and exercise V2 media/status/result/delete. Static source review confirms no Directus mutation is made by the new processing screen. No production API was called.

## 11. Automated Tests and Analysis

| Suite/check | Result |
|---|---|
| New Flutter V2 client tests | **10 passed**. Includes disabled flag, raw MP4/WAV media and content types, bad format rejection before request, missing auth no request, DTO/consent/idempotency, same key on safe retry, auth rejection sanitized/no retry, media deletion, nullable insufficient-evidence result parsing and key generation. |
| Flutter scan-related regression set (`scan_service_projection`, polling policy, result model/display, failure mapper, new V2 tests) | **28 passed**. |
| V2 backend suite (`pytest -p no:cacheprovider -q`) using installed `.venv` | **68 passed, 1 skipped**, one deprecation warning. PostgreSQL integration skipped because `WELLAR_TEST_POSTGRES_DSN` is not configured. This run included API, auth, media, worker, queue and disposable runner tests. |
| V2 disposable process runner test rerun | **1 passed**; it exercises local HTTP + worker and cleanup with generated synthetic fixture data. No Flutter client was part of that test. |
| Full Flutter suite | **Incomplete / failing.** Parallel run observed 47 passing tests and 6 failures before stalling in a pre-existing stale workspace-switch test. Sequential run reproduced auth journey expectations for missing `WorkspaceAccessScreen`/registration control and a workspace-switch server-confirmation failure, then stalled on the stale-switch test; it was interrupted without a final suite summary. Do not treat this as a passing full suite or a clean baseline comparison. |
| Flutter analyzer on modified scan/new client files | Completed with **0 errors** and 53 infos/warnings, all reported in the large pre-existing `scan_flow_impl_normalized.dart` (existing deprecations/unused fields and analyzer infos). New client/result/config files have no analyzer diagnostics. |

The initial baseline test attempt did not complete before edits because of sandbox child-process restrictions/tool startup; the full-suite results above are post-change observations. No dependency install/download occurred.

## 12. Actual Local Runtime Verification

No Flutter app/device/emulator was launched and no live Flutter-to-V2 HTTP call was made. Flutter widget tests run under `TestWidgetsFlutterBinding`, which prevents ordinary HTTP from reaching the network; a physical/emulator device and a V2 auth token mapped to the synthetic principal were not configured. The V2 backend’s own disposable API/worker self-test passed in its test suite, but this does not prove the Flutter client on a device.

Android debug cleartext is now restricted to local development hosts. Android emulator should use `http://10.0.2.2:8000` to reach the host’s loopback API. Android `127.0.0.1` refers to the emulator itself. iOS ATS/local networking needs a debug-only configuration or a locally trusted HTTPS endpoint before using the default HTTP URL. Physical-device LAN hosts are intentionally rejected by the Flutter local-host guard.

## 13. Errors, Retries and Cancellation

- Missing/invalid local config blocks before request; a server 401/403 is sanitized and not retried.
- Media signature/size failure blocks before request; upload itself is never retried because an uncertain retry could create duplicate objects.
- Scan submission uses one generated idempotency key across its bounded safe retry.
- Poll requests are bounded; transient status request failure is surfaced rather than retried indefinitely; result-unavailable is treated as pending.
- `failed` is terminal. Unknown statuses, mismatched scan IDs/schema versions, non-null target values, model version presence or unexpected model invocation state are rejected rather than displayed as predictions.
- User cancellation stops client requests. V2 currently has no scan cancellation endpoint; a previously accepted worker may continue. Media is preserved after acceptance until terminal status or V2 retention.

## 14. Security and Privacy

- No token is hardcoded. Dev token must be separate from Directus and synthetic-only; production OIDC/issuer/audience alignment remains unverified.
- Tenant and subject authorization are derived only from V2 auth principal, not request JSON or Directus workspace IDs.
- V2 is local host only, release mode rejects this integration, and default feature flag is off.
- Explicit consent distinguishes V2 research-use from existing readiness consent. No image extraction, thumbnail upload, focus-game event submission or scientific score generation occurs.
- File media is temporary on device and uploaded to V2. Flutter deletes known refs after terminal result/rejection where safe; accepted ambiguous jobs and unknown upload refs are bounded by V2 server retention. Local source cache cleanup is not guaranteed by plugin; this Phase 1 does not add a persistent media ledger.
- Android cleartext exception exists only in debug source/resources and matches local endpoints. Main/release manifest remains cleartext-disabled. iOS local HTTP remains blocked pending a safe debug-only route.

## 15. Remaining Device, Backend and Identity Blockers

1. No production OIDC client-token issuance/audience/tenant-claim contract between Directus identity and V2 is available. Directus JWT cannot be reused. A verified identity broker/issuer contract is required before production use.
2. No actual temporary V2 dev token mapping was configured or exercised from Flutter. Local V2 mode must only be enabled when the backend token map binds the token to exactly `synthetic-user` / `synthetic-tenant`.
3. PCM WAV recording support is plugin/platform dependent and must be exercised on target Android/iOS hardware; unsupported encoders block scans.
4. No Android/iOS real-device build/runtime integration was run. iOS ATS does not permit the default local HTTP setup yet.
5. Directus reporting/history and assigned-request reconciliation are intentionally absent for V2 results.
6. Local idempotency state is in-memory only; app process restart recovery is not implemented.
7. Full Flutter suite is not green/completed due pre-existing modified auth/workspace test failures/stall; investigate those independently before release.

## 16. Exact Next Steps for a Safe Local Full-Scan Check

1. In the V2 development environment, create a short-lived opaque token mapped only to `sub=synthetic-user` and `tenant_id=synthetic-tenant`. Do not use employee data or a Directus/production token. Set `WELLAR_ENV=development`, `WELLAR_AUTH_MODE=development`, `WELLAR_QUEUE_BACKEND=sqlite`, `WELLAR_MEDIA_BACKEND=local`, and temporary `WELLAR_DB_PATH`/`WELLAR_MEDIA_ROOT` outside the V2 source tree.
2. Start `app.main:app` bound to `127.0.0.1:8000` and `python -m app.workers.entrypoint` in a second terminal with the same disposable environment. Keep both local and stop them after the test; remove only the explicitly created temporary test directory after confirming both processes stopped.
3. For Android emulator, run a debug build with `WELLAR_V2_BASE_URL=http://10.0.2.2:8000`. For desktop/iOS simulator use a permitted loopback URL; for iOS first configure a debug-only ATS/local HTTPS path. Do not use a physical LAN host because Phase 1 restricts local hosts.
4. Run Flutter with explicit `--dart-define=ENABLE_LOCAL_WELLAR_V2=true`, the loopback base URL, the temporary `WELLAR_V2_DEV_TOKEN`, and exact synthetic tenant/subject declarations. Do not put a real identity token in build defines.
5. In the app, accept the distinct V2 research-use checkbox, capture a short video and verify WAV support. Expected output is `insufficient_evidence`, null targets, no Directus history row and no readiness score. Verify V2 media cleanup after terminal result and inspect server logs for no token/media payload. Stop API/worker and clean temporary SQLite/media state.

Commands already verified offline:

```powershell
# Flutter fake-adapter contract test
rtk proxy cmd.exe /d /c "set DART_SUPPRESS_ANALYTICS=true&& C:\flutter\bin\flutter.bat test test\wellar_v2_client_test.dart --reporter expanded"

# V2 tests; run from D:\flutter\last\wellar-ai-v2
rtk proxy cmd.exe /d /c "set PYTHONDONTWRITEBYTECODE=1&& D:\flutter\last\wellar-ai-v2\.venv\Scripts\python.exe -m pytest -p no:cacheprovider -q"
```

## 17. Phase 1 Limitations

This is an opt-in local demonstration path, not production integration. It does not connect production identity, persist V2 results to Directus, reconcile requests/workforce reports, resume after app restart, cancel accepted server jobs, or promise device-wide media compatibility. V2 currently does not provide a validated fatigue/vigilance model; the app deliberately displays only its V2-specific insufficient-evidence output and nullable targets. No production-readiness, scientific-validity, latency-capacity or real-device claim is made.
