# Phase 0B Runtime Contract Summary

Batch 0B updates the Directus runtime contract and creates decision logs only. It does not change Flutter behavior or live Directus.

## Files Changed In Batch 0B

- `docs/directus_runtime_contract.md`
- `backend/directus/docs/runtime-contract-cleanup-summary.md`
- `backend/directus/docs/legacy-collections-decision-log.md`
- `backend/directus/docs/phase-0b-runtime-contract-summary.md`

## Contract Decisions

- 11 canonical active runtime collections were formalized.
- 7 backend/internal support collections were formalized.
- `requests` was marked as legacy duplicate of `scan_requests`.
- 7 missing-but-referenced collections were documented.
- Canonical field naming decisions were recorded.

## Canonical Active Runtime Collections

- `business_profiles`
- `business_profile_members`
- `departments`
- `request_invites`
- `scan_requests`
- `wellness_scans`
- `scan_media`
- `scan_results`
- `alerts`
- `notifications`
- `activity_events`

## Backend/Internal Support Collections

- `push_subscriptions`
- `consent_logs`
- `reports_exports`
- `employee_baselines`
- `scan_media_files`
- `shift_templates`
- `workspace_applications`

## Legacy And Missing Collections

- `requests` is legacy and must not be used in new code.
- Missing but referenced: `subscriptions`, `plans`, `audit_logs`, `business_upgrade_requests`, `business_locations`, `business_automation_rules`, `business_invoices`.

## Next Batches

- **Batch 0C**: permissions/RBAC and tenant isolation planning.
- **Batch 0D**: flows/secrets/hardcoded URLs.
- **Batch 0E**: Flutter/backend contract fixes.
- **Batch 0F**: security hardening.
- **Batch 0G**: test checkpoint.

## Reviewer Checklist

- Confirm `docs/directus_runtime_contract.md` changed.
- Confirm no Flutter files are staged.
- Confirm no live Directus changes were made.
- Confirm 0B is documentation-only.
- Confirm 0C starts from the permission blockers documented in the contract.
