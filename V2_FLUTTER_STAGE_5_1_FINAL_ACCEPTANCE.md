# Wellar AI V2 Flutter Stage 5.1 Final Acceptance

**Status: PARTIAL** — offline integration checks and Android debug build pass; live Directus and physical-device acceptance remain unrun.

## Implementation verified

- The existing V2 client uses the V2 `/api/v1/media/{modality}`, `/api/v1/scans`, status, result, and media-delete routes. Uploads pass raw `Uint8List` request bodies and set `image/jpeg`, `video/mp4`, or `audio/wav`.
- Client limits match the supplied backend defaults: JPEG 5 MiB, MP4 20 MiB, and WAV 8 MiB. JPEG SOI, MP4 `ftyp`, and RIFF/WAVE PCM 16-bit signatures are checked before upload. The recorder selects mono WAV in V2 mode; the actual camera codec and device-produced recording still require device verification.
- Scan submission uses schema `1.0`, fixed `media_processing: true` and `research_use: false`, no caller-supplied tenant or subject identity, and a stable key across its bounded retry. The client reads the current `Session.instance.accessToken`; one Directus refresh and one retry follow a 401.
- Status polling, result retrieval, request timeouts, idempotent ambiguous submission retry, and retention of uploaded media when submission outcome is unknown are implemented. Media cleanup occurs before acceptance or after terminal processing; accepted work retains its media on cancellation or polling failure.
- Result validation accepts only `insufficient_evidence` or `model_unavailable`, rejects numeric target values and model versions, and keeps V2 results separate from legacy scan models.
- V2 remains disabled by default. The V2 capture branch requires the feature flag, HTTPS endpoint, and exact allowlisted user ID. With the flag disabled, audio remains AAC, legacy pre-finalization runs, and `_finishScan` continues through the existing Directus scan path.

## Changes and preservation

- No Flutter application source files were edited; no integration defect requiring a code change was found.
- Therefore, no pre-edit source backup was needed. Existing owner work and mixed V2 changes remain in place.
- The report itself is the only new file from this acceptance work.

## Verification results

- `rtk C:\flutter\bin\flutter.bat test --no-pub test\wellar_v2_client_test.dart --reporter expanded --timeout 20s` — **PASS, 14 tests**. Covers default-off feature gate, raw media bytes/MIME, unsupported media rejection, token refresh/retry, schema/consent, stable idempotency and ambiguous retry, safe errors, status/result parsing, and media deletion.
- `rtk C:\flutter\bin\flutter.bat test --no-pub test\scan_service_projection_test.dart test\scan_result_model_test.dart --reporter expanded --timeout 20s` — **PASS, 5 tests**. Legacy scan projection and result parsing regressions passed.
- Targeted analysis of the five V2-specific Dart files — **exit 1: one lint**, `unnecessary_non_null_assertion` at `lib/services/wellar_v2_client.dart:343`. No analyzer errors were reported.
- Analysis including `scan_flow_impl_normalized.dart` — **exit 1: 52 existing warnings/infos**, including unused members, deprecated APIs, and the same non-null assertion. No analyzer errors were reported. Unrelated scan-flow warnings were not edited.
- `rtk C:\flutter\bin\flutter.bat build apk --debug --no-pub` — **PASS**, produced `build\app\outputs\flutter-apk\app-debug.apk`.
- `test/wellar_v2_live_http_test.dart` was **not run live**. The required live-test environment variables are absent, and the backend port `127.0.0.1:8000` is not listening. No credentials or media were guessed or printed.
- `flutter devices` found Windows, Chrome, and Edge only; **no Android or iOS device** was connected.

## Live acceptance boundary

- **Directus authentication:** Not verified live. The unit test verifies the one-refresh behavior with a synthetic injected token provider; the backend checkout’s security acceptance records live OIDC as partial without a configured live provider.
- **H.264 MP4:** Client and backend check the MP4 container signature. They do not prove the camera produced H.264 on this host. The backend’s real-media acceptance has H.264 evidence for its supplied sample, not this Flutter camera/device.
- **Real device:** Not verified. Camera codec, WAV output, permissions, capture duration/size, network routing, and UI behavior need a connected Android/iOS device.
- **AI predictions:** Remain unavailable; the V2 response validator rejects model versions and numeric target values.

## Minimum owner-side live run

Use an isolated non-production V2 HTTPS endpoint configured to validate a short-lived Directus-issued token and map it to one approved synthetic test subject. On the owner’s machine, set `WELLAR_V2_LIVE_TEST=1`, `WELLAR_V2_LIVE_BASE_URL`, `WELLAR_V2_LIVE_TOKEN`, `WELLAR_V2_LIVE_VIDEO`, and `WELLAR_V2_LIVE_AUDIO` locally (do not share values); use synthetic H.264 MP4 and PCM WAV files only. Then run:

```powershell
rtk C:\flutter\bin\flutter.bat test --no-pub test\wellar_v2_live_http_test.dart --reporter expanded --timeout 20s
```

After that API smoke passes, connect an approved Android/iOS test device, launch a build with V2 enabled only for that synthetic user and HTTPS endpoint, and verify one consented capture through the V2 result UI. Keep V2 disabled for production identities.

## One next action

Run the bounded live test above against the isolated HTTPS V2 endpoint with one Directus-authenticated synthetic identity and synthetic H.264/WAV media, then verify one capture on an approved physical device.
