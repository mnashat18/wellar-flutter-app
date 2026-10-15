# Flutter Safety Review

**Review date:** 2026-10-15  
**Scope:** Read-only review of the canonical Flutter working tree. No product, test, dependency, or build files were edited. The only file created for this review is this report.

## Executive conclusion

**NEEDS REVIEW — do not treat this checkout as release-cleared.** There are 100 tracked modified paths and 36 untracked paths, an unavailable clean baseline for many of them, and a historically failing full Flutter suite. The current full-suite attempt and a targeted reproduction both stalled before emitting test events and were stopped; they do not establish a fresh pass/fail count. Phase 1C's recorded complete run was 57 passed, 12 failed, 1 skipped. No confirmed V2-caused production regression was found in the source reviewed, but broad pre-existing application edits, no release build/runtime test, and incomplete recording cleanup evidence prevent a “safe” finding.

No production API, Directus, legacy AI Server, or PostgreSQL service was contacted. No Git state-changing operation was performed.

## 1. Current Git state and baseline evidence

- Git root is `D:\flutter_app\wellar-flutter-app`; branch is `main`, tracking `origin/main`, with no ahead/behind marker in `git status --short --branch`.
- Current status contains **100 modified tracked paths and 36 untracked paths** (139 porcelain records including status entries; one untracked directory entry can represent multiple files). `git diff --stat` reports 100 changed tracked files, 8,633 insertions and 4,739 deletions. Generated plugin registrants, `pubspec.yaml`/lockfile, platform manifests, broad business/auth/workspace/scan code, tests and numerous audit documents are included.
- This repository has no clean pre-Phase-1 baseline for the broad dirty set. Prior Phase reports explicitly record that Directus/auth/workspace/scan code, platform settings, dependency metadata and tests were already modified before the V2 work. Thus Git diff against `HEAD` does not identify ownership or prove these are Phase 1 regressions.
- The Phase 1, 1B and 1C reports are untracked local evidence, not committed baselines. V2's report history says the V2 project itself had no Git metadata available. The baseline Flutter suite before Phase 1 was incomplete; no clean baseline comparison exists.
- One earlier Phase 1C Flutter invocation omitted `--no-pub` and Flutter printed dependency-resolution/download messages. The Phase 1C report discloses this restriction incident. This review did not run package resolution or install anything; whether that earlier invocation changed global package cache state is unverified.

### Working-tree inventory by likely origin

| Origin grouping | Current paths / evidence | Confidence |
|---|---|---|
| V2 Phase 1 implementation | `lib/services/wellar_v2_client.dart`, `lib/models/wellar_v2_result.dart`, `lib/screens/wellar_v2_processing_screen.dart`, `lib/screens/wellar_v2_result_screen.dart`, V2 additions to `lib/config/app_config.dart` and `lib/screens/scan_flow_impl_normalized.dart`, Android debug network config, `test/wellar_v2_client_test.dart`; source presence and `FLUTTER_V2_PHASE1_RESULTS.md` agree. | High for V2-specific new files; medium for hunks in shared dirty files. |
| Phase 1B/1C integration and test harness | `test/v2_ui_smoke_main.dart`, `tool/phase1b_local_http.py`, `tool/phase1c_emulator_ui.py`, `test/wellar_v2_live_http_test.dart`; reports identify these as disposable local harness/test entrypoint. Phase 1C also changed `test/auth_journey_screens_test.dart`, `test/organization_switch_flow_test.dart`, and added the `DirectusClient` test seam. | High for the harness files; medium for shared test files because the whole files were already dirty. |
| Other feature/product work and audits | 100 tracked files include extensive role screens, Directus services, workspace and scan paths, translations, generated plugin registrants, lockfile and platform files. Untracked files include multiple audit reports, workspace selection, workforce, location, navigation, validation and UI utilities/tests. Prior reports state many existed before V2 work. | Low for precise authorship; high that they are unrelated or mixed and not attributable solely to V2. |

The exhaustive current path list is captured by the commands `git status --short`, `git diff --stat`, and `git ls-files --others --exclude-standard`; it is intentionally summarized here to avoid implying that every dirty path was introduced by V2.

## 2. Phase 1 / 1B / 1C change attribution

