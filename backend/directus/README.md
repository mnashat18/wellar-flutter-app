# Directus Backend Setup

This folder stores sanitized Directus backend artifacts for the existing live Easypanel deployment.

Live Directus URL:

```text
https://dash.conntinuity.com/
```

Phase 0 scope is documentation and export planning only. Do not modify Flutter behavior, do not change the live Directus instance, and do not run schema apply or migrations during this phase.

## Folder Layout

```text
backend/directus/
  schema/        Sanitized Directus schema snapshots.
  permissions/   Sanitized roles, permissions, and policies exports.
  flows/         Sanitized flows and operations exports.
  env/           Placeholder environment templates only.
  docs/          Export checklists, live instance notes, reproducibility criteria.
  seeds/         Sanitized reference seed data only.
  extensions/    Extension deployment and configuration notes.
```

## Artifacts To Export

- Schema snapshot.
- Collections, fields, and relations.
- Roles.
- Permissions and policies.
- Flows.
- Operations.
- Presets/bookmarks if they are needed to reproduce operational setup.
- Dashboards/panels if they are needed to reproduce operational setup.
- Exportable settings that affect auth, files, security, CORS, storage, mail, OAuth, and rate limiting.
- Required environment variables, documented with placeholders only.
- Seed/reference data such as plans, default roles, default departments, and default statuses, if needed.
- Extension deployment/configuration details.

## Manual Schema Export Commands

Run these manually only after confirming a backup exists.

Inside the Easypanel Directus container:

```bash
directus schema snapshot ./directus-schema.snapshot.yaml
directus schema snapshot ./directus-schema.snapshot.json
```

If `directus` is not globally available in the container:

```bash
npx directus schema snapshot ./directus-schema.snapshot.yaml
npx directus schema snapshot ./directus-schema.snapshot.json
```

From a local terminal using the live API and an admin token:

```bash
curl -H "Authorization: Bearer DIRECTUS_ADMIN_TOKEN" \
  "https://dash.conntinuity.com/schema/snapshot" \
  -o directus-schema.snapshot.json
```

PowerShell equivalent:

```powershell
$headers = @{ Authorization = "Bearer DIRECTUS_ADMIN_TOKEN" }
Invoke-RestMethod -Uri "https://dash.conntinuity.com/schema/snapshot" -Headers $headers -OutFile "directus-schema.snapshot.json"
```

Do not commit the token, shell history containing the token, or any raw export that includes secrets or private data.

## Safe Export Order

1. Back up the database, uploaded files/storage, production environment variables, and deployed extensions.
2. Export schema snapshot.
3. Export roles, permissions, and policies.
4. Export flows and operations.
5. Export presets, bookmarks, dashboards, and panels only if they matter to reproducibility.
6. Export sanitized seed/reference data only.
7. Review every export for secrets and private data before moving it into git-tracked files.

## Never Commit

- Production `.env` files.
- Database dumps with real user/customer data.
- Directus admin tokens.
- OAuth secrets.
- SMTP secrets.
- Firebase private keys or sensitive service-account files.
- Storage credentials.
- Private keys.
- Uploaded files.
- Raw exports containing customer, user, auth, billing, or health-related data.

## Safe To Commit After Review

- Schema snapshots without secrets.
- Roles, permissions, and policies exports if they do not expose secrets.
- Flows and operations after checking for embedded secrets.
- `.env.example` with placeholders only.
- Directus setup documentation.
- Extension deployment notes.
- Seed/reference data without private customer or user data.

