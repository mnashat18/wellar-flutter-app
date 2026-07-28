# Wellar Mobile — Store Release Handoff

This document is the top-level checklist for whoever cuts the Play Store and
App Store builds. It links out to the platform-specific documents.

## Scope of this handoff

Source-level preparation only. No real credentials, keystores, provisioning
profiles, APNs keys, service accounts, or store metadata are included in
this repository.

## Frozen identifiers

- Android namespace: `com.example.waller_app`
- Android `applicationId`: `com.example.waller_app`
- iOS `PRODUCT_BUNDLE_IDENTIFIER`: `com.example.wallerApp`

Do not rename packages, folders, targets, Firebase apps, or URL schemes.

## Preflight

1. `flutter --version` matches the SDK pinned in `pubspec.yaml`.
2. `flutter pub get` completes clean.
3. Copy `config/store_release.example.json` to `config/store_release.json` and
   fill in every value (see `README.md`).
4. `ACCOUNT_DELETION_URL` must be a live HTTPS URL before submission.
5. `ENABLE_PUSH_SUBSCRIPTION_WRITES` must be `true`.

## Android

Follow `docs/ANDROID_RELEASE.md`.

Highlights:

- Create the upload keystore locally, drop `key.properties` into `android/`
  (excluded from Git).
- Confirm `google-services.json` for `com.example.waller_app` is placed at
  `android/app/google-services.json`.
- Build with `flutter build appbundle --release --dart-define-from-file=...`.
- The AAB lands under `build/app/outputs/bundle/release/`.

## iOS

Follow `docs/IOS_RELEASE.md`.

Highlights:

- Configure the Apple Developer Team in Xcode.
- Confirm `GoogleService-Info.plist` for `com.example.wallerApp` is placed at
  `ios/Runner/GoogleService-Info.plist`.
- Add the reversed client ID `CFBundleURLTypes` entry in Xcode (see the iOS
  release doc).
- Enable Push Notifications capability + Remote notifications background
  mode.
- Upload the APNs authentication key in the Firebase Console.
- Archive → TestFlight → App Store.

## Firebase

Follow `docs/FIREBASE_AND_FCM.md`.

## Privacy and account deletion

Follow `docs/PRIVACY_DATA_INVENTORY.md` and `docs/ACCOUNT_DELETION.md`. The
Play Console requires a deletion URL. The App Store requires in-app
initiation of deletion.

## What is done vs. still required

`docs/KNOWN_ISSUES.md` separates source-complete items from items requiring
external credentials or store console metadata.
