# iOS Release

## Bundle identity

- `PRODUCT_BUNDLE_IDENTIFIER = com.example.wallerApp`.
- The bundle identifier is fixed. It must match the Firebase iOS app and the
  provisioning profile that ships to App Store Connect. Do not rename it
  during the release.

## Requirements

- macOS with Xcode 15+.
- Command line tools: `xcode-select --install`.
- CocoaPods: `sudo gem install cocoapods` (or Homebrew).
- Apple Developer account with an active Team ID and the Wellar App ID
  provisioned.

## Apple Developer Team

Open `ios/Runner.xcworkspace` in Xcode. In the Runner target's Signing &
Capabilities pane, select the Apple Developer Team associated with the
Wellar App ID. Automatic signing is the default; use a manual provisioning
profile if the account policy requires it.

## GoogleService-Info.plist

Download `GoogleService-Info.plist` for the Firebase iOS app whose bundle ID
is `com.example.wallerApp` and place it at
`ios/Runner/GoogleService-Info.plist`. The file is `.gitignore`d.

## Google reversed client ID URL scheme

`Info.plist` intentionally does not hard-code a Google reversed client ID.
The uploader must add a `CFBundleURLTypes` entry that mirrors the
`REVERSED_CLIENT_ID` string from the real `GoogleService-Info.plist` — this
is the callback URL scheme that Google Sign-In listens on.

Add via Xcode → Runner → Info → URL Types:

- Identifier: `google-sign-in`
- URL Schemes: the value of `REVERSED_CLIENT_ID` from
  `ios/Runner/GoogleService-Info.plist` (looks like
  `com.googleusercontent.apps.<numbers>-<hash>`).
- Role: Editor.

Equivalent `Info.plist` XML the uploader may paste manually:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>google-sign-in</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>REPLACE_WITH_REVERSED_CLIENT_ID</string>
        </array>
    </dict>
</array>
```

## Push Notifications capability

In Xcode → Runner target → Signing & Capabilities:

1. Click `+ Capability` and add **Push Notifications**. Xcode will create the
   `Runner.entitlements` file and register the App ID for push.
2. Click `+ Capability` again and add **Background Modes**. Enable
   **Remote notifications**. (`Info.plist` already declares
   `UIBackgroundModes` with `remote-notification`, but the capability must
   still be enabled on the App ID.)

## APNs authentication key

APNs is configured on the Firebase side, not in this repo.

1. In Apple Developer → Certificates, Identifiers & Profiles → Keys, create
   an APNs authentication key (`.p8`). Note the Key ID and Team ID.
2. In Firebase Console → Project Settings → Cloud Messaging → Apple app
   configuration, upload the `.p8`, Key ID, and Team ID.
3. Never commit the `.p8` file to Git. Store it as an external secret.

## Provisioning

Automatic signing is sufficient for TestFlight and production if the App ID
has Push Notifications enabled and the Team has an active distribution
certificate. Otherwise, use a manual App Store distribution provisioning
profile.

## Archive and upload

1. In Xcode, select the `Runner` scheme and the `Any iOS Device (arm64)`
   destination.
2. Product → Archive.
3. Distribute App → App Store Connect → Upload.

Alternative via CLI:

```
flutter build ipa --release --dart-define-from-file=config/store_release.json
```

The archive lands under `build/ios/archive/`. Upload via Transporter or
`xcrun altool` / `xcrun notarytool` as appropriate.

## Real-device validation

Before submitting for review, validate on a real device:

- Google Sign-In completes end to end.
- FCM token is obtained and push subscription writes succeed.
- Foreground, background, and terminated notifications route correctly.
- Camera and microphone capture during the scan flow.
- Delete account link opens the configured deletion page.

## Never in Git

- `ios/Runner/GoogleService-Info.plist`
- APNs `.p8` keys
- Provisioning profiles (`*.mobileprovision`)
- Any store-release JSON with filled values
