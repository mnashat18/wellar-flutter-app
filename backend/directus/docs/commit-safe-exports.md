# Directus Commit-Safe Export Policy

Last updated: 2026-06-16

## Purpose

Directus exports can contain operational secrets, private service URLs, role IDs,
field names, webhook headers, and environment-specific metadata. Raw exports are
local audit artifacts only. Commit only sanitized `*.commit-safe.json` files and
documentation.

## Commit-Safe Files

The following files are intended to be safe to commit after validation:

- `backend/directus/flows/directus-flows.commit-safe.json`
- `backend/directus/flows/directus-operations.commit-safe.json`
- `backend/directus/permissions/directus-roles.commit-safe.json`
- `backend/directus/permissions/directus-policies.commit-safe.json`
- `backend/directus/permissions/directus-permissions.commit-safe.json`
- `backend/directus/schema/directus-schema.snapshot.json`
- `backend/directus/schema/directus-schema.snapshot.yaml`
- `backend/directus/docs/*.md`
- `backend/directus/env/.env.example`

Schema snapshots may be committed only after checking that they contain schema
metadata only and no row/customer data.

## Local-Only Files

Do not commit these files or patterns:

- Raw flow exports: `backend/directus/flows/directus-flows.json`
- Raw operation exports: `backend/directus/flows/directus-operations.json`
- Raw permission exports: `backend/directus/permissions/directus-*.json`
- Stale aliases: `flows.json`, `operations.json`, `roles.json`,
  `permissions.json`, `policies.json`, `access-policies.json`
- `*.raw.json`, `*.safe.json`, `*.post-*.json`, `*backup*.json`
- `.env`, production env files, admin tokens, private keys, service accounts
- `*.dump`, `*.sql`, `*.backup`, `*.bak`
- Directus uploads, storage, database dumps, or runtime backup folders

## Sanitization Rules

Commit-safe exports must preserve structure while redacting sensitive values:

- Replace `X-Directus-Secret` values with `[REDACTED_SECRET_VALUE]`.
- Replace authorization/header secret values with `[REDACTED_SECRET_VALUE]`.
- Replace private infrastructure URLs with descriptive placeholders.
- Preserve flow names, operation chains, collections, fields, filters, and
  non-secret template variables.
- Do not include user/customer row data.

## Required Checks

Before committing commit-safe exports:

1. Validate every `*.commit-safe.json` with `ConvertFrom-Json`.
2. Run the targeted secret scan from `secret-scan-checklist.md`.
3. Confirm `git status --short` does not show raw export files staged.
4. Confirm any real secret found in a raw export has a rotation issue/checklist.

