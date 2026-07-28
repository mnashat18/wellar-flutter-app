# Directus Export Checklist

Use this checklist for the existing live Directus instance at:

```text
https://dash.conntinuity.com/
```

## Before Export

- [ ] Confirm no Flutter changes are part of this step.
- [ ] Confirm no live Directus schema changes are planned.
- [ ] Create or verify a current database backup.
- [ ] Create or verify a backup of uploaded files/storage.
- [ ] Save production environment variables outside git.
- [ ] Save deployed extension files/build artifacts outside git.
- [ ] Confirm who has the Directus admin token and where it is stored.
- [ ] Confirm shell history, terminal recording, and logs will not expose tokens.

## Export

- [ ] Export schema snapshot.
- [ ] Export collections, fields, and relations if not already covered by the schema snapshot.
- [ ] Export roles.
- [ ] Export permissions.
- [ ] Export policies.
- [ ] Export flows.
- [ ] Export operations.
- [ ] Export presets/bookmarks if operationally required.
- [ ] Export dashboards/panels if operationally required.
- [ ] Document auth, files, security, CORS, storage, mail, OAuth, and rate-limit settings.
- [ ] Document required environment variables with placeholders only.
- [ ] Export sanitized seed/reference data only if needed.
- [ ] Document extension deployment and configuration.

## Verify

- [ ] Snapshot opens as valid JSON or YAML.
- [ ] Core app collections are present.
- [ ] Expected fields and relations are present.
- [ ] Role names and role IDs are recorded if needed for permissions or seed data.
- [ ] Permissions and policies match the live admin UI.
- [ ] Flows do not contain embedded secrets.
- [ ] Operations do not contain embedded secrets.
- [ ] No admin tokens are present.
- [ ] No OAuth client secrets are present.
- [ ] No SMTP secrets are present.
- [ ] No storage credentials are present.
- [ ] No Firebase private keys or sensitive service-account JSON is present.
- [ ] No real user/customer rows are present.
- [ ] No uploaded files are present.

## Store In Repo

- [ ] Put sanitized schema exports in `backend/directus/schema/`.
- [ ] Put sanitized role/permission/policy exports in `backend/directus/permissions/`.
- [ ] Put sanitized flow/operation exports in `backend/directus/flows/`.
- [ ] Put placeholder env docs in `backend/directus/env/`.
- [ ] Put sanitized seed data in `backend/directus/seeds/`.
- [ ] Put extension notes in `backend/directus/extensions/`.

## Stop Conditions

Stop and do not commit if any export contains:

- Real customer data.
- Real user data.
- Tokens or secrets.
- Passwords or password hashes.
- Private files or uploads.
- Production database dumps.
- Private keys.

