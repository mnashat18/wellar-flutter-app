# On-device face/eye analysis feasibility

**Verdict: GO-WITH-CONDITIONS** for a local landmark/EAR spike. Do not replace the current score workflow or promise a validated drowsiness/readiness result yet. The checkout records media to files and has no detected Flutter ML/landmark dependency or live camera image stream. A local spike can retain the current capture method, analyze sampled video frames after recording, and prove performance before adding native complexity. Evidence below is static source inspection; no app or production service was run.

## Project location and evidence scope

The requested search under `D:\flutter\last` found no Flutter `pubspec.yaml`; that directory contains `wellar-ai-v2` and server projects. The Flutter project used for this report is `D:\flutter_app\wellar-flutter-app` (`pubspec.yaml`; root directory). V2 eye-feature reference is `D:\flutter\last\wellar-ai-v2\app\media\extractors.py`. The audit is read-only except for this report. Unverifiable facts are explicitly marked `UNVERIFIED`.

## 1. Current capture pipeline

| Question | Finding and evidence |
|---|---|
| Packages | `camera: ^0.11.3`, `record: ^6.2.0`, `image_picker: ^1.2.1`, `path_provider: ^2.1.5`, `get_thumbnail_video: ^0.7.3`, and `video_compress: ^3.1.4` are in `pubspec.yaml:42-51`. |
| State flow | `ScanFlowStep` is `intro → consent → permissions → video → audio → focus` (`lib/screens/scan_flow_impl_normalized.dart:33-35,465-510,545-620`). |
| Video | `CameraController` uses `ResolutionPreset.veryHigh`; requested settings are 1280×720, 30 fps, 3.5 Mbps, H.264/MP4 (`scan_flow_impl_normalized.dart:86-89,1403-1452`). It calls `startVideoRecording()` / `stopVideoRecording()` and keeps the returned `XFile` (`:1452,1505,1569`). Requested settings are preferences; actual negotiated camera resolution/fps are `UNVERIFIED`. There is no `startImageStream` use found in app Dart code. |
| Audio | `record` captures to a path under `getTemporaryDirectory()` and then wraps it in `XFile` (`scan_flow_impl_normalized.dart:1669,1745`). Exact sample rate/channel/codec must be confirmed in recorder configuration; `UNVERIFIED` here. |
| Processing/upload | `ScanFinalizeService` uploads audio and video; it may prefinalize media before the later focus step (`lib/services/scan_finalize_service.dart:70-117,134-363`; `scan_flow_impl_normalized.dart:1576,1807-1835`). Upload also creates a thumbnail and `scan_media` relation (`scan_finalize_service.dart:273-348`). |
| Local retention/deletion | Video/audio are local `XFile` paths; compressed video may be another temp path (`lib/services/scan_service.dart:2005-2054`, `lib/utils/video_compress_io.dart:15-79`). A repository search found no media `File.delete()`/`XFile` deletion call. Restart/invalidation clears in-memory `_videoFile`, `_audioFile`, `_thumbnailBytes` references (`scan_flow_impl_normalized.dart:1585` and capture invalidation near `:2100+`); widget disposal disposes recorder/controller (`:233-243`). Clearing references is not deleting the underlying files. Actual OS/plugin temp-file cleanup timing is **UNVERIFIED**. |

## 2. On-device ML currently present

No MediaPipe, TensorFlow Lite, ML Kit, or face-landmark package/import was found in `pubspec.yaml`, `pubspec.lock`, `lib`, `android`, or `ios` by static search. The capture flow imports `camera`, `record`, `path_provider`, and video thumbnail/compression packages (`scan_flow_impl_normalized.dart:3-18`). On-device landmark inference is therefore **not implemented in this checkout**. No local model asset for mobile landmark inference was identified by this audit.

## 3. Platform targets and device range

- Android and iOS project folders are present. Android uses `minSdk = flutter.minSdkVersion`, `targetSdk = flutter.targetSdkVersion` (`android/app/build.gradle.kts:48-49`); the effective numeric min SDK depends on the Flutter Gradle plugin/version and is **UNVERIFIED** from this file alone.
- iOS deployment target is 13.0 in the Xcode project (`ios/Runner.xcodeproj/project.pbxproj:349,475,526`).
- The repository names no explicit supported device model or performance tier; **device range is UNVERIFIED**. A capture preference of 720p/30 fps is not evidence that all supported hardware sustains it (`scan_flow_impl_normalized.dart:86-89`).

## 4. Landmark options to evaluate

No candidate package is currently declared. This is a proposal shortlist, not a claim that these packages are compatible with this app’s exact Flutter/Dart/native toolchain. Package version, native platform coverage for the chosen release, license of the complete runtime/model, and model size are all **UNVERIFIED offline** and must be checked against pinned upstream artifacts before adoption.

