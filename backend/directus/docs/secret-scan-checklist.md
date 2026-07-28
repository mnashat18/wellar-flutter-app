# Directus Secret Scan Checklist

Last updated: 2026-06-16

Run this checklist before committing any Directus export or documentation update.

## Targeted Scan

From the repo root:

```powershell
rg -n -i "X-Directus-Secret|authorization|bearer|access_token|refresh_token|api[_-]?key|client[_-]?secret|private[_-]?key|-----BEGIN|postgres://|smtp|password|secret|trycloudflare|sendpushnotification|localhost:4200|ai-server/process|http://directus/assets" backend/directus
```

## Expected Safe Hits

These can be safe if they are placeholders or metadata:

- `.env.example` placeholder values.
- Documentation examples using placeholder token names.
- Field names such as `token`, `password`, or `tfa_secret`.
- Template variables such as `{{generate_invite_token.token}}`.
- Redaction placeholders such as `[REDACTED_SECRET_VALUE]`.

## Unsafe Hits

Do not commit files containing:

- Real admin tokens.
- Real webhook secrets.
- Real API keys.
- Real OAuth secrets.
- Real SMTP credentials.
- Real storage credentials.
- Real database credentials.
- Real access or refresh tokens.
- Private keys.
- Production-only internal URLs that should not be public.
- User/customer row data.

## Review Steps

1. Classify each hit as metadata, placeholder, template variable, URL, header, or
   actual secret.
2. If an actual secret is found, do not paste the value into chat or docs.
3. Redact the commit-safe copy.
4. Add the secret to the manual rotation checklist.
5. Confirm raw files remain ignored/local-only.

