# Phase 0A Sanitization Summary

Last updated: 2026-06-16

## Scope

Batch 0A protects Directus export artifacts before any schema, permissions,
flows, or Flutter behavior changes. No live Directus changes were made.

## Raw Local-Only Exports

The following current exports are local-only because they may contain secrets,
hardcoded URLs, or environment-specific operational metadata:

- `backend/directus/flows/directus-flows.json`
- `backend/directus/flows/directus-operations.json`
- `backend/directus/permissions/directus-roles.json`
- `backend/directus/permissions/directus-policies.json`
- `backend/directus/permissions/directus-permissions.json`

Older/stale variants in `backend/directus/flows/` and
`backend/directus/permissions/` are also local-only unless they are explicitly
regenerated as `*.commit-safe.json`.

## Commit-Safe Exports

The following files were regenerated as commit-safe audit artifacts:

- `backend/directus/flows/directus-flows.commit-safe.json`
- `backend/directus/flows/directus-operations.commit-safe.json`
- `backend/directus/permissions/directus-roles.commit-safe.json`
- `backend/directus/permissions/directus-policies.commit-safe.json`
- `backend/directus/permissions/directus-permissions.commit-safe.json`

## Redactions Applied

The commit-safe operations export redacts:

- `X-Directus-Secret` header values.
- Secret-like authorization/header values.
- Private or environment-specific service URLs, including push, report export,
  local invite, Directus asset, and AI processing URLs.

Structure, collection names, operation chains, field metadata, filters, and
template variables are preserved for audit.

## Manual Follow-Up Required

- Rotate the exposed `X-Directus-Secret` in Directus and the matching push
  service.
- Re-export flows after rotation.
- Regenerate commit-safe exports.
- Re-run the secret scan checklist.
- Decide later whether stale tracked exports should be removed in a dedicated
  cleanup batch.

## Out Of Scope

- No Flutter behavior changes.
- No Directus schema, role, permission, policy, flow, or operation changes.
- No live secret rotation.
- No migration, schema apply, build, or Flutter test run.

