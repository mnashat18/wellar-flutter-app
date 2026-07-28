# Android Release

## Package identity

- `applicationId` and `namespace`: `com.example.waller_app`.
- The `applicationId` is fixed. It is the Play Store identity of Wellar
  Mobile, and it must match the Firebase Android app and the Google OAuth
  Android client. Do not rename it during the release. Once published, an
  `applicationId` cannot be reused for a different app in the Play Console.

## Upload keystore

1. On the release machine, create the upload keystore:

   ```
   keytool -genkey -v -keystore android/upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias wellar-upload
   ```

2. Place the keystore file wherever `key.properties` points to. The default
   in `android/key.properties.example` is `android/upload-keystore.jks`.

3. Copy `android/key.properties.example` to `android/key.properties` and
   fill in `storeFile`, `storePassword`, `keyAlias`, `keyPassword`.

Neither the keystore nor `key.properties` may be committed. Both are already
in `.gitignore`. If either becomes lost, the app can only be re-published
under a new key via Play App Signing key upgrade — treat them as
production secrets.

## Extract SHA-1 / SHA-256

Google OAuth (Android type) requires the SHA-1 (and Play App Signing key
SHA-256) tied to the release signature.

Local upload key:

```
keytool -list -v -keystore android/upload-keystore.jks -alias wellar-upload
```

Play App Signing key: available in Play Console → Setup → App integrity.
Copy the SHA-1 and SHA-256 fingerprints from there.

## Firebase Android app

Ensure the Firebase project has an Android app registered with:

- Package name: `com.example.waller_app`.
- Both the upload key SHA-1/SHA-256 and the Play App Signing key SHA-1/SHA-256
  added under SHA certificate fingerprints.

Download the resulting `google-services.json` and place it at
`android/app/google-services.json`. This file is `.gitignore`d.

## Google OAuth (Android client)

The Google Cloud project backing the Firebase project needs an Android OAuth
client for `com.example.waller_app` with the release SHA-1 fingerprint. The
mobile app itself only speaks to the mobile exchange endpoint using the
Web-typed `GOOGLE_MOBILE_CLIENT_ID`, but the Android client is what allows
Google Sign-In to complete on device.

## Play App Signing

Play App Signing is required. When uploading the first AAB, Play Console
prompts to enroll. Enroll and keep the upload key as the local key.

## Build command

```
flutter build appbundle --release \
  --dart-define-from-file=config/store_release.json
```

`ENABLE_PUSH_SUBSCRIPTION_WRITES=true` must be present in the JSON.

## Output location

- `build/app/outputs/bundle/release/app-release.aab`

Upload the AAB to Play Console → Testing → Internal testing (first), promote
to closed / open / production once verified.

## Never in Git

- `android/key.properties`
- `android/upload-keystore.jks` (or any `*.jks` / `*.keystore` in the tree)
- `android/app/google-services.json`
- Any store-release JSON containing filled values

All are excluded by `.gitignore` today; keep it that way.