- **Phase 1:** dedicated client/result model and two V2 screens; compile-time local V2 configuration; separate branch in `scan_flow_impl_normalized.dart`; debug-only Android local cleartext configuration; focused client tests. Report: `FLUTTER_V2_PHASE1_RESULTS.md`.
- **Phase 1B:** report and disposable local HTTP/emulator harness work, with subsequent stabilization changes described in `FLUTTER_V2_PHASE1B_RESULTS.md`. The reports document the already-existing real HTTP client test evidence and a previous full suite that did not finish cleanly.
- **Phase 1C:** test-only UI entrypoint and synthetic local media; local API/worker harness; auth/workspace test fixture changes and bounded waits; `DirectusClient` test-only refresh-client factory seam; Phase 1C report. Report: `FLUTTER_V2_PHASE1C_RESULTS.md`.
- These reports identify the intended phase changes but do not provide a machine-recorded before/after patch series. As many shared files were dirty before Phase 1, any exact attribution of their entire current diff is uncertain.

## 3. Directus, legacy scan and original application preservation

Source review supports isolation **when the local V2 flag is false**:

- `lib/config/app_config.dart:59-76` declares `ENABLE_LOCAL_WELLAR_V2` with `defaultValue: false`; it separately declares V2 base URL and credential/identity compile-time inputs. No token is hardcoded in this source.
- `lib/services/wellar_v2_client.dart:29-50` requires non-release mode, a distinct nonempty V2 token, the exact synthetic tenant/subject markers and an allowlisted local host. The V2 client comment and imports show it does not use Directus auth or the legacy processor.
- `lib/screens/scan_flow_impl_normalized.dart:1840-1844` skips legacy media prefinalization when V2 is requested. At `:1931-1957`, it validates V2 config, pushes the V2 processing route and returns before the normal `createWellnessScan` path beginning at `:1962` and workflow dispatch at `:1992`. Therefore this branch does not make the normal legacy `/process` call or create a Directus scan result. This is static source evidence; the normal production-authenticated journey was not re-run in this review.
- The V2-specific result model/screen is separate from legacy readiness categories. Phase 1C's emulator run recorded V2-only routes and no `/process`, and the V2 result was `insufficient_evidence` with null targets. That emulator evidence is historical and was not repeated in this review.
- Existing Directus auth, workspace switching and business features have extensive dirty changes. The V2 branch is isolated by source, but the complete dirty changes to shared Directus/auth/workspace code cannot be cleared as regressions or certified as preserved without a clean baseline and successful regression suite.
- `lib/services/directus_client.dart` contains a `@visibleForTesting` refresh client override around `:10-11` and setter around `:394-400`, assigning only inside an `assert`. This is an intentional test seam, not a V2 auth change. No release compilation was performed to validate tree-shaking/assert behavior.

## 4. Release/debug isolation

**Positive source evidence:**

- V2 flag default is false (`lib/config/app_config.dart:59-62`).
- V2 local config checks `!kReleaseMode` and local-host allowlisting (`lib/services/wellar_v2_client.dart:29-50`). Even if a release build passes the flag, client config rejects local mode. There is no silent fallback to legacy processing when V2 was explicitly requested but invalid.
- Android main manifest has `android:usesCleartextTraffic="false"` (`android/app/src/main/AndroidManifest.xml:9`). The V2 cleartext network config is added from `android/app/src/debug/AndroidManifest.xml`; its debug XML denies cleartext by default and permits only `localhost`, `127.0.0.1`, and `10.0.2.2`.
- V2 smoke entrypoint and harness are under `test/` and `tool/`, not the production `lib/main.dart` entrypoint. Synthetic media is embedded in the test entrypoint, not registered as a normal application asset (Phase 1C report and current `pubspec.yaml` evidence).

**Limits / review items:**

- A `--dart-define` development token becomes a compile-time value in the specific debug artifact. The previous harness report says its token was synthetic, ephemeral and not printed or persisted; that does not make dart-define suitable for distributed builds. Do not reuse or distribute that debug artifact. No release/profile artifact was built here.
- `!kReleaseMode` permits profile mode as well as debug mode. It is still constrained to local hosts and a synthetic principal, but a future tightening to `kDebugMode` is a small defense-in-depth option if local V2 is meant only for debug.
- The source does not prove a release build cannot be manually supplied a development token at compile time; instead, the runtime guard prevents the V2 request path in release. Build/release CI configuration was not audited beyond this checkout.
- The main Android setting remains hardened in source, but merged release manifest output was not built/inspected. iOS release/debug ATS behavior was not built or runtime tested.

