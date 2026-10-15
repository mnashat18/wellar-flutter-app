# Wellar Flutter V2 Phase 1C Results

## Outcome

The two originally identified auth journey tests and the two focused organization-switch tests now pass. The installed Android emulator completed a real local HTTP journey through the production V2 processing and result widgets using generated synthetic MP4/WAV media and an ephemeral synthetic V2 identity. The result UI showed `Insufficient evidence`, unavailable/null targets, and the non-predictive disclaimer. V2 media objects were deleted after completion.

The full Flutter suite completed but is not green: **57 passed, 12 failed, 1 skipped** (70 visible tests). The production Directus-authenticated capture journey and interactive cancellation were not verified. At final cleanup, the AVD became unavailable to adb; the successful run verified server media cleanup, while the later test-only local-file deletion path was added but not rerun after the AVD went offline.

## 1. Repositories and State Preservation

- Flutter root: `D:\flutter_app\wellar-flutter-app`, branch `main`.
- V2 root: `D:\flutter\last\wellar-ai-v2`; its existing `.venv`, API source, tests, and worker were used read-only.
- Flutter already contained extensive modified and untracked files before Phase 1C. Those user changes were preserved. No reset, stash, checkout, cleanup of user code, commit, or branch operation occurred.
- No V2 or legacy AI Server files were changed. No Directus production API or PostgreSQL port 5432 was contacted.
- V2 verification used disposable SQLite and local media under a temporary directory. Successful harness exit removed this state and stopped the API and separate worker.

## 2. Exact Phase 1C Changes

- `test/auth_journey_screens_test.dart`: corrected the anonymous join expectation to the actual sign-in redirect and changed the registration submit finder from `ElevatedButton` to the rendered custom `InkWell` action. Bounded both tests.
- `test/organization_switch_flow_test.dart`: supplied the selected membership expected by the real workspace-switch contract; added a mock for post-switch active-membership verification; asserted the actual request sequence; added an injected fake refresh client for the otherwise separate refresh `Dio`; and replaced timer sleeps around `firstContextGate` with a completer handshake and bounded waits.
- `lib/services/directus_client.dart`: added a `@visibleForTesting` refresh-client factory seam. It is set only inside an `assert`, so release builds cannot enable the test override. Production refresh behavior remains unchanged.
- `test/v2_ui_smoke_main.dart`: added a test-only entrypoint that automatically opens the actual V2 processing widget below a `Navigator`, creates synthetic MP4/WAV files in app temporary storage, and deletes those local inputs when the processing/result route returns. It does not boot the production app, Directus, camera, or authentication flow.
- `tool/phase1c_emulator_ui.py`: added a local-only runner that creates a short-lived synthetic principal, starts loopback V2 API and worker against temporary SQLite/media, runs the debug entrypoint on the existing AVD, records sanitized method/path/status access-log evidence, checks result UI and media cleanup, then stops services and removes temporary state.
- `FLUTTER_V2_PHASE1C_RESULTS.md`: this report.

The synthetic MP4 is embedded only in the test entrypoint. It is not configured as a global Flutter asset and does not add test media to ordinary app/release bundles. No dependency was intentionally added.

## 3. Previously Identified Test Blockers

### Auth journey

- Workspace access expectation: source behavior constructs `WorkspaceAccessScreen`, whose unauthenticated guard replaces it with `LoginScreen`. The previous assertion expected the transient guarded screen as the final route. The test now asserts the sign-in result, preserving the auth guard.
- Registration submit finder: the UI uses a custom action built around `InkWell`, not `ElevatedButton`. The test now asserts that this action is disabled before the final password character and enabled afterward.
- Isolated verification: `auth_journey_screens_test.dart` **5 passed, 0 failed**.

### Organization switch

- The switch test omitted `expectedMembership`, leaving the canonical business-profile target unspecified and causing the production verification to reject the selection. Its fixture now supplies the selected membership and mocks the actual membership verification request. The separate refresh client is supplied a deterministic fake, so the test binding no longer attempts an unmocked HTTP request.
- The stale-switch test waited on `firstContextGate` while using timer delays to guess when the first context request had begun. It now waits for an explicit `firstContextStarted` signal, releases the gate deterministically, and bounds both operations.
- Isolated verification: `successful organization switch refreshes token and replaces context` **1 passed**; `stale switch result cannot overwrite a newer selected organization` **1 passed**.
- No authorization checks, auth semantics, or workspace business rules were weakened.

## 4. Full Flutter Regression Outcome

Command (package resolution explicitly disabled):

```powershell
C:\flutter\bin\flutter.bat test --no-pub --reporter compact --timeout 30s
```

Outcome: **57 passed, 12 failed, 1 skipped**. The run reached the test runner's `done` event; no test stalled beyond the 30-second per-test timeout. The one skip is the opt-in real-HTTP test, which requires the disposable integration harness.

Remaining failing test names and confirmed evidence:

