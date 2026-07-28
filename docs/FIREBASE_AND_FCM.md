# Firebase and FCM

## Overview

Firebase Cloud Messaging (FCM) is the transport for best-effort push. It is
**not** the source of truth for user-visible notifications. Every business
event that a user must see is written as a durable in-app notification in
Directus; FCM is layered on top so the notification arrives promptly.

```
business event
   → durable in-app notification (Directus, authoritative)
   → best-effort FCM push (transient, non-authoritative)
```

If FCM fails, the user still sees the notification the next time the app
loads its inbox from Directus.

## Firebase apps required

- **Android app**: package `com.example.waller_app`. Config lands at
  `android/app/google-services.json`.
- **iOS app**: bundle ID `com.example.wallerApp`. Config lands at
  `ios/Runner/GoogleService-Info.plist`.

Both files are excluded from Git.

## FCM token lifecycle (source)

Wired in `lib/services/push_notification_service.dart`:

- `FirebaseMessaging.getToken()` on initialize.
- `FirebaseMessaging.onTokenRefresh` listener updates the stored token.
- `FirebaseMessaging.onMessage` handles foreground messages.
- `FirebaseMessaging.onMessageOpenedApp` handles tap-through when the app is
  in the background.
- `FirebaseMessaging.getInitialMessage()` handles the terminated-app cold
  start with a pending notification.
- The background handler `_firebaseMessagingBackgroundHandler` in
  `lib/main.dart` initialises Firebase and is registered via
  `FirebaseMessaging.onBackgroundMessage`.

## Notification permission and channel

- Notification permission is requested at first launch as part of the push
  service initialization.
- Android notification channel `waller_alerts` is declared as the default
  channel in `AndroidManifest.xml` via
  `com.google.firebase.messaging.default_notification_channel_id`.

## Push subscription writes

Push subscriptions describe *this installation on this device for this
member*. The mobile app writes them to Directus so the server can address a
specific device.

- `AppConfig.enablePushSubscriptionWrites` gates writes at compile time.
- Debug default: `false` (developer machines do not pollute installation
  rows).
- Store-release JSON: `ENABLE_PUSH_SUBSCRIPTION_WRITES = true`. This is
  required.

The compile-time flag is intentionally *not* flipped in source — only the
store-release JSON changes its value.

## Logout / installation lifecycle

- On logout the app should mark the current installation row inactive
  rather than delete it. This is handled server-side; the mobile client is
  responsible for signalling logout via the authenticated request path.
- Reusing the same device across accounts is expected to produce distinct
  installation rows keyed by member × device. Stale rows are pruned on the
  server, not by the mobile client. Backend schema is out of scope for the
  handoff and was not modified.

## Notification tap routing

`lib/main.dart` attaches a push open handler that routes on payloads whose
`event`, `screen`, `route`, `link_type`, or `type` indicate a scan request.
Missing `scan_request_id` falls back to the employee requests screen.

## Release configuration

- Android needs `google-services.json`.
- iOS needs `GoogleService-Info.plist`.
- iOS needs the APNs `.p8` authentication key uploaded to the Firebase
  Console (Project Settings → Cloud Messaging → Apple app configuration).
- iOS needs Push Notifications capability + Remote notifications background
  mode enabled in Xcode.
- Store-release JSON must set `ENABLE_PUSH_SUBSCRIPTION_WRITES = true`.

## Tests to run on device

- Foreground: with the app open, trigger a push and confirm the in-app
  handler fires and the durable notification appears in the inbox.
- Background: with the app minimized, trigger a push and confirm the system
  banner arrives. Tapping it should route to the correct screen.
- Terminated: fully close the app, trigger a push, tap the banner, and
  confirm cold-start routing lands on the correct screen.

The durable notification must independently show up regardless of whether
FCM delivered the push.