## 5. Full-suite failures and classifications

### Current reproduction attempt

This review attempted the full suite with:

```powershell
rtk proxy powershell -NoProfile -Command "C:\flutter\bin\flutter.bat test --no-pub --reporter expanded --timeout 20s"
```

The Flutter process emitted no test events and did not return during the bounded observation window. It was interrupted. A targeted single-test run for the push endpoint mismatch using `--no-pub --timeout 15s --plain-name ...` behaved the same. **Current rerun: incomplete; no current pass/fail/skip count.** Per-test timeout does not bound tool startup/compilation, so these attempts cannot be treated as reproductions of individual assertions.

### Last complete available run

`FLUTTER_V2_PHASE1C_RESULTS.md` records a completed post-Phase-1C run: **57 passed, 12 failed, 1 skipped** with a 30-second per-test timeout. It reports the names and failure clues below. This is historical evidence, not a fresh result for this review. No clean pre-Phase-1 baseline exists, so none of these failures can be proven to predate Phase 1.

| # | Test | Classification supported by available evidence | Safety status |
|---:|---|---|---|
| 1 | `identical sync requests coalesce within one authenticated session` | **Incomplete mock/fixture** — Phase 1C report says workspace verification rejected the fixture because selected expected membership/context was omitted. No production authorization rule should be weakened. | Historical failure; current assertion not reproduced. |
| 2 | `session restore uses canonical active membership instead of first membership row` | **Unknown** — current fixture/policy produced workspace selection instead of expected role shell. Available evidence does not decide whether mock context is incomplete or app behavior is wrong. | Needs focused source and fixture review. |
| 3 | `google post-auth uses canonical active membership without fallback or switch` | **Unknown** — expected nonempty output was empty under fixture; no assertion trace here distinguishes a mock mismatch from a production defect. | Needs focused review. |
| 4 | `google post-auth with missing canonical workspace throws noMembership and clears local state` | **Unknown** — the recorded behavior returned normally instead of expected `AuthFlowException`; cannot classify without current source-level execution evidence. | Security-sensitive auth/workspace semantics; do not change policy by guess. |
| 5 | `refresh access shows explicit organization selector and only switches after tap` | **Unknown** — historical report says widget workflow failed, without sufficient assertion details to classify. | Needs focused reproduction. |
| 6 | `push diagnostics screen does not expose raw token actions` | **Unknown** — historical report says test failed, without assertion details. | Sensitive diagnostics behavior; inspect exact failure before any change. |
| 7 | `protected endpoints are the only registered push paths` | **Outdated test expectation, source-confirmed mismatch** — test expects `/wellar/push-subscriptions/sync`; current `protected_push_subscription_api.dart` registers `/wellar-push-subscriptions/sync`. This establishes disagreement, not which endpoint the external server expects. | Do not change runtime path without API contract evidence. |
| 8 | `sparse 201 waits for refreshed canonical owner context` | **Outdated test finder** — recorded `RangeError` indexes a third `TextField`, while current test/UI has only two fields in this flow. The behavior under test is not reached. | Test repair is appropriate after confirming intended fields. |
| 9 | `sparse 201 stops when token refresh fails` | **Outdated test finder** — same recorded index error before refresh-failure assertion. | Test repair is appropriate; preserve auth semantics. |
| 10 | `switch organization action appears before logout and handles single organization state` | **Unknown** — historical failure lacks captured assertion details. | Needs focused reproduction. |
| 11 | `didUpdateWidget rebuilds shell when initial context identity changes` | **Unknown** — historical failure lacks captured assertion details. | Needs focused reproduction. |
| 12 | `App shows splash screen` | **Outdated test expectation, source/report supported** — test expects `PublicHomeScreen`; Phase 1C report records startup resolves unauthenticated flow to `public_entry`. It is not evidence of a V2 failure. | Verify intended app startup contract before updating test. |

**Confirmed production defects among these 12: none established.** This is not equivalent to proving there are none. The current runner's startup stall and broad dirty baseline prevent a stronger conclusion.

## 6. Sensitive recording and media cleanup

