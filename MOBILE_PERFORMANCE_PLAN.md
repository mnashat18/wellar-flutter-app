# Mobile Performance and Scale Plan

**Audit-only recommendations.** No code or API contract was changed. This plan targets responsive capture/result UX, lower request and media costs, and readiness evidence for a tenant of 2,000 employees. Tenant size is not assumed to mean 2,000 simultaneous scans.

## Current performance profile

- Capture: `lib/screens/scan_flow_impl_normalized.dart` requests `ResolutionPreset.veryHigh`; it also declares 1280×720/30fps/3.5Mbps preferences. The resolution can exceed the stated target on some devices.
- Compression/upload: `lib/utils/video_compress_io.dart` uses a 720p quality profile and 30fps but does not pass the logged bitrate as an explicit compressor parameter. It retains original media (`deleteOrigin:false`) and has fallback behavior that may upload the original. `lib/services/scan_service.dart` limits compressed video to 80MB, uses multipart-from-file on mobile, and has long upload timeouts. Temporary file cleanup is not apparent.
- Polling: scan-flow, result screen, and `ScanSyncService` each have polling implementations. They can overlap across routes or recovery paths. The results screen polls status frequently and performs additional result lookups. Push notifications are not a demonstrated job-state source of truth.
- Data access: `fetchHistoryTimeline` does sequential per-scan result retrieval. Home data and home scan providers issue separate `fetchHomeData` calls. Workforce screens use fixed limits and eagerly build lists.
- UI: a 700ms status timer calls `setState` during scan processing. Poll and state changes should be measured on low-end devices and while upload/processing is active.

## Minimal phased plan

### P0 — prevent wasted AI work and duplicate traffic

1. Introduce one scan-job coordinator/repository that owns state, one poll loop, and one in-flight request per scan ID. UI screens subscribe to it; navigation must not start a second loop.
2. Make “check/resume existing scan” the timeout/reconnect path. Do not create a new scan simply because the result deadline elapsed.
3. Gate transport retries by operation safety. For compatibility, keep paths, payloads, and deployed endpoints unchanged; avoid automatic replay of POST create/upload/process requests when outcome is uncertain. Retry reads with bounded exponential backoff and jitter. Any write retry should require server-confirmed deduplication or an explicit, supported idempotency contract.
4. Persist minimal scan job metadata and reconcile it at app startup/resume. See state machine in `MOBILE_AUDIT.md`.

### P1 — reduce requests and media cost

1. Unify polling policy: single-flight status read, adaptive exponential backoff with jitter, pause while backgrounded/offline, immediate reconciliation on resume/connectivity, and a visible “still processing” state with no implied failure. Use push only as a wake-up hint; fetch authoritative status from the existing API.
2. Stop result polling once a result is present. If status is completed but result is not yet visible, retry only the result read with a bounded consistency window; never re-dispatch AI.
3. Replace N+1 history reads with a batched result query using the already-used scan ID filter where deployed API supports it. Keep request schema/API compatible; retain graceful fallback only if batch response semantics require it. Consolidate home data providers to avoid the duplicate 50-row fetch.
4. Choose capture resolution based on device capability and a documented maximum; enforce a true output-size/bitrate budget and verify compressor output metadata. Prefer upload of a bounded compressed file; if compression fails, ask whether to retry compression or cancel rather than silently send a very large source.
5. Delete raw, compressed, audio, and thumbnail temp files after successful upload or explicit cancellation, using `finally` cleanup and ensuring no active upload still references them. Enforce free-space checks and cap retained failed-job artifacts.
6. Use paged server queries for employee/history lists and lazy builders (`ListView.builder`/slivers). Provide server-side search/filter and explicit “load more”; do not fetch all 2,000 employee records into a widget.

### P2 — responsiveness and instrumentation

- Replace a 700ms whole-screen `setState` pulse with a localized animation/timer or derive elapsed status from a ticker; confirm with frame timings.
- Keep compression/file hashing off the UI isolate if synchronous CPU work is introduced; profile actual plugin work on representative Android/iOS hardware.
- Add sampled performance events containing only pseudonymous scan correlation ID, stage, duration, bytes bucket, retry count, network type, app version, and device class. Do not capture media or content.
- Configure centrally managed crash reporting only after privacy/retention and consent review. Add dashboards for stage durations, upload failures, uncertain dispatches, result latency, poll volume, process restarts/resumes, and crash-free scan sessions.

## 2,000-employee validation plan

Define separate dimensions: total directory size, active daily users, peak concurrent scans, scans per hour, expected media size, and AI service throughput. Load test with staged cohorts; do not infer safe concurrency from the mobile client. Backend/API owners must establish queue capacity and rate limits.

Suggested client/performance gates (targets are proposals, to be validated on agreed reference devices):

| Scenario | Measurement / gate |
|---|---|
| Workforce directory of 2,000 | First page bounded and interactive; pagination/search avoids full-result materialization; scroll frame times measured on low-tier Android. |
| Scan upload on constrained 4G and Wi-Fi | Progress is visible; bounded retries; no duplicate media records on ambiguous response; record p50/p95 upload duration and bytes. |
| AI job 2–10 minutes | Poll request volume is bounded; backgrounding does not continue a hot loop; resume reconnects to same scan ID and dispatch count stays one. |
| Low storage / slow CPU | Compression failure is surfaced; no unbounded memory spike; no upload of source media above agreed budget without user confirmation. |
| Results/history | Request count proportional to pages, not rows; no N+1 regression; p95 time-to-result separated from AI processing time. |

## Regression tests to add (not run as part of this audit)

- Unit: polling backoff/jitter bounds, terminal-state transitions, completed-but-result-late behavior, retry classification by HTTP method/operation.
- Service: concurrent submit coalescing, ambiguous `POST /process` timeout reconciliation, no second dispatch after resume, upload response-loss behavior, token expiry during AI dispatch, result-read-only retries.
- Widget/integration: double tap, navigate away/back, app lifecycle pause/resume, offline/online, process restart with persisted scan ID, long-running processing without “retake” promotion.
- Performance: 2,000-row directory paging, low-end device scrolling/frame timeline, large video compression/upload peak memory and temp-file cleanup.
- Contract: assert existing deployed endpoint paths and request bodies remain unchanged for the mobile-only phase.