| Candidate | Potential fit | Version / platform / license / model size | Likely project changes |
|---|---|---|---|
| Google ML Kit face detection Flutter plugin | Lowest-friction face/landmark experiment; verify whether its eye landmark output is sufficiently dense/stable for six-point EAR. | **UNVERIFIED**; no dependency in `pubspec.yaml`/`pubspec.lock`. | Add pinned dependency; verify Android/iOS native min requirements and privacy/data behavior; add iOS usage/config and Android manifest/build changes only if plugin docs require them. |
| MediaPipe Tasks Vision Face Landmarker through native Android/iOS bindings and a Flutter platform channel | Better candidate if dense eye contours/iris landmarks are required; inference may run per sampled frame or live stream. | **UNVERIFIED**; no MediaPipe package, channel, or model asset in the app. License and `.task` asset size must be verified for the exact distribution. | Add native Android and iOS task-runner bindings, platform channel/plugin, model asset download/package policy, lifecycle/threading, camera-frame conversion and build configuration. |
| `tflite_flutter` plus a selected face/landmark model | Flexible if a vetted compact model is selected; model output and post-processing become app-owned. | **UNVERIFIED**; neither package nor model exists in the app. Model license, model size, acceleration delegates and platform requirements depend on selected artifact. | Add pinned interpreter dependency, model asset and its license, Android/iOS delegate/native setup, image preprocessing, landmark decoding and model-version checks. |

Do not select by package name alone. For each candidate, verify exact locked version, supported Android/iOS minima, license for both wrapper and native/model assets, offline behavior, model bytes, and measured p50/p95 frame latency on the minimum target device. Existing source evidence for the absence of these integrations: `pubspec.yaml:38-57`, plus the import list at `scan_flow_impl_normalized.dart:3-18`.

## 5. `WellarV2Client` and result parsing

- Default client token provider returns `Session.instance.accessToken`; refresh delegates to `DirectusClient.instance.refreshAuthToken` (`lib/services/wellar_v2_client.dart:82-90`). Request code adds the token as bearer authorization (`:311+`); V2 auth mode must accept the Directus user JWT for this to work. Whether the deployed V2 server validates that issuer/audience is **UNVERIFIED**. The client can technically send the user’s current Directus token; do not substitute a service secret in the mobile app.
- `WellarV2Result` parses `schema_version`, `scan_id`, `status`, `model_version`, `model_invocation_status`, `targets`, `quality`, and `features` (`lib/models/wellar_v2_result.dart:20-60`). Per-target parsing reads only `status`, `value`, and `reason` (`:1-14`). It does not model a typed `drowsiness_indicator`, nor dedicated `insufficient_quality` or `retake` fields. The V2 screen recognizes top-level `status == insufficient_evidence` and any quality value equal to `insufficient_quality`, and then displays a retake recommendation (`lib/screens/wellar_v2_result_screen.dart:12-51`). This is a loose string scan, not a typed retake contract.

## 6. State-machine insertion point and uploaded-file dependencies

**Smallest insertion point:** after video and audio capture have produced local files, and before `_startMediaPrefinalizeIfReady()` starts upload (`scan_flow_impl_normalized.dart:1569-1576,1745,1807-1835`). Run an explicit local-analysis step there using the captured video or sampled frames. Do not insert it after `ScanFinalizeService.start()` because finalize already uploads audio/video and creates/link media records (`lib/services/scan_finalize_service.dart:134-363`). For a privacy-first opt-in model, disable prefinalization until after opt-in.

Current dependencies on upload:

- `ScanFinalizeService` uploads audio/video/thumbnail, creates scan-media relation, marks media ready, then accepts/starts processing (`scan_finalize_service.dart:179-363`).
- `wellness_scans` lifecycle and media file IDs are consumed by `ScanService`; duplicate guard checks recent `pending`, `media_ready`, `processing`, and `in_progress` scans within 10 minutes (`lib/services/scan_service.dart:407-465`).
- Result polling is Directus-based, using `ScanResultPollingPolicy`: 1s early, 2s mid, 3s late, up to 90s (`lib/utils/scan_result_polling_policy.dart:1-23`; calls from scan flow and scan service).
- V2 upload helpers require modality bytes and issue upload requests before scan submission (`lib/services/wellar_v2_client.dart:98-167,171-220`).
- `scan_media` rows, request-completion handling, media-ready status, and duplicate detection must be revised if local-only scans should not upload by default. Keep a distinct local result path or explicitly model “local-only” scan status; do not report a cloud result while these existing server records are absent.

## 7. Unknown states, retake, score UI

### Unknown/insufficient fallback

