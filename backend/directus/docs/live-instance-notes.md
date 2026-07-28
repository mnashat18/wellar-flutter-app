# Live Directus Instance Notes

## Instance

- Provider: Easypanel.
- Directus URL: `https://dash.conntinuity.com/`
- Purpose: Existing live backend for the Waller/Wellar app.

## Phase 0 Rules

- Read-only first.
- Do not modify the live instance.
- Do not delete collections.
- Do not rename collections or fields.
- Do not change roles, permissions, or policies.
- Do not edit flows or operations.
- Do not rotate secrets unless separately planned.
- Do not run `directus schema apply`.
- Do not run database migrations blindly.
- Do not import snapshots into production.
- Do not export and commit real user/customer data.

## Export Commands

Inside the Easypanel Directus container:

```bash
directus schema snapshot ./directus-schema.snapshot.yaml
directus schema snapshot ./directus-schema.snapshot.json
```

If the Directus binary is not globally available:

```bash
npx directus schema snapshot ./directus-schema.snapshot.yaml
npx directus schema snapshot ./directus-schema.snapshot.json
```

From a local terminal with an admin token:

```bash
curl -H "Authorization: Bearer DIRECTUS_ADMIN_TOKEN" \
  "https://dash.conntinuity.com/schema/snapshot" \
  -o directus-schema.snapshot.json
```

PowerShell:

```powershell
$headers = @{ Authorization = "Bearer DIRECTUS_ADMIN_TOKEN" }
Invoke-RestMethod -Uri "https://dash.conntinuity.com/schema/snapshot" -Headers $headers -OutFile "directus-schema.snapshot.json"
```

## Manual Notes To Fill Later

- Directus version:
- Database engine/version:
- Easypanel service name:
- Container image/tag:
- Storage adapter:
- Mail provider:
- Auth providers:
- CORS origins:
- Public URL setting:
- Extension deployment path:
- Backup location:
- Export date:
- Export operator:

