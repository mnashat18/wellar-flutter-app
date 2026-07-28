# Google Mobile Exchange Extension

Existing repository source:

```text
backend/directus-extension-endpoint-google-mobile-exchange/
```

This document records deployment notes for the existing Directus endpoint extension. It does not implement Google login and does not change the live Directus instance.

## Endpoint

Expected route:

```text
POST https://dash.conntinuity.com/google-mobile-exchange
```

The extension verifies a Google ID token server-side and returns Directus-compatible session tokens.

## Required Environment Variables

Use placeholders in documentation and committed templates only.

```text
GOOGLE_MOBILE_ALLOWED_CLIENT_IDS=replace-with-google-oauth-client-id
GOOGLE_MOBILE_ALLOW_USER_CREATE=false
GOOGLE_MOBILE_DEFAULT_ROLE_ID=replace-with-directus-role-id-or-empty
```

## Build Commands

From the extension source folder:

```bash
npm install
npm run build
```

## Deployment Notes

Recommended Directus endpoint deployment path:

```text
extensions/endpoints/google-mobile-exchange/index.js
```

Expected built file:

```text
backend/directus-extension-endpoint-google-mobile-exchange/dist/index.js
```

After copying the built file into the Directus extensions folder, Directus must be restarted for the endpoint to load.

## Verification

After deployment, verify the route exists without committing any tokens:

```bash
curl -i -X POST "https://dash.conntinuity.com/google-mobile-exchange" \
  -H "Content-Type: application/json" \
  -d '{"idToken":"placeholder","platform":"android"}'
```

Expected result for a placeholder token is an authentication error such as `GOOGLE_TOKEN_INVALID`, not a missing route.

## Do Not Commit

- Google OAuth client secrets.
- Real Google ID tokens.
- Directus access tokens.
- Directus refresh tokens.
- Real role IDs if they are considered sensitive in the deployment process.
- Production `.env` files.

