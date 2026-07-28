# Privacy Data Inventory (Mobile)

This is a factual inventory of the categories of data Wellar Mobile touches
on device or transmits to Wellar-controlled servers. It is not a legal
document and does not constitute a privacy policy. Play Console and App
Store Connect data safety questionnaires should be authored by whoever owns
the store listings, using this inventory as source.

## Identity and account

- User ID (Directus user identifier).
- Full name (given/family, as provided by the user).
- Email address (used for authentication and Directus identity).
- Google account identifier when a member signs in with Google via the
  mobile exchange endpoint.

## Organization membership

- Organization / business profile ID(s) the user is a member of.
- Role within each organization (owner / HR / manager / employee).
- Department assignment within the organization.

## Scan capture

- Camera video of the person being scanned (captured to app-scoped storage
  during scan, uploaded to Directus once the scan is finalized).
- Microphone audio recorded during the scan (five-second clip auto-stopped
  and continued through the scan flow).
- Video thumbnail bytes derived on device.
- Readiness / scan results returned by the AI processing server and stored
  as part of the durable scan record.

## Device and installation

- Device ID / installation identifier (used to link an installation to a
  member).
- FCM registration token (used to address this device for push).
- Push subscription state (active / inactive), written only when
  `ENABLE_PUSH_SUBSCRIPTION_WRITES` is true.

## Notifications

- Durable in-app notifications delivered from Directus (business events,
  scan requests, etc.).
- Best-effort FCM push messages layered over durable notifications.

## Reports and exports

- Report metrics and exports downloaded from the backend to app-scoped
  storage for the user's own review (never re-uploaded from the client).

## Diagnostics

- Local debug logs (`debugPrint`) during development. No third-party
  analytics or crash reporting SDK is wired into the mobile client at this
  time.
- Firebase Analytics is explicitly disabled in the current
  `GoogleService-Info.plist` (`IS_ANALYTICS_ENABLED = false`). If Firebase
  Analytics is enabled during release, the store data safety declarations
  must be updated accordingly.

## What Mobile does NOT collect

- Location data (no location plugin is wired).
- Contacts, calendar, or SMS.
- Payment or financial information.
- Advertising identifiers.

If any of the above are added later, this document and the store data safety
declarations must be updated in the same change.
