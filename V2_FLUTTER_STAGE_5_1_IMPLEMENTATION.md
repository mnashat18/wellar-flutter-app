# Wellar AI V2 Flutter Stage 5.1

## Status

**Stage 5.1: PARTIAL.** The isolated direct V2 capture, upload, submission, polling, and result path is implemented behind a disabled-by-default rollout gate. The focused contract and legacy regression tests pass, and an Android debug APK builds. Whole-project analysis exits nonzero on repository-wide analyzer issues. Live Directus authentication and real-device acceptance remain unverified.

## Flutter files modified

- `lib/config/app_config.dart`
- `lib/services/wellar_v2_client.dart`
- `lib/screens/scan_flow_impl_normalized.dart`
- `lib/screens/wellar_v2_processing_screen.dart`
- `lib/screens/wellar_v2_result_screen.dart`
- `test/wellar_v2_client_test.dart`
- `test/wellar_v2_live_http_test.dart`

No backend, Directus, Angular, legacy AI Server, Docker volume, or existing backend data files were changed.

## Feature flag and rollback

- `ENABLE_WELLAR_V2_SCANS` defaults to `false`.
- `WELLAR_V2_TEST_USER_ALLOWLIST` is a comma-separated list of exact Directus user IDs. A user must be on this list, the flag must be enabled, and `WELLAR_V2_BASE_URL` must be valid HTTPS before the capture flow takes the V2 branch.
- `WELLAR_V2_BASE_URL` defaults to empty. No usable URL means the V2 branch stays unavailable.
- Rollback is to leave the flag off or remove the user ID from the allowlist. The existing Directus/legacy scan path remains the default.
- The allowlist controls rollout only. It is never sent to V2 or used as authorization.

## Authentication and media compatibility

`WellarV2Client` reads `Session.instance.accessToken` for each request. On an HTTP 401, it calls the existing `DirectusClient.instance.refreshAuthToken()` once and retries that request once with the refreshed access token. It does not pass tenant, subject, role, membership, employee, or Directus scan IDs to V2. V2 remains responsible for resolving and enforcing the authenticated tenant and subject.

Uploads use raw `Uint8List` request bodies and the V2 endpoint's exact content types:

- JPEG thumbnail: `POST /api/v1/media/image`, `image/jpeg`, maximum 5 MiB.
- MP4 capture: `POST /api/v1/media/video`, `video/mp4`, maximum 20 MiB.
- Recorder output: `POST /api/v1/media/audio`, PCM WAV, `audio/wav`, maximum 8 MiB.

The client checks file signatures and V2 `media_ref` syntax. Unsupported captures fail with a retake message; upload requests are not automatically replayed after ambiguous failures.

## Scan submission, status, and result

The app submits schema version `1.0`, the returned opaque `media_refs`, `media_processing=true`, `research_use=false`, and `reaction_task=null`. A cryptographically random `Idempotency-Key` is reused unchanged for the bounded safe submission retry. The existing focus UI is not serialized as reaction/PVT observations.

V2 status is polled from `GET /api/v1/scans/{scan_id}`. Backend `queued` and `processing` are displayed as queued and running; `completed` triggers `GET /api/v1/scans/{scan_id}/result`; `failed` remains a V2 failure state. Result presentation is isolated from the legacy result model. V2's `insufficient_evidence` and `model_unavailable` responses and unavailable target reasons are shown without inventing scores. Insufficient or failed media quality produces retake guidance. The client rejects result payloads that contain numeric target predictions or a model version, consistent with the current V2 response contract.

V2 scan IDs and results remain in the V2 flow and are not inserted into Directus scan records or histories. No manager or HR cross-user scan view was added.

## Backups

Modified Flutter files were copied before editing. Backup hashes and final source hashes are in [stage-5.1-FINAL-SHA256.json](.backups/stage-5.1-FINAL-SHA256.json). Backup copies are in:

- `.backups/stage-5.1-20261015-221819/`
- `.backups/stage-5.1-tests-20261015-222203/`

## Verification

- `dart format` formatted the changed Dart sources. Dart then exited 1 because it could not update its telemetry timestamp outside the writable workspace (`C:\Users\Abdulrhman Nashat\AppData\Roaming\.dart-tool\dart-flutter-telemetry-session.json`: Access denied). The source formatting itself completed.
- Focused Flutter tests passed: `wellar_v2_client_test.dart`, `scan_service_projection_test.dart`, and `scan_result_model_test.dart` — **19 tests passed**. This includes JPEG/MP4/WAV raw upload contracts, fixed consent, idempotency, Directus token refresh/retry, and existing scan projection behavior.
- `flutter analyze` exited 1 with **319 analyzer issues** across the existing repository, primarily warnings and infos. The analyzer run did not produce a clean project pass.
- `flutter build apk --debug --no-pub` — **passed**, producing `build/app/outputs/flutter-apk/app-debug.apk`.
- No live V2 endpoint, Directus token, production session, device camera/microphone, or mobile network authentication run was performed.

## Remaining acceptance checks

- Configure a non-production HTTPS V2 URL backed by the actual Directus authenticator and allowlist one synthetic test employee.
- Verify one live Directus refresh followed by V2 upload and scan status/result on Android and iOS devices.
- Confirm image thumbnail and recorder WAV compatibility across target devices and test cancellation/ambiguous submission recovery.

## Next action

Run a live staging acceptance with one allowlisted synthetic employee and real Directus-issued credentials before enabling the rollout flag for any additional test users.
