# Account Deletion

## Configuration key

`ACCOUNT_DELETION_URL` in `lib/config/app_config.dart` is a compile-time
`String.fromEnvironment` value. It defaults to:

`https://app.conntinuity.com/delete-account`

The store-release JSON should set the same URL unless a release override is
required.

## In-app flow

1. Profile -> **Delete account**.
2. The app shows a confirmation dialog explaining that continuing will open
the secure account deletion page.
3. On confirm, the app validates that `ACCOUNT_DELETION_URL` is a well-formed
HTTPS URL.
4. If valid, the app opens the URL in an external browser via
`url_launcher` (`LaunchMode.externalApplication`).
5. The linked page submits a deletion request to
`POST /wellar/account-deletion-requests`.
6. If the URL is empty or not HTTPS, the app shows an "Account deletion not
configured" dialog directing the user to contact their administrator.

The client **does not** report success. It never claims that server-side
deletion occurred. All completion signalling lives in the deletion page.

## Server-side deletion status

The web page submits account deletion requests to the Directus extension at
`POST /wellar/account-deletion-requests`.

This is not a direct user-delete operation. Staff must verify the request,
review memberships, organizations, scans, reports, notifications,
subscriptions, audit data, and legal retention responsibilities, and then
perform any deletion work manually.

Account deletion is not complete in the sense of purging user data until:

- The public page and Directus extension are deployed.
- Staff complete the manual review and any approved deletion work.
- Retention windows and any residual telemetry are documented in the web
  privacy policy.

## Store requirements

- **Play Console** requires a public URL where users can request account
deletion. Supply the same URL that populates `ACCOUNT_DELETION_URL` in the
store-release JSON.
- **App Store Connect** requires that account deletion can be initiated from
inside the app. The in-app Delete account entry point satisfies that, and
the linked page must handle the request submission.

## Pre-submission checklist

- [ ] `ACCOUNT_DELETION_URL` in the store-release JSON is set to a live
      HTTPS URL.
- [ ] The URL renders a deletion request page on device.
- [ ] The deletion page submits to `POST /wellar/account-deletion-requests`.
- [ ] The same URL is entered in Play Console -> Data safety -> Account
      deletion.
- [ ] The App Store listing describes the Profile -> Delete account entry
      point.