- `displayRiskLevelLabel` maps null, empty, and every unrecognized risk string to **“High risk”** (`lib/utils/scan_result_display.dart:17-34`). This is the confirmed unknown-state-to-high-risk fallback and must be replaced with an explicit `Unknown`/`Insufficient evidence` state before on-device abstention is wired in.
- `scan_details_screen.dart` has separate status normalization and retake detection (`:700-735,934-939`); unknown handling there should be reviewed against the display helper before rollout. Exact behavior for all malformed/unknown values: **UNVERIFIED** without enumerating the helper’s complete method body.
- History maps recognized risk tokens and otherwise may show the source label (`lib/screens/history_screen.dart:419-504`); it does not use the helper’s guaranteed high-risk fallback in that method.
- V2 result UI already distinguishes `insufficient_evidence`, `model_unavailable`, and quality values containing `insufficient_quality` (`wellar_v2_result_screen.dart:12-51`).

### Retake states

- Legacy result detail checks retake condition and changes prominent status/message/CTAs (`lib/screens/scan_details_screen.dart:700-735,786-830`).
- Company readiness request projection has explicit “Retake needed”, “Result unavailable”, “Result requires review”, and “Processing assessment” outcomes (`lib/screens/company_readiness_results_screen.dart:575-617`).
- V2 screen recommends retake only when a `quality` value exactly matches `insufficient_quality` (`wellar_v2_result_screen.dart:12-46`). Map local landmark failure, low face coverage, low sample count, and analyzer timeout into typed insufficient-quality reasons and a real retake action; do not equate “no face” with high risk.

### Score-dependent UI inventory found

This app’s screens and summaries depend on legacy readiness/confidence/risk fields. Static search found these user-facing consumers; no standalone fatigue/focus/risk numeric fields are parsed by `WellarV2Result`:

- Scan detail: readiness percentage, confidence, camera confidence, task score and risk label (`lib/screens/scan_details_screen.dart:712-735,767-850`; `lib/utils/scan_result_display.dart:75-124`).
- Home dashboard: readiness gauge derived from scan confidence/history (`lib/screens/home/home_dashboard.dart:61-73,137-161,219-240,494-495`).
- Company/owner/admin summaries: readiness scores and four-state distributions (`lib/screens/company_readiness_results_screen.dart:165-256,961+`; `lib/screens/owner_company_screen.dart:485,619-708`; `lib/screens/admin_scan_requests_screen.dart:396-409`).
- Analytics and company dashboard: average confidence and readiness concern aggregates (`lib/screens/analytics_screen.dart:293-335,698-699,1150-1155`; `lib/screens/company_dashboard_screen.dart:582-719,1228-1229`).
- Alert details and owner scan history display readiness (`lib/screens/alert_detail_screen.dart:211-212`; `lib/screens/owner_scan_history_screen.dart:179-204`).
- History and manager screens display readiness state/distributions (`lib/screens/history_screen.dart:333,419-504`; `lib/screens/manager_home_screen.dart:326-335`; `lib/screens/manager_team_screen.dart:220-221`).

Full app-wide UI dependency inventory should be generated by a focused follow-up search before removing legacy fields; the list above is the high-confidence set identified by this audit. `ScanResult` fields and nullability are defined in `lib/models/scan_result.dart:1-110`.

## 8. Consent changes for local-only-by-default

Current English scan text explicitly consents to processing captured JPEG, MP4 and WAV “directly by Wellar AI V2” and says research is off and scores are unavailable (`lib/screens/scan_flow_impl_normalized.dart:782-793`). Capture requires acceptance (`:1907-1931`). Other consent/localization strings exist in English and Arabic (`lib/i18n/tr.dart:158-167,684-693`).

For “analysis on device, nothing uploaded unless opted in,” update both languages and all scan entry points to state: (1) analysis occurs locally; (2) media stays on device by default; (3) exactly which media and derived outputs leave the device on opt-in; (4) destination, purpose, retention and withdrawal; (5) whether metadata/results still sync when media is not uploaded. Separate local-analysis consent from cloud-upload consent. Gate `startMediaPrefinalize`, `/files` uploads, scan-media creation, and V2 media upload behind explicit upload opt-in; current V2 request hardcodes media processing true and research use false (`lib/services/wellar_v2_client.dart:198`). Ensure local deletion happens after local analysis and is verified, not merely clearing references. Exact existing Arabic wording semantics need human review; source contains separate Arabic strings at `tr.dart:684-693`.

## 9. Dart port requirements, effort and ordering

### V2 temporal eye feature behavior to reproduce

The reference is `D:\flutter\last\wellar-ai-v2\app\media\extractors.py:31-40,74-119,122-152`.

