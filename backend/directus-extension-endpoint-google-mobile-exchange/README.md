# Google Mobile Exchange Directus Endpoint

This extension exposes:

- `POST /google-mobile-exchange`

It verifies a Google `idToken` server-side and returns Directus-compatible session tokens.

## Request

```json
{
  "idToken": "google-id-token",
  "platform": "android"
}
```

## Success response

```json
{
  "access_token": "...",
  "refresh_token": "...",
  "expires": 900000,
  "user": {
    "id": "...",
    "email": "...",
    "first_name": "...",
    "last_name": "..."
  }
}
```

## Error responses

- `400 { "error": "GOOGLE_TOKEN_MISSING" }`
- `401 { "error": "GOOGLE_TOKEN_INVALID" }`
- `400 { "error": "GOOGLE_EMAIL_MISSING" }`
- `403 { "error": "GOOGLE_EMAIL_NOT_VERIFIED" }`
- `403 { "error": "GOOGLE_ACCOUNT_NOT_ALLOWED" }`
- `500 { "error": "DIRECTUS_SESSION_CREATE_FAILED" }`

## Environment variables

- `GOOGLE_MOBILE_ALLOWED_CLIENT_IDS`:
  Comma-separated Google OAuth client IDs allowed for token audience validation.
- `GOOGLE_MOBILE_ALLOW_USER_CREATE`:
  `true/false` toggle for creating missing Directus users.
- `GOOGLE_MOBILE_DEFAULT_ROLE_ID`:
  Optional Directus role ID assigned when creating new users.

## Build

```bash
npm install
npm run build
```

## Deploy to Directus

Use one of the following patterns on the Directus server.

### Pattern A: Endpoint folder (recommended for route control)

1. Build this package (`dist/index.js`).
2. Copy output to Directus:
   - `extensions/endpoints/google-mobile-exchange/index.js`
3. Restart Directus.
4. Verify:
   - `POST https://dash.conntinuity.com/google-mobile-exchange`

### Pattern B: Package extension loader

1. Install this package in the Directus environment.
2. Ensure the extension loader discovers it.
3. Restart Directus.
4. Verify route is exactly `/google-mobile-exchange`.

## Notes

- The endpoint does not trust client email; it verifies with Google.
- It does not create workspace memberships.
- It returns real Directus tokens only when session creation is supported by the current Directus runtime.
