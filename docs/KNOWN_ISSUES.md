# Known Issues and Handoff Boundaries

This document draws the line between what the source is ready for and what
must still be supplied outside the repository.

## Code implemented (source-complete)

- Authenticated cold start routes through `SplashScreen`, which uses the
  session-aware verified route resolver.
- Scan flow enforces a five-second audio duration, auto-stops the recorder,
  and auto-advances into finalize with duplicate-transition guards.
- `AI_SERVER_URL` and `ACCOUNT_DELETION_URL` are wired as
  `String.fromEnvironment` values, with the AI URL defaulting to the current
  working AI server and the deletion URL defaulting to empty.
- `ScanService` pulls the AI process URL from `AppConfig.aiServerUrl`.
- Profile → Delete account validates the deletion URL is HTTPS, opens the
  external page when configured, and reports "not configured" when absent.
  The client never claims server-side deletion.
- Android release signing loads from `android/key.properties`. Release
  bundle / assemble tasks fail fast if the file is missing. Local debug
  workflows are unaffected.
- Android manifest declares only the permissions actually justified by
  active source (INTERNET, POST_NOTIFICATIONS, CAMERA, RECORD_AUDIO,
  READ_MEDIA_VIDEO, READ_MEDIA_IMAGES). `usesCleartextTraffic` is `false`;
  every production URL in `AppConfig` is HTTPS.
- Firebase / FCM wiring is present: background handler, token acquisition,
  token refresh, foreground / background / terminated message handling,
  notification permission request, and durable-notification-first
  architecture.
- iOS `Info.plist` declares camera, microphone, photo library usage strings
  and `UIBackgroundModes = remote-notification`.
- Store-release configuration example exists at
  `config/store_release.example.json` with all required keys.
- `.gitignore` excludes keystores, `key.properties`, `google-services.json`,
  `GoogleService-Info.plist`, and local environment files.

## Runtime verification required

The store handoff prep is source-only. The following must be verified on a
real device before submission:

- `flutter analyze` passes cleanly on the release configuration.
- Cold start goes through the splash → routed shell (authenticated) or
  splash → public entry (unauthenticated).
- Scan capture: camera, five-second audio auto-stop, thumbnail generation,
  upload to Directus, AI processing round-trip.
- Google Sign-In completes on both Android and iOS builds signed with the
  real release identities.
- FCM foreground, background, and terminated push handling.
- Push subscription writes land in Directus with
  `ENABLE_PUSH_SUBSCRIPTION_WRITES = true`.
- Profile → Delete account opens the real deletion page.
- Report / export download opens successfully.

## External credentials / configuration required

These are not present in the repository by design and must be supplied by
whoever cuts the release:

- Android upload keystore + `android/key.properties`.
- Firebase Android app configured with the release SHA-1 / SHA-256, and
  `google-services.json` placed under `android/app/`.
- Google OAuth Android client for `com.example.waller_app` with the release
  SHA-1.
- iOS Firebase app configured with bundle ID `com.example.wallerApp`, and
  `GoogleService-Info.plist` placed under `ios/Runner/`.
- iOS reversed client ID `CFBundleURLTypes` entry added via Xcode.
- iOS Push Notifications capability enabled on the App ID.
- APNs `.p8` authentication key uploaded to the Firebase Console.
- Apple Developer Team and distribution provisioning.
- Real values for `GOOGLE_MOBILE_CLIENT_ID` and `ACCOUNT_DELETION_URL` in
  the store-release JSON.

## Store console metadata required

- Play Console listing: title, short/full description, screenshots, feature
  graphic, content rating questionnaire, data safety declarations, privacy
  policy URL, account deletion URL.
- App Store Connect listing: app name, subtitle, promotional text,
  keywords, screenshots, App Privacy questionnaire, in-app account deletion
  disclosure, review notes covering the mobile exchange endpoint used by
  Google Sign-In.

## Explicit limitations of this handoff

- No Flutter / Dart / Gradle / Xcode / npm command was executed.
- No analyzer or test suite was run.
- No AAB, IPA, keystore, or provisioning profile was produced.
- Backend, Directus, web app, AI server, and Firebase / Play / App Store
  consoles were not modified.
