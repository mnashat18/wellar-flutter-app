# Wellar AI V2 Android handoff

## Integration contract

The app keeps its Directus scan creation, `/files` uploads, `media_ready` update, and Directus `scan_results` polling. When it triggers the configured process URL, it uses the signed-in Directus access token through the existing shared Directus Dio client (including its refresh interceptor). It GETs the Directus scan row and verifies that `user` equals the signed-in session user before submission.

The process URL is configured with `--dart-define=WELLAR_AI_SERVER_URL=https://<host>/process`. `WELLAR_AI_SERVER_URL` takes precedence over the older `AI_SERVER_URL` define; the existing URL remains the fallback. No credential belongs in a Dart define or source file.

| JSON key | App now sends | V2 accepts | Notes |
|---|---|---|---|
| `scan_id` | Directus scan UUID string | required UUID string | Same |
| `user_id` | `Session.instance.userId` | required; must equal authenticated Directus user | App checks scan owner first |
| `video_file_id` | Directus video file UUID | required UUID string | Same |
| `audio_file_id` | Directus WAV file UUID | required UUID string | Same |
| `image_file_id` | omitted | optional UUID string | App has not connected the thumbnail ID to this request |
| `task_metrics` | scan row map, reduced to at most 32 entries | optional object, max 32 keys | Trimmed to fit total body cap |
| `device_info` | scan row map, reduced to at most 32 entries | optional object, max 32 keys | Trimmed to fit total body cap |
| `environment_info` | scan row map, reduced to at most 32 entries | optional object, max 32 keys | Trimmed to fit total body cap |

The app omits all other scan-row fields. It removes metadata entries until the encoded JSON body is at most 16 KiB. V2 returns HTTP 202; the existing Directus poller continues to obtain the terminal result. Evidence: `lib/services/scan_service.dart` (`triggerAiServerProcess`, `_boundedMetadata`), `lib/services/scan_finalize_service.dart` (`_triggerAiProcess`), V2 `docs/INTEGRATION.md` and `openapi.json`.

## Media before and after

| Media | Before | After |
|---|---|---|
| Audio | Legacy recorder path: AAC-LC, mono, 44.1 kHz, 128 kbps, `.m4a`; V2 branch had WAV at 44.1 kHz | WAV encoder, PCM 16-bit, mono, 16 kHz, `.wav`; upload part MIME `audio/wav` |
| Video | 5-second MP4, preferred 1280×720 at 30 fps and 3.5 Mbps; upload hard cap 80 MiB | MP4, preferred 1280×720 at 30 fps and 2 Mbps; Directus part MIME `video/mp4`; hard cap 18 MiB |
| Image | Thumbnail JPEG bytes, inferred multipart MIME | JPEG bytes, explicit `image/jpeg` multipart MIME |

The 2 Mbps/5-second target is about 1.2 MiB before container overhead; the app rejects output above 18 MiB. This is a target plus a hard rejection limit, not a guarantee that every encoder output will be below 18 MiB. Evidence: `lib/screens/scan_flow_impl_normalized.dart`, `lib/utils/video_compress_io.dart`, `lib/services/scan_service.dart` (`uploadXFile`, `uploadVideoFile`, `uploadBytes`).

Local cleanup code-path review: capture video compression removes a distinct raw source after preparation; terminal result, failed/pending resolution, or screen disposal waits for in-flight video preparation and media prefinalization before deleting the owned video/audio files (`_cleanupCapturedFiles`, `dispose`, `_openResultPollingScreen`, and terminal state handlers in `scan_flow_impl_normalized.dart`). The V2 processing route deletes its two local files in `finally` and on route disposal (`wellar_v2_processing_screen.dart`). The Directus upload's temporary safe MP4 copy is removed in `uploadVideoFile`'s `finally`, and its distinct compression intermediate is removed after copy (`scan_service.dart`). The thumbnail is held as `Uint8List` in memory and is not written as a separate local thumbnail file. This is source review, not device filesystem test evidence.

## Tenant identity: UNVERIFIED

V2 directus auth resolves `tenant_id` from the authenticated Directus user's `active_business_profile` and checks membership against that tenant (`D:\flutter\last\wellar-ai-v2\app\security\auth.py`, `docs/INTEGRATION.md`). The app writes `wellness_scans.business_profile` from its active workspace selection. The checked-in code does not prove that the app's selected workspace always equals the Directus user's `active_business_profile`, so the relationship is **UNVERIFIED**, not assumed to match.

Required fix before rollout: require the app's selected business profile to equal the authenticated user's `active_business_profile` before `/process`, and fail closed on mismatch; alternatively change the V2 auth integration to derive tenant from the scan's `business_profile` only after verifying scan ownership and membership. Confirm this with a test account against the staging Directus instance.

## Result schema comparison

V2 writes `risk_level`, `readiness_score`, `confidence`, `ai_model_version`, `baseline_used`, `explanation`, and structured `internal_analysis` (`app/compat/directus_facade.py`, `app/compat/legacy_projection.py`). The Directus snapshot has all seven field names; none are absent. Snapshot types: `risk_level:string`, `readiness_score:decimal`, `confidence:decimal`, `ai_model_version:string`, `baseline_used:boolean`, `explanation:text` (required), `internal_analysis:string` (`backend/directus/schema/directus-schema.snapshot.yaml`, `scan_results` fields). Numeric scores remain null by contract.

