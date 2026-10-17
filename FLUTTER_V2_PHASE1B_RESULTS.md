# Wellar Flutter → V2 Phase 1B Results

**Outcome:** The dedicated Flutter V2 client was exercised against a disposable standalone V2 API and separate worker over real HTTP. The Flutter client reached the API, uploaded synthetic MP4 and PCM WAV media, submitted a scan, replayed the same idempotency key, observed a pending result, received the completed V2 result, and deleted both media objects. The Android emulator also reached the host API over `10.0.2.2`. The actual capture-screen journey was not run: reaching it requires the app's Directus identity flow, and no production identity/API was used.

## 1. Repositories and Git Baseline

- Canonical Flutter checkout: `D:\flutter_app\wellar-flutter-app`. This is a Git working tree on branch `main`. Before adding this report, `git status --short` reported 135 modified/untracked entries across the checkout; final status is 136 with this report included. The checkout contained extensive dirty work already present when this verification began. No reset, stash, checkout, revert, cleanup, branch switch, or commit was performed. Existing modifications were preserved.
- Canonical V2 source: `D:\flutter\last\wellar-ai-v2`. The source root, `app/`, `tests/`, and `.venv` exist. `git rev-parse` reports that this directory is not a Git repository, so V2 Git status/diff is unavailable. V2 source and tests were read/run without editing its files.
- Installed local tools: Flutter at `C:\flutter`, V2 virtualenv Python at `D:\flutter\last\wellar-ai-v2\.venv`, ffmpeg on PATH, Android SDK `adb`, and emulator 36.6.11. No dependency install or download occurred.
- A pre-Phase-1B baseline suite result is unavailable. Auth/workspace tests and code were already dirty at the start of this phase; their current failures cannot be labelled pre-existing with certainty.

## 2. Exact Phase 1B Changes

Phase 1B changed or added:

- `lib/services/wellar_v2_client.dart`: defensive normalization of malformed/non-object HTTP error bodies, preventing dynamic-map cast failures from bypassing safe error handling.
- `test/wellar_v2_client_test.dart`: tests for timeout retry with the same idempotency key, cancellation before adapter/network access, and malformed HTTP error bodies.
- `test/wellar_v2_live_http_test.dart`: opt-in, real HTTP workflow test. It is skipped by default and takes credentials, URLs, and generated media paths only from the harness process environment.
- `tool/phase1b_local_http.py`: disposable local runner. It creates a random short-lived synthetic token, generated media, temporary SQLite/media storage, and separate V2 API and worker processes; it verifies emulator TCP routing; then it stops services and removes temporary state.
- `FLUTTER_V2_PHASE1B_RESULTS.md`: this results report.

Phase 1's separate V2 implementation remains in the existing dirty tree, including `lib/config/app_config.dart`, `lib/screens/scan_flow_impl_normalized.dart`, the V2 client/model/screens, and Android debug network configuration. Those files were not rewritten during this phase. Current status marks them modified or untracked; the pre-existing contents were preserved.

## 3. V2 API Contract Inspected

The implementation and tests in `app/api/v1.py`, `app/media/storage.py`, `app/workers/entrypoint.py`, `app/workers/worker.py`, `app/media/analysis.py`, and the V2 `tests/` tree establish:

| Operation | Contract observed |
|---|---|
| `POST /api/v1/media/video` | Raw request bytes, `video/mp4`; returns 201 and opaque `media_ref`. MP4 intake checks the `ftyp` signature and configured size limits. |
| `POST /api/v1/media/audio` | Raw request bytes, `audio/wav`; returns 201 and opaque `media_ref`. WAV parsing/processing is server-side. |
| `POST /api/v1/scans` | JSON `schema_version: "1.0"`, `media_refs`, nullable `reaction_task`, consent object, required `Idempotency-Key`; returns 202 with `scan_id` and status. Identity is derived from the bearer principal, not body tenant/subject fields. |
| `GET /api/v1/scans/{scan_id}` | Returns the owner-scoped queued/processing/completed/failed status. |
| `GET /api/v1/scans/{scan_id}/result` | Returns 404 `result_unavailable` until a result exists, then schema `2.0`. |
| `DELETE /api/v1/media?media_ref=...` | Owner-scoped media deletion; returns 204 on success. |

