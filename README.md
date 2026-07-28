# Wellar Mobile (`waller_app`)

Wellar Mobile is the Flutter client for Wellar — the on-device experience for
employees, managers, HR, and owners of a Wellar business profile. It captures
scans, surfaces durable in-app notifications, and gives each role a focused
shell over the Wellar backend.

This repository contains only the Flutter mobile app. It does not house the
web application, the Directus backend, the AI processing server, or any
Firebase / store console configuration.

## Prerequisites

- Flutter SDK compatible with the pinned Dart version in `pubspec.yaml`.
- Android Studio + Android SDK (API 34+ recommended for `compileSdk = 36`).
- Xcode 15+ and macOS for iOS release builds.
- A Firebase project already configured for Wellar. Do not create a new one.

## Install dependencies

```
flutter pub get
```

## Debug configuration

Debug builds default to the shared development endpoints declared in
`lib/config/app_config.dart`. No secrets are required for a debug run.

```
flutter run
```

## Store-release configuration

Store-release builds must be driven by a JSON configuration file that populates
the compile-time `String.fromEnvironment` / `bool.fromEnvironment` values.

1. Copy `config/store_release.example.json` to `config/store_release.json` (or
   an equivalent path outside the repo).
2. Fill in the release values.
3. Build with `--dart-define-from-file`:

```
flutter build appbundle --release --dart-define-from-file=config/store_release.json
flutter build ipa       --release --dart-define-from-file=config/store_release.json
```

The example file is committed. The real file must never be committed.
`ENABLE_PUSH_SUBSCRIPTION_WRITES` must be `true` in store-release builds.

## Secrets policy

Nothing sensitive belongs in this repo. That includes keystores, keystore
passwords, `key.properties`, APNs `.p8` keys, service accounts,
`google-services.json`, `GoogleService-Info.plist`, OAuth client secrets, and
any real store-release JSON. All of the above are excluded by `.gitignore`.

## Frozen identifiers

The following identifiers are frozen for this handoff and must not be changed
during the release:

- Android namespace: `com.example.waller_app`
- Android `applicationId`: `com.example.waller_app`
- iOS `PRODUCT_BUNDLE_IDENTIFIER`: `com.example.wallerApp`

Renaming the packages, folders, targets, Firebase applications, MainActivity,
or URL schemes purely to change how the identifiers read is out of scope for
the store handoff.

## Responsibility split

Wellar Mobile is one client. The other pieces of the platform stay with their
respective owners:

- Web application — separate repo, out of scope.
- Directus backend, roles, permissions, and workspace endpoints — out of
  scope.
- Google mobile exchange endpoint — hosted service, out of scope.
- AI processing server — hosted service, out of scope.
- Firebase Console, Play Console, App Store Connect — external systems.

**Organization switching is Web-only.** The mobile app surfaces an
informational notice on Profile → Switch organization directing the user to
the web app. Mobile does not attempt to move a member between organizations.

## Release documentation

- `docs/STORE_RELEASE_HANDOFF.md` — end-to-end checklist for whoever cuts the
  release build.
- `docs/ANDROID_RELEASE.md` — Play Store release steps.
- `docs/IOS_RELEASE.md` — App Store release steps.
- `docs/FIREBASE_AND_FCM.md` — Firebase + push notification wiring.
- `docs/PRIVACY_DATA_INVENTORY.md` — data collected and processed by Mobile.
- `docs/ACCOUNT_DELETION.md` — the current account deletion flow and its
  external dependency.
- `docs/KNOWN_ISSUES.md` — what is done in source vs. what must still be
  supplied outside the repo.