Schema concern: V2 supplies `internal_analysis` as an object, while the snapshot declares the field as `string`. Confirm whether the deployed Directus API serializes that object into the string field. If it does not, change that existing field to a JSON-capable Directus field (database JSON, Directus type `json`, optional, interface `input-code`) or explicitly JSON-encode at the V2 writer. Do not add duplicate `internal_analysis` fields. The snapshot's required `explanation` also needs a non-null V2 string for every write path.

## Directus flow

The checked-in `backend/directus/flows/directus-flows.commit-safe.json` export marks `WallerAi` **inactive** (`trigger:event`, `scope:items.update`, `collections:wellness_scans`). This is export evidence only; live instance status is **UNVERIFIED**. Keep it inactive/disable it in the deployed instance if it triggers the same `/process` endpoint, because the app now triggers `/process` itself after `media_ready` and duplicate processing can race the V2 result writer.

The read-only scan of `D:\flutter\last\wellar-ai-v2\requirements-lock.txt` found no Windows-only package markers (`win32`, `windows`, `pywin`, `wmi`). This does not replace a Linux Docker dependency installation check.

## Ten-step Android staging test

Use only a test account and a staging Directus/V2 deployment.

1. Configure `WELLAR_AI_SERVER_URL` to the staging V2 `/process` URL and sign in as a test user with an active business profile.
2. Start a scan and accept the revised consent; verify the prompt describes face/eye signals, optional photo, deletion, and no training/research use.
3. Record the five-second face video and five-second voice sample; confirm the app produces MP4 and WAV and proceeds through the existing focus task.
4. Complete the scan and inspect the Directus `wellness_scans` row: `user`, `business_profile`, and initial status are correct for the test account.
5. Inspect the Directus `/files` records uploaded by the app: video MIME `video/mp4`, audio MIME `audio/wav`, optional thumbnail MIME `image/jpeg`; record their IDs for verification.
6. Inspect `scan_media`: video/audio IDs must be related to the same `scan_id` before processing begins.
7. Confirm the app's `/process` request contains only `scan_id`, `user_id`, `video_file_id`, `audio_file_id`, and bounded `task_metrics`, `device_info`, `environment_info`; verify its bearer identity is the test user's Directus session (do not copy the token into a report).
8. Confirm `/process` returns 202 and the app continues polling Directus, with no duplicate WallerAi invocation.
9. Inspect `wellness_scans.status` (`completed` or `retake_required`) and the matching `scan_results` row: `risk_level`, `readiness_score`, `confidence`, `ai_model_version`, `baseline_used`, `explanation`, `internal_analysis`. Null scores must stay null. For insufficient quality verify `risk_level` is null and status is `retake_required`.
10. After terminal success/failure, inspect `internal_analysis.deletion_proven` and GET each original media ID from Directus `/files`; V2's documented contract expects deletion to be proven and the media no longer retrievable. Also verify the app's local capture and audio files are absent from their temporary paths after navigation/cleanup.

## Change and verification record

Changed for this work: `lib/services/scan_service.dart`, `lib/services/scan_finalize_service.dart`, `lib/screens/scan_flow_impl_normalized.dart`, `lib/screens/wellar_v2_processing_screen.dart`, `lib/utils/video_compress_io.dart`, `lib/utils/scan_local_media_cleanup.dart`, `lib/config/app_config.dart`, `lib/i18n/tr.dart`, `lib/utils/scan_result_display.dart`, `lib/utils/readiness_distribution.dart`, `lib/screens/scan_details_screen.dart`, `lib/screens/history_screen.dart`, `lib/screens/owner_scan_history_screen.dart`, `lib/screens/company_readiness_results_screen.dart`, `lib/screens/home/home_dashboard.dart`, `lib/screens/owner_home_screen.dart`, `lib/services/owner_ops_service.dart`, `lib/screens/analytics_screen.dart`, `lib/screens/company_dashboard_screen.dart`, `test/scan_result_display_test.dart`, and this handoff.

No commits were created. At the beginning of this run, the repository already had a broad set of modified and untracked files, including the same app integration files. Committing those paths would include pre-existing changes, so the requested per-task commits could not be made without risking unrelated user work. No existing changes were reset or overwritten. Backups for files edited during this run are in the machine temp directory `wellar-task-backups`.

`flutter analyze --no-pub` completed with exit code 1 and 320 diagnostics across the whole workspace (warnings/info; the terminal output was truncated). A changed-file analysis reported 129 diagnostics including three compile errors; the three errors were fixed, then a focused analysis of the three affected Dart files reported 91 warning/info diagnostics and no errors. The full test command (`flutter test --no-pub --reporter compact`) and a focused `scan_result_display_test.dart` run both stayed silent for over two minutes; both were stopped. Test pass/fail counts are **UNVERIFIED**. No tests were edited except `test/scan_result_display_test.dart`, which updates unknown/null/retake mapping expectations.
