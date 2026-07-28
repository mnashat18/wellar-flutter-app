# Legacy Collections Decision Log

This document records Batch 0B decisions about legacy, duplicate, or drifted Directus collections and fields.

## Primary Decision

- `requests` is treated as a legacy duplicate of `scan_requests`.
- `scan_requests` is the canonical request lifecycle collection.
- New backend, Flutter, and Directus flow work must not introduce new dependencies on `requests`.

## Evidence

- `requests` is referenced by existing legacy flows.
- Active `When Request Created0` still references legacy `requests`.
- `scan_requests` is part of the canonical active runtime contract.
- Flutter and flows have drifted request field names that need cleanup in later batches.

## Legacy / Drifted Names

- `requests`
- `requested_for`
- `requested_for_email`
- `note` / `notes` unless schema-approved
- `wellness_scan` fallback
- `readiness_state`
- `overall_state`
- `state`
- `readiness_label`

## Canonical Replacements

- `requests` -> `scan_requests`
- `requested_for` / `requested_for_email` -> `scan_requests.target_member`
- `wellness_scan` fallback -> `scan_requests.completed_scan`
- `readiness_state` / `overall_state` / `state` / `readiness_label` -> `scan_results.risk_level` and `scan_results.readiness_score`
- `note` / `notes` / `message` must not be written unless intentionally added to schema

## Batch Mapping

- **Batch 0D**: flows using legacy `requests` or stale fields
- **Batch 0E**: Flutter code using legacy aliases
- **Batch 0G**: tests/checkpoint to ensure legacy names are no longer used

## Decision Status

- `requests` is not deleted in Batch 0B.
- No live Directus changes are made in Batch 0B.
- This is documentation-only.
- Deletion or migration decisions require a later explicit migration plan.