The V2 backend's `DevelopmentAuthenticator` maps a development bearer token to a principal in server configuration. This run supplied only a generated, disposable identity mapping `synthetic-user` to `synthetic-tenant`. The token was generated at runtime using a cryptographically secure random generator, passed through the harness child process environment, never printed, written to source, committed, persisted, or supplied as a Dart define. No Directus credential was reused.

V2's worker source uses deterministic media extractors and does not invoke a validated fatigue/vigilance model. Its honest result is `insufficient_evidence`, with null targets and `model_version: null`; no scientific prediction was claimed.

## 4. Flutter Capture Compatibility

- Scan capture remains in `scan_flow_impl_normalized.dart`. Camera recording uses `CameraController.startVideoRecording()` with the configured `ResolutionPreset.veryHigh`; both installed platform camera plugins write MP4 containers. Android CameraX creates `.mp4` output; the iOS plugin creates an `AVAssetWriter` with `.mp4`. Flutter does not explicitly pin video codec/bitrate in this capture call; an actual device recording was not captured in this phase, so the emitted codec and exact resolution remain device-runtime unknowns.
- In explicitly requested V2 mode, audio recording switches to `AudioEncoder.wav`, mono, 44.1 kHz. The installed Android `record_android` WAV writer emits a RIFF/WAVE PCM header with 16-bit samples; installed iOS `record_ios` configures Linear PCM, 16-bit, little endian, and WAV output. The scan rejects a device that reports the WAV encoder unsupported. The V2 client independently checks the actual bytes for RIFF/WAVE PCM16 before upload, so AAC data cannot be labelled WAV.
- The V2 client accepts MP4 only when it has the ISO-BMFF `ftyp` marker and is within 20 MiB; WAV must have a valid bounded RIFF layout, PCM encoding 1, and 16-bit samples, within 8 MiB. The backend remains responsible for deeper media decode/quality checks. A matching header alone is not proof that arbitrary media is decodable.
- The scan's existing focus/reaction interaction does not supply verifiable per-trial stimulus/response timestamps. V2 submission sends `reaction_task: null`; the task is not represented as validated PVT.
- The V2 path uploads only actual captured video and audio. It does not synthesize an image or extract a still frame. Legacy thumbnail/finalization work is bypassed when V2 is selected.

## 5. Identity, Feature Flag, and Network Safety

- `ENABLE_LOCAL_WELLAR_V2` defaults to false. V2 configuration is separate from Directus credentials, requires the declared synthetic development tenant/subject, a separate bearer token, and a loopback/local-emulator URL. The client does not include `tenant_id` or `subject_id` in scan payloads.
- `WellarV2LocalConfig.enabled` rejects release builds (`kReleaseMode`) and rejects non-local hosts. No release configuration or production environment was changed. A development token embedded in a Dart define would be extractable from that debug build; it is a disposable local test mechanism only, not an authentication design for distribution.
- Android's main manifest keeps `usesCleartextTraffic="false"`. A debug-only network-security config allows cleartext to `localhost`, `127.0.0.1`, and emulator host alias `10.0.2.2`; it retains a deny-cleartext base config. The debug manifest references that config. These constraints were source-inspected; no release APK was built.
- The installed AVD `Medium_Phone_API_36.1` booted as `emulator-5554`. While the disposable API was bound to host loopback, `adb shell toybox nc -z 10.0.2.2 <port>` succeeded. This proves emulator TCP routing to that temporary host port, not an app HTTP request or TLS/security-policy runtime behavior.

## 6. Real HTTP Workflow and Results

The repeatable command is:

```powershell
cd D:\flutter_app\wellar-flutter-app
rtk proxy cmd.exe /d /c "D:\flutter\last\wellar-ai-v2\.venv\Scripts\python.exe tool\phase1b_local_http.py"
```

The harness generates a two-second synthetic black H.264 MP4 and one-second mono PCM16 WAV, creates a fresh random synthetic principal, and launches API and worker as separate local processes. Both use SQLite and media storage under a unique `%TEMP%\wellar-v2-phase1b-*` directory. It does not configure or connect to PostgreSQL or port 5432. The service binds only to `127.0.0.1`.

Observed on the final successful run:

1. Emulator TCP reachability to host loopback via `10.0.2.2` succeeded.
2. Flutter test's real Dio client posted MP4 and WAV bytes; each upload returned HTTP 201.
3. Scan submission returned HTTP 202. Replaying the same payload with the same `Idempotency-Key` returned the same scan ID and HTTP 202; it did not create a second scan.
4. A result fetch while the job was pending returned the V2 `result_unavailable` response; the client surfaced it as retryable.
5. The separate worker completed processing. Status polling reached `completed`; result retrieval returned HTTP 200, schema `2.0`, `insufficient_evidence`, `model_version: null`, and only null target values.
6. Both uploaded media references were deleted with HTTP 204 after terminal completion. The harness verified there were no remaining media files, stopped both services, and removed the temporary SQLite/media directory.

Latest observed timings for this one local run: combined two-media upload 130 ms, initial submission 39 ms, status-poll interval from start through completion 6,759 ms, result retrieval 11 ms. These timings are for tiny generated media on one host; they do not estimate real-device latency, capacity, production performance, or backend throughput. Worker processing included extraction work and must not be read as model-inference time.

## 7. Directus and Legacy Isolation

- The existing default scan path and Directus workflows remain unchanged when the local V2 flag is false.
- Source inspection shows the selected V2 branch in `_finishScan` routes to `WellarV2ProcessingScreen` and returns before legacy scan creation/finalization. V2 client source contains no Directus client, legacy `/process` path, or legacy result model. The branch has no fallback to the old processor.
- The live integration test constructs only `WellarV2Client`; it observed only V2 media, scan, status, result, and cleanup operations. It did not start the Flutter app or observe an interactive scan branch. Thus no live Directus non-mutation claim is made. No Directus scan result/readiness category is written by the isolated client workflow.
- Durable reconciliation of standalone V2 scans into company history/reporting remains an integration gap. This phase makes no dual write and does not mutate Directus collections.

## 8. Test Results

| Verification | Result |
|---|---:|
| Focused `wellar_v2_client_test.dart` after Phase 1B changes | **13 passed, 0 failed** |
| Opt-in real HTTP test against disposable API + separate worker | **1 passed, 0 failed** |
| Android emulator `10.0.2.2` route probe during that run | **Passed** |
| V2 backend full test suite, installed venv, no pytest cache/bytecode | **68 passed, 1 skipped, 0 failed** |
| Full Flutter test suite, serial, `--timeout 20s` | **Incomplete; observed 4 passed, 3 failed, then stalled** |

Full Flutter suite failures observed:

- `test/auth_journey_screens_test.dart`, `auth intent join path opens workspace access screen`, assertion at line 84: expected one `WorkspaceAccessScreen`, found zero. The production handler does construct that screen; the test's actual navigation result is unresolved, and it was not changed.
- `test/auth_journey_screens_test.dart`, `registration enables submit on the final password character`, assertion at line 126: `tester.widget<ElevatedButton>(submitButton)` throws `Bad state: No element`. The registration UI renders the app's custom `_ActionButton.primary`, not an `ElevatedButton`, so the widget finder does not match the rendered control. This is a deterministic test/UI abstraction mismatch, not a V2 regression; the test was preserved.
- `test/organization_switch_flow_test.dart`, `successful organization switch refreshes token and replaces context`: fails because the server did not confirm the selected workspace. Logs show its membership probe receives status 0. Flutter's test runner warns that `HttpClient` requests are intercepted/blocked and return 400; the test's Dio interceptor does not mock the separate `HttpClient` membership probe. Authentication and workspace rules were not weakened.
- `test/organization_switch_flow_test.dart`, `stale switch result cannot overwrite a newer selected organization`: stalls in the same file. The test's first context interceptor waits on `firstContextGate.future`; during observed runs it never reached the subsequent `firstContextGate.complete()`. It exceeded the external run window despite the test package timeout and required external interruption. No test was removed or disabled.

The auth/workspace files were already modified before this phase, and no clean baseline run completed. These exact current failures are proven; whether any predate Phase 1 cannot be established from available Git history.

V2 backend skip: `tests/test_postgres_integration.py` skips because `WELLAR_TEST_POSTGRES_DSN` is not configured. PostgreSQL was not contacted.

`git diff --check` also reported a trailing blank line at `lib/screens/pricing_screen.dart:536`, an unrelated pre-existing dirty file that was left untouched. It emitted only line-ending warnings for other existing modified files.

## 9. Error, Retry, and Cleanup Behavior