1. Six-point EAR from normalized landmark coordinates: compute two vertical distances divided by twice horizontal distance; reject malformed/nonfinite points and nonpositive horizontal span (`_ear`, lines 31-40; left/right indices are module constants near lines 12-16).
2. Validate finite positive duration and sampling rate; handle empty observations with a complete zero/nullable result and explicit `face_not_detected` status (74-82).
3. Compute expected sample count, nearest time bins, face/sampling/overall coverage and missingness without treating absent observations as open eyes (82-89).
4. Integrate closure and mouth-open time only across continuous neighboring observations with valid face/eye points; exclude intervals beyond `max(.25, 1.5/sampling_hz)` and avoid interpolation (89-113, output exclusion semantics at 119).
5. Blink event requires closed run duration 0.1–0.5s; report closure-event counts, blink rate/minute, mean/max closure duration (98-102,117-119). Mouth-opening event duration is 0.2–3.0s and is explicitly not a yawn/sleepiness label (103-113,119).
6. Short-clip closure fraction is available only if minimum observed eye seconds, valid sample count, temporal coverage and sampling Hz all meet configured thresholds; otherwise return null with the specific insufficient reason (115-119 plus constants near lines 18-25). `perclos_estimate` remains null/deprecated; never rename this sparse descriptive fraction to PERCLOS (119).
7. Preserve feature-version, model/runtime metadata, timestamps, and quality fields used downstream (`extractors.py:122-168`).

Exact EAR cutoff, event thresholds and configured minima are read from constants/config (`extractors.py:12-25`); copy their values only from those sources, not from the prose above.

### Golden-vector format

Check in a small JSON fixture per deterministic synthetic sequence, not media: `{schema_version, feature_version, sampling_hz, duration_seconds, ear_threshold, observations:[{timestamp_seconds, face_valid, left_eye:[6 normalized xy points], right_eye:[6 normalized xy points], mouth_open}], expected:{ear_per_sample, face_coverage, sampling_coverage, overall_coverage, closure_event_count, blink_event_count, blink_rate_per_minute, short_clip_eye_closure_fraction, short_eye_feature_status, perclos_estimate:null}}`. Use explicit numeric tolerances per float and exact equality for counts/status/nulls. Include empty, malformed, nonfinite, gap, 0.1s/0.5s boundary, insufficient coverage and sampling-rate vectors. Cross-check the Dart implementation against Python output generated from the V2 function using only synthetic observations. Track generator seed and parameters; no real face media is needed.

### Minimal spike and estimated changes

| Order | Change / effort | Risk and gate |
|---|---|---|
| 1 | Inventory candidate upstream SDK/model licenses, platform minima, artifact bytes, exact pinned versions: 4–8h | High compliance/build risk until both native SDK and model license are confirmed. |
| 2 | Spike one native landmark path behind a feature flag, initially decode saved synthetic face-like frames, return six-point eyes: 12–24h | High device/API/threading risk. No real user capture/upload. |
| 3 | Port EAR and temporal eye aggregation to pure Dart; add golden JSON vectors: 8–16h | Medium semantic drift risk; gate on matching reference vectors and uncertainty behavior. |
| 4 | Run camera capture + local analyzer on a mid-range Android and iPhone; measure throughput/thermal/memory: 8–16h | High performance variance. Gate: sustained >=15 analyzed frames/s on both target devices, with actual measured resolution and no UI jank/crash. |
| 5 | Add typed insufficient/retake state and remove unknown=>High risk mapping; update every score consumer and tests: 12–24h | High user/safety risk due multiple dashboards and report aggregations. |
| 6 | Add local-only default, separate upload opt-in, deletion verification, and bilingual consent: 12–24h | High privacy/state migration risk; ensure no prefinalize upload before opt-in. |
| 7 | Integrate as optional analyzer stage in scan flow; preserve or explicitly migrate `scan_media`, finalize, duplicate guard and status/history semantics: 12–24h | High compatibility risk; current cloud workflows assume uploaded media and Directus rows. |

**Estimated total: 68–136 engineering hours**, excluding vendor/legal review, device procurement, accessibility/localization review and release acceptance. It assumes one candidate path; a switch from candidate after licensing/build failure adds time.

### Smallest proving experiment

1. Build a debug-only spike on one mid-range Android and one current supported iPhone; exact device models are owner choice (**UNVERIFIED**). Keep capture to local MP4 as today.
2. Generate synthetic 720p frames with a deterministic face-like pattern and synthetic eye landmarks with known open/closed sequence; also use an openly licensed sample only after license verification. Do not use pilot media.
3. Run native landmark inference on at least 15 frames/s for a 60-second run, concurrently compute EAR in Dart/native bridge, and record analyzed fps, per-frame p50/p95/max latency, dropped frames, memory, thermal throttling, and UI frame jank.
4. Compare EAR/blink/closure outputs with ground truth vectors and V2 Python outputs. Pass only if measured sustained throughput is >=15 fps on both devices, output tolerances pass, and timeout/no-face results produce insufficient-quality rather than a high-risk score.

