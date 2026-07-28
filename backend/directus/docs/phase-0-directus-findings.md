# Phase 0 Directus Findings

## Scope

This document summarizes read-only Phase 0 evidence collected from completed Directus exports.

Phase 0 evidence is useful for audit, review, and migration planning. It is not proof of Enterprise SaaS readiness, production hardening, tenant isolation, compliance, or secure runtime behavior.

No live Directus changes are part of this document. Do not use this step to change schema, collections, fields, roles, permissions, policies, flows, operations, migrations, or Flutter behavior.

## Evidence Files

- `backend/directus/schema/directus-schema.snapshot.json`
- `backend/directus/schema/directus-schema.snapshot.yaml`
- `backend/directus/permissions/roles.json`
- `backend/directus/permissions/permissions.json`
- `backend/directus/permissions/policies.json`
- `backend/directus/permissions/access-policies.json`
- `backend/directus/flows/flows.json`
- `backend/directus/flows/operations.json`
- `backend/directus/docs/live-instance-notes.md`
- `backend/directus/docs/export-checklist.md`
- `backend/directus/docs/directus-reproducibility-dod.md`

## Schema Export Summary

- Directus version: `11.14.1`
- Database vendor: `postgres`
- Collections exported: `19`
- Fields exported: `249`
- Relations exported: `59`
- No obvious real secrets were found in the schema snapshot during Phase 0 review.

The schema snapshot proves that a structural export exists for review. It does not prove that the schema is complete for a reproducible production deployment, that constraints enforce all business rules, or that field-level access is safe.

## Permissions Export Summary

- Roles exported: `9`
- Permissions exported: `316`
- Policies exported: `10`
- Access-policy mappings exported: `10` policy records / `14` role-policy links
- No obvious real secret values were found in the permissions exports during Phase 0 review.

Important permission evidence:

- `AI Server Access` policy appears broad and needs dedicated review.
- `$t:public_label` policy appears broad and needs dedicated review.
- `admin_access: true` exists on `Administrator`, `Admin Policy`, and `$t:public_label`.
- `directus_users` permissions expose sensitive field names, including `password` and `tfa_secret`. Secret values were not found, but field exposure should be audited.
- `Owner Policy` can update `directus_users.active_business_profile` and `directus_users.active_department` without visible filter or validation in the exported evidence.

## Flows Export Summary

- Flows exported: `21`
- Operations exported: `94`
- All `21` flows use `accountability: all`.

Operation types exported:

- `exec`: `10`
- `condition`: `9`
- `mail`: `2`
- `item-read`: `26`
- `item-update`: `19`
- `item-create`: `22`
- `transform`: `2`
- `request`: `3`
- `item-delete`: `1`

Request operations identified:

- `Export Reports` calls a temporary-looking Cloudflare tunnel host.
- `Send Push When Scan Request Created` calls a Google Cloud Run endpoint and previously included an `X-Directus-Secret` header value before local redaction.
- `WallerAi` calls `ai-server`.

Sensitive collections modified or touched by flows include:

- `directus_users`
- `request_invites`
- `business_profile_members`
- `business_profiles`
- `scan_requests`
- `wellness_scans`
- `scan_results`
- `scan_media`
- `reports_exports`
- `alerts`
- `notifications`
- `push_subscriptions`

Additional flow evidence:

- `WallerAi` creates `scan_results` and should be reviewed together with the broad `AI Server Access` policy.
- Some flows reference `$full` payloads and should be reviewed for tenant isolation and accidental data overexposure.

## Sanitization Performed

`backend/directus/flows/operations.json` was sanitized locally after export.

- One `X-Directus-Secret` header value was replaced with `REDACTED_DIRECTUS_SECRET`.
- The `X-Directus-Secret` header name was preserved.
- The operation, URL, request body, flow ID, operation ID, and metadata were preserved.
- Post-sanitization validation confirmed `operations.json` remained valid JSON.
- Post-sanitization validation confirmed the redacted header still exists and no non-redacted `X-Directus-Secret` value remains.
- Post-sanitization credential scanning found no bearer tokens, JWTs, private keys, access tokens, refresh tokens, SMTP credentials, OAuth secrets, or storage credentials in `operations.json`.

