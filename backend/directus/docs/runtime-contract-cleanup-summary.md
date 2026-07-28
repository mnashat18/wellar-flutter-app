# Runtime Contract Cleanup Summary

Batch 0B canonicalizes the Directus runtime contract after:

- schema export verification
- permissions export verification
- flows/operations export verification
- backend gap report
- Batch 0A commit-safe export sanitization

## Scope

This document summarizes the runtime contract cleanup performed during Batch 0B. It defines the canonical set of active collections, identifies backend/internal support collections, flags legacy and missing-but-referenced collections, and documents carry-forward blockers for subsequent batches.

## Files Reviewed

- `docs/directus_runtime_contract.md` — updated with canonical sections and decisions
- `backend/directus/exports/` — schema, permissions, and flows exports verified during Batch 0A/0B
- Backend gap report findings

## Contract Decisions

### Canonical Active Runtime Collections

The following collections constitute the active runtime contract used by the Flutter mobile app and shared web/mobile flows:

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

### Backend/Internal Support Collections

The following collections exist for backend/infrastructure/internal use and are **not** part of the mobile runtime contract:

- `push_subscriptions`
- `consent_logs`
- `reports_exports`
- `employee_baselines`
- `scan_media_files`
- `shift_templates`
- `workspace_applications`

### Legacy Collections

- **`requests`** is a legacy duplicate of `scan_requests`. Do not use `requests` in new code.

### Missing But Referenced Collections

The following collections are referenced in the codebase or backend but are not yet part of the active runtime contract:

- `subscriptions`
- `plans`
- `audit_logs`
- `business_upgrade_requests`
- `business_locations`
- `business_automation_rules`
- `business_invoices`

## Carry-Forward Blockers

The following issues must be addressed in subsequent batches before the runtime contract can be considered production-ready:

- `notifications` permissions missing
- `activity_events` permissions missing
- broad/unfiltered permissions need tenant review
- public `directus_files` / `directus_folders` read requires review
- hardcoded `X-Directus-Secret` requires manual rotation
- hardcoded flow URLs require env/config cleanup
- active flow still references legacy `requests`
- `subscriptions` referenced by flows but missing schema
- many flows use `$full` and require tenant-scope review
- most active flows lack reject/error paths

## Next Batch

**Batch 0C**: Directus permissions/RBAC and tenant isolation planning.