1. `identical sync requests coalesce within one authenticated session` — server workspace verification rejects the test fixture; the fixture still needs the selected membership/context supplied.
2. `session restore uses canonical active membership instead of first membership row` — expected role shell, received workspace selection under current mocked context/policy.
3. `google post-auth uses canonical active membership without fallback or switch` — an expected non-empty result is empty under the current fixture.
4. `google post-auth with missing canonical workspace throws noMembership and clears local state` — the current call returns normally instead of matching the expected `AuthFlowException`; requires a focused auth-flow fixture/source review.
5. `refresh access shows explicit organization selector and only switches after tap` — still fails in the broad widget workflow; no auth policy was changed to accommodate it.
6. `push diagnostics screen does not expose raw token actions` — test failure remains; no production diagnostic behavior was altered.
7. `protected endpoints are the only registered push paths` — explicit stale expectation: test expected `/wellar/push-subscriptions/sync`, implementation registers `/wellar-push-subscriptions/sync`.
8. `sparse 201 waits for refreshed canonical owner context` — deterministic finder error: the test indexes a third `TextField`, but only two are present.
9. `sparse 201 stops when token refresh fails` — same third-field `RangeError` before the behavior under test.
10. `switch organization action appears before logout and handles single organization state` — remaining workspace UI test failure.
11. `didUpdateWidget rebuilds shell when initial context identity changes` — remaining role-shell test failure.
12. `App shows splash screen` — test expected `PublicHomeScreen`, while app startup logs show the actual unauthenticated route resolves to `public_entry`.

The 12 remaining failures are outside the two fixed targeted test failures. The relevant test and application files were already dirty at the start of Phase 1C, so a clean pre-Phase-1C baseline is unavailable; it is not possible to prove whether each remaining failure predates the earlier phase.

## 5. V2 Client Regression

Command:

```powershell
C:\flutter\bin\flutter.bat test --no-pub test\wellar_v2_client_test.dart --reporter expanded --timeout 20s
```

Outcome: **13 passed, 0 failed**. This includes:

- V2 feature flag disabled by default.
- Raw MP4 and PCM WAV bytes with matching content types.
- Unsupported/mislabeled media rejected before network access.
- Missing V2 credential fails before sending a request.
- Required V2 scan schema and idempotency key.
- Safe same-key retry behavior.
- Cancellation before adapter access and no retry after cancellation.
- Auth rejection does not retry; errors are sanitized.
- Nullable insufficient-evidence result parsing and opaque media deletion.

The Phase 1B backend suite result (**68 passed, 1 skipped**) is historical evidence and was not rerun in this phase. Phase 1C did run the V2 API and worker locally for the emulator path.

## 6. Android Emulator and Actual UI Journey

- Existing AVD: `Medium_Phone_API_36.1`, adb device `emulator-5554`, Android SDK already installed. Host-to-emulator route via `10.0.2.2` succeeded.
- Debug-only base URL was `http://10.0.2.2:<temporary-port>`. A short-lived synthetic token was generated in memory by the harness and passed only to this local debug invocation. It was not printed, written to source/report, committed, or intentionally persisted. It is not an authentication design for distribution.
- The verified journey was: test-only Flutter entrypoint → actual `WellarV2ProcessingScreen` → synthetic media upload → V2 scan submission → worker processing → actual `WellarV2ResultScreen` → user-visible insufficient-evidence result.
- Actual result UI showed `Insufficient evidence`, unavailable/null target values, and the statement that no validated fatigue/vigilance prediction or readiness/risk score is available.
- The complete production scan/capture flow was **not** verified. This entrypoint intentionally bypasses app startup, Directus sign-in, permissions, and camera/microphone capture. No claim of a full employee scan is made.

### Sanitized real HTTP evidence

The disposable API access log recorded only method, route without query values, and status. No Authorization header, token, body, media reference, or media bytes were emitted in the report.

| Operation | Observed result |
|---|---|
| `POST /api/v1/media/video` | 201 |
| `POST /api/v1/media/audio` | 201 |
| `POST /api/v1/scans` | 202 |
| `GET /api/v1/scans/{scan_id}` | 200 on each status poll |
| `GET /api/v1/scans/{scan_id}/result` | 200 |
| `DELETE /api/v1/media` | 204 for both uploaded media references |

The result screen and successful deletions were observed from the same emulator run. The temporary V2 media directory contained **0 files** after completion. The access log contained V2 API routes only; it contained no `/process` request. The test entrypoint imports the V2 screen directly and does not instantiate Directus or a legacy processor.

Observed harness wall time was approximately **78 seconds** for one emulator run. This includes Flutter launch/build, user-visible flow, backend processing, polling, and result display; it is not a server latency, model latency, or throughput measurement.

## 7. Identity, Feature Flag, and Network Safety