- The V2 processing screen tracks opaque uploaded refs and calls `DELETE /api/v1/media` after terminal result/failure (`lib/screens/wellar_v2_processing_screen.dart:145-186`). Deletion failures are swallowed to avoid exposing refs/errors, which means cleanup failure can leave server media under V2 retention without a visible warning.
- On cancellation after server acceptance, the code deliberately does not delete media because the worker may still need it (`:171-176`, `:205-210`). V2 has no client-visible cancel route in this flow. Thus accepted scan cancellation can leave media retained until backend retention or another cleanup process; that is a privacy/retention dependency to confirm with the V2 owner.
- The production capture screen disposes camera/recorder controllers (`lib/screens/scan_flow_impl_normalized.dart:233-243`), but the reviewed path does not establish comprehensive local deletion of all original/compressed audio/video on cancel, backgrounding, process kill, or failed submission. Controller disposal is not file erasure. This is a **HIGH privacy review item** for actual employee capture until local-file ownership and cleanup are traced end-to-end.
- The test harness's synthetic app-cache files are deleted in a `finally` block (`test/v2_ui_smoke_main.dart:39-58`), but Phase 1C explicitly states the final local-file cleanup patch was not rerun after its AVD became offline. Historical emulator verification did observe V2 server media directory empty after successful completion. Do not conflate server deletion proof with local recording deletion proof.
- No employee/biometric media was created by this review.

## 7. Risks

### HIGH

- **Release confidence blocked by dirty baseline and red suite:** 100 modified tracked paths, 36 untracked paths, no clean baseline, historical 12 failures, and current test runner stalls before events. Current app state cannot be given a release sign-off from this evidence.
- **Local capture retention is not proven:** disposal does not establish deletion; cancellation/app-kill paths and post-failure cleanup need exact file lifecycle evidence. Sensitive media can remain in app cache or server storage after interrupted scans.

### MEDIUM

- **Auth/workspace outcomes:** failures #2–#5 and #10–#11 concern authentication and workspace selection. They are unknown, not safely dismissible as stale tests. Avoid touching auth policy until deterministic focused tests give evidence.
- **External push route contract mismatch:** #7 shows implementation/test disagreement; switching the route based only on the test expectation could break server compatibility.
- **Release isolation not artifact-verified:** source guards look correct, but no release/profile build or merged-manifest inspection was performed; debug dart-define artifacts contain their supplied values.
- **Untracked synthetic test harness:** files under `test/` and `tool/` appear isolated, but should remain out of release entrypoints/assets and should not contain persistent credentials. Current source uses generated synthetic material and harness-scoped identity.

### LOW

- **Test-only Directus seam:** assert-guarded factory is narrowly scoped, but its release behavior should be validated in a release build/test configuration.
- **Audit document consistency:** several untracked audit documents and Phase reports coexist; reviewers should rely on dated evidence and current source rather than treat all reports as synchronized.

## 8. Exact narrow fixes to consider later (not implemented)

1. Restore a known clean baseline in a separate, owner-approved review environment or record a pre-integration commit/tree hash; do not clean this working tree to manufacture one.
2. Run the full suite after resolving the runner startup issue; use per-test timeouts plus an outer process timeout. Capture exact assertion traces for all 12 failures before classifying the six unknown auth/workspace/UI cases.
3. Repair only the two sparse-201 tests' finder strategy if source confirms the changed form fields; keep assertions on the intended refresh behavior.
4. Resolve the push route disagreement against the actual server/API contract, then align test or implementation accordingly.
5. Inspect `App` startup routing and update the splash expectation only if `public_entry` is the intended canonical unauthenticated state.
6. Add/verify deterministic local file deletion in scan completion, pre-acceptance failure, user cancellation, background/kill recovery and failed cleanup paths. Define a server-side retention fallback and observable sanitized cleanup outcome for accepted jobs.
7. Restrict local V2 to `kDebugMode` if profile use is not needed; build a release artifact and inspect merged manifest/config to prove no debug network exception or synthetic entrypoint is packaged.
8. Re-run normal Directus login/workspace/scan finalization tests with isolated mocks and no external requests; separately assert V2 mode has no `/process` request and no Directus mutation.

## 9. Review disposition

**NEEDS REVIEW.** There is not enough clean-baseline or full-suite/runtime evidence to declare the application safe. The source-reviewed V2 boundary appears fail-closed for release and isolated from Directus/legacy processing when disabled, but auth/workspace test failures, broad unrelated working-tree changes, incomplete recording cleanup proof, and absent release build evidence remain open. Do not state “completely safe,” and do not ship this dirty tree as release-cleared on this review alone.