- Only submission is automatically retried, once, for retryable transport/timeout, HTTP 408/429/5xx errors, using the identical payload and `Idempotency-Key`. The focused tests verify same-key replay for 503 and connection timeout. 401/403 is not retried; messages/body details are sanitized.
- Cancellation is passed through Dio `CancelToken`; a pre-cancelled request never reaches the adapter, and the focused test confirms no retry. A user cancellation after V2 accepts a job cannot cancel server work because V2 has no scan-cancel endpoint; uploaded media remains for worker processing/retention.
- Media is deleted on known pre-acceptance failure and after a terminal result/failure. Ambiguous submission outcomes and accepted-but-still-processing jobs retain media to avoid deleting worker input. Delete failures are swallowed in the UI; the backend retention policy is the fallback.
- Pending-result handling was tested against real V2. A transport timeout was simulated through a fake adapter; an actual socket drop or black-hole backend timeout was not run. 401, 503 retry, malformed response sanitization, unsupported local media rejection, and same-key client retry were exercised with client test doubles, not as live server fault injection.
- The V2 server's actual rejection path is covered by its existing backend suite, but this run did not send deliberately corrupt media to the disposable server. No invasive or production failure injection was performed.

## 10. Which Journey Was Verified

**Verified:** the production `WellarV2Client` implementation from a Flutter test process talking over real HTTP to a disposable V2 API and separate worker, with synthetic media and identity. Upload, submit, idempotency replay, pending result, terminal status, result schema, cleanup, and Android host routing all passed.

**Not verified:** opening the production Flutter app, authenticating through Directus, navigating through real capture UI, recording media on Android, running V2 debug mode from an installed app, observing result UI rendering, iOS capture/runtime, production identity, tenant provisioning, Directus history reconciliation, failure behavior under real radio/network interruption, or scale/latency under load. The app was not launched against Directus, and no credentials were fabricated.

## 11. Remaining Blockers and Exact Next Safe Step

1. Build a non-production identity bridge that issues a short-lived V2 JWT with verified issuer, audience, signature, expiry, and tenant/subject authorization. Do not reuse a Directus bearer token without those claims and verification.
2. Define a durable reconciliation/reporting design between V2 scan IDs and Directus business records before enabling company history/reporting. Phase 1B intentionally makes no cross-system write.
3. Run a debug app journey on the already-installed emulator only after a local non-production Directus/test identity flow is available. Bind disposable V2 to host loopback; pass `WELLAR_V2_BASE_URL=http://10.0.2.2:<port>` and a short-lived synthetic V2-only token via a local debug run configuration, never a distributed build. Keep `ENABLE_LOCAL_WELLAR_V2=true` explicit; verify capture bytes and final V2 UI, then stop services and remove temporary state.
4. If an app-level Directus mock or isolated test login becomes available, add an integration test that exercises the actual `_finishScan` branch and asserts no `/process` call and no Directus scan mutation.
5. Repair the two auth test finders/navigation expectation and the workspace test's `HttpClient` dependency injection and unresolved completer sequencing. Then rerun the entire Flutter suite to completion; preserve authentication/workspace business behavior.
6. Before any capacity claims, run synthetic load against an isolated V2 environment with explicit request concurrency, upload-size distribution, queue depth, worker count, and resource metrics. The one local timing sample is not a capacity result.

## 12. Security and Limitations

- The V2 integration remains opt-in and local only. V2 configuration and auth remain separate from Directus. No production API, real employee recording, or real identity was used.
- The result UI is V2-specific and displays `Insufficient evidence`; no readiness/risk score is generated. Scan IDs, opaque media refs, and API result fields are not written into legacy score categories.
- The synthetic harness uses test-mode development auth and temporary SQLite/local media, which are single-host test facilities. It does not validate OIDC/JWT integration, production storage/queue topology, TLS, or tenant policy configuration.
- Android debug cleartext policy was source-inspected; iOS ATS/runtime network behavior was not tested. No release or profile artifact was built.
- Existing app startup, authentication, permissions, lifecycle, local recordings retention, and all production Directus flows were not exercised in this phase. Local capture files are not automatically proven erased by the V2 client; this client uploads bytes and the existing scan flow owns temporary-file lifecycle.
- The V2 backend contains no validated scientific fatigue/vigilance model. `insufficient_evidence` is the only honest prediction-related result observed.