- The default local V2 flag remains false; the focused client test passed this assertion.
- `WellarV2LocalConfig` rejects release mode and accepts only the configured local/emulator hosts plus the declared synthetic tenant and subject. The test runner supplied a separate synthetic V2 token. Directus credentials were not reused.
- Android main manifest still has `usesCleartextTraffic="false"`. Cleartext allowance for `localhost`, `127.0.0.1`, and `10.0.2.2` exists only in the debug network-security config. No release network-security setting was weakened and no release artifact was built.
- The test-only entrypoint contains no Directus credentials or production auth bypass. Production routes and Directus workflows were not changed by this phase.

## 8. Cancellation and Media Privacy

- Client cancellation behavior is covered by the passing client test: a pre-cancelled request never reaches the adapter and is not retried.
- The processing widget's user cancel action and accepted-scan retention policy were source-reviewed. V2 has no scan-cancel endpoint: after acceptance, a canceled UI cannot stop worker processing, so server media must remain available to the worker and is governed by V2 retention unless cleanup is explicitly performed after terminal processing.
- Interactive Android cancellation after acceptance was **not** exercised. The UI run completed normally and verified server-side media deletion.
- The test-only entrypoint now deletes generated local synthetic inputs when its pushed processing/result route returns. That final local-file cleanup addition was not dynamically verified because the AVD went offline before the follow-up run. Synthetic local cache files from a prior UI run may remain on the emulator app's temporary directory; there was no employee or biometric data in them. Do not clear all app data to resolve this. Once the AVD is available, verify/delete only `cache/v2_synthetic.mp4` and `cache/v2_synthetic.wav` using `run-as com.example.waller_app`.

## 9. Timing and Capacity Limits

- The approximately 78-second observed harness wall time includes cold Flutter startup/build and device UI automation. It must not be interpreted as V2 scan processing latency.
- Per-stage upload/submission/worker/result timing was not instrumented from this UI run. The API status sequence and final schema were observed; backend capacity, throughput, real-device latency, camera warmup, and radio resilience remain unmeasured.
- One emulator and tiny synthetic media are not evidence of capacity or production performance.

## 10. V2/Directus and Legacy Boundaries

- The test-only run exercised the standalone V2 media, scans, status, result, and media-delete endpoints only. It made no Directus request or mutation.
- The ordinary app remains on Directus for identity and business workflows when V2 mode is off. V2 scans still have no durable Directus history/reporting reconciliation; no dual-write was added.
- The V2 result remains separate from legacy `ScanResult` readiness/risk categories. No false Directus scan record, readiness score, or scientific result was created.
- No legacy AI Server code, endpoint, package, or service was contacted, changed, imported, started, or deployed.

## 11. AVD Final State and Remaining Verification

The successful final HTTP/UI run completed and its temporary API/worker/database/media state was removed. A subsequent attempt to verify the newly added test-entrypoint local-file cleanup failed before startup because `adb` no longer listed the AVD. The existing AVD process was unresponsive to adb; it was not wiped and no data partition was cleared. No later emulator journey is claimed.

Not verified:

- Directus-authenticated production app navigation or an employee account.
- Android camera/microphone permission grant/deny, actual capture, format/device compatibility, or capture cancellation.
- Interactive cancellation after server acceptance.
- The test entrypoint's final app-cache file deletion after pressing `Done`.
- iOS runtime, production OIDC/JWT identity, Directus reconciliation, release artifact behavior, real network interruption, or load capacity.

## 12. Package Resolution Restriction Incident

One early focused Flutter invocation was run without `--no-pub`. Flutter printed `Resolving dependencies...` and `Downloading packages...`. No package was intentionally added in Phase 1C, and all subsequent Flutter test commands used `--no-pub`; however, I cannot verify whether that automatic invocation fetched package archives or changed pre-existing cache/lock state. This was an execution mistake against the no-download restriction and is disclosed explicitly. No further package resolution/download command was run.

## 13. Exact Next Owner Action

1. Restore the existing AVD to an adb-online state without wiping its data.
2. Inspect only the test-generated cache files (`cache/v2_synthetic.mp4`, `cache/v2_synthetic.wav`), remove them with `run-as com.example.waller_app` if still present, and rerun the harness once to verify the final `Done`/local cleanup path.
3. Fix the remaining 12 test failures as test-fixture/navigation issues where source evidence supports that diagnosis; do not relax workspace/auth semantics. Rerun with `flutter test --no-pub --timeout 30s`.
4. Before real capture integration, provide a disposable local identity/session path and decide how standalone V2 scan IDs/results will be reconciled into Directus history. Then exercise Android camera/microphone capture and post-acceptance cancellation against disposable V2 only.

## Reproduction Command

With the installed emulator adb-online and the local V2 `.venv` intact:

```powershell
cd D:\flutter_app\wellar-flutter-app
rtk proxy powershell -NoProfile -Command "& 'D:\flutter\last\wellar-ai-v2\.venv\Scripts\python.exe' tool\phase1c_emulator_ui.py"
```

The harness uses only a loopback API, synthetic identity/media, temporary SQLite/local-media storage, the installed debug app/toolchain, and `10.0.2.2`. It never calls production Directus or the legacy AI Server.