Important: the exported `operations.json` is sanitized local evidence. It should not be used to apply back to Directus without restoring or reviewing required secrets through secure deployment configuration, such as environment variables, secret storage, or another approved secret-management path.

## Key Risks Found

- Broad policy surface: `AI Server Access` and `$t:public_label` require dedicated review before they can be considered safe.
- Admin capability exposure: `admin_access: true` appears on `Administrator`, `Admin Policy`, and `$t:public_label`.
- Sensitive Directus user fields are exposed by permission definitions. The audit found field names, not secret values, but the exposure still requires access review.
- User context mutation risk: `Owner Policy` can update active workspace fields on `directus_users` without visible exported filter or validation.
- Flow accountability risk: all flows use `accountability: all`, which needs review against least-privilege and tenant-isolation requirements.
- External request risk: exported request operations call external services, including a temporary-looking Cloudflare tunnel host, a Google Cloud Run endpoint, and `ai-server`.
- AI result integrity risk: `WallerAi` creates `scan_results`; this should be reviewed together with `AI Server Access`, service authentication, request validation, and audit logging.
- Sensitive collection mutation risk: flows modify operational, identity, invitation, reporting, notification, media, and scan-result collections.
- `$full` payload risk: flows using `$full` should be reviewed for accidental cross-tenant reads, writes, and data exposure.
- Secret-management risk: one shared secret was found in an operation header and redacted locally. Runtime secret rotation and secure configuration review remain separate follow-up work.

## What This Proves

- Phase 0 has local exported evidence for schema, permissions, policies, flows, and operations.
- The schema export is parseable and includes the expected high-level counts.
- The permissions and policy exports are present and reviewed for obvious embedded secret values.
- The flow and operation exports are present and reviewed for operation counts, request operations, sensitive collection writes, and obvious embedded secrets.
- The local operation export has been sanitized for the known `X-Directus-Secret` value while preserving the exported structure.
- The exported evidence is sufficient to begin focused security, tenant-isolation, reproducibility, and deployment-readiness review.

## What This Does Not Prove

- It does not prove Enterprise SaaS readiness.
- It does not prove tenant isolation across all collections, policies, flows, custom code, and external services.
- It does not prove least-privilege access for Directus roles, policies, or flow accountability.
- It does not prove that external services validate requests securely.
- It does not prove runtime environment variables, storage credentials, mail settings, OAuth settings, CORS settings, rate limits, or deployed extensions are secure.
- It does not prove database backups, restore procedures, observability, incident response, or compliance controls are production-ready.
- It does not prove that the sanitized `operations.json` can be safely imported or applied to any Directus instance.

## Required Follow-Up Work

- Review `AI Server Access` policy scope and the `WallerAi` flow together.
- Review `$t:public_label` and any role or policy with `admin_access: true`.
- Audit `directus_users` permissions, especially sensitive fields such as `password`, `tfa_secret`, active workspace fields, role fields, and identity fields.
- Review `Owner Policy` updates to `directus_users.active_business_profile` and `directus_users.active_department` for tenant boundaries and validation.
- Review all flows using `accountability: all` and decide whether narrower accountability is required.
- Review all `$full` references in flows for overexposure and cross-tenant data access.
- Replace temporary-looking external endpoints with stable, reviewed deployment endpoints where appropriate.
- Move runtime shared secrets out of exported operation configuration and into approved secure deployment configuration.
- Rotate or replace any runtime secret that was exposed in a local export, if it is confirmed to be a real active secret.
- Document required environment variables, storage configuration, mail configuration, OAuth configuration, CORS, rate limits, backups, and extensions with placeholders only.
- Build a separate reproducibility and deployment plan before applying any schema or Directus configuration to another environment.

## Commit Safety Notes

- Commit only sanitized export files and documentation.
- Do not commit production `.env` files, admin tokens, OAuth secrets, SMTP secrets, storage credentials, private keys, database dumps, uploaded files, customer data, user data, auth data, billing data, or health data.
- Do not print or reintroduce the original `X-Directus-Secret` value.
- Review `backend/directus/flows/operations.json` before commit and confirm the only `X-Directus-Secret` value is `REDACTED_DIRECTUS_SECRET`.
- Treat sanitized exports as audit evidence, not as direct production apply inputs.
- Do not run `directus schema apply`, migrations, or live Directus modifications as part of Phase 0 documentation work.
