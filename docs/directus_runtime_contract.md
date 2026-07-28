# Wellar Mobile/Web Directus Runtime Contract

Last updated: 2026-05-29

This document is the source of truth for the active runtime data contract used by Flutter mobile (and shared web/mobile flow touchpoints).

## Contract rules

- Do not read/write Directus directly from screens.
- Screens must consume service/repository APIs only.
- 401 => clear session and route to login.
- 403 => friendly unavailable/permission state (never raw Directus errors in UI).
- Empty data => clean empty state.
- Missing field/schema mismatch => safe fallback + debug log.
- Network failure => retry state.

## Active collections and usage

### `business_profiles`
- Read fields:
  - `id`
  - `company_name`
  - `is_active`
  - `plan_code`
  - `billing_status`
- Used by:
  - Owner (company scope)
  - Workspace resolution context
- Services:
  - `organization_service.dart`
  - `owner_ops_service.dart`

### `business_profile_members`
- Read fields:
  - `id`
  - `user`, `user.id`, `user.email`, `user.first_name`, `user.last_name`
  - `business_profile`, `business_profile.id`, `business_profile.company_name`, `business_profile.is_active`, `business_profile.plan_code`, `business_profile.billing_status`
  - `department`, `department.id`, `department.name`
  - `member_role`
  - `status`
  - `date_created`
- Write/update fields (invite/join flows):
  - `status`
  - `member_role`
  - `department`
- Used by:
  - Employee (self workspace context)
  - Manager (team scope)
  - HR (workspace people scope)
  - Owner (company scope)
- Services:
  - `organization_service.dart`
  - `manager_ops_service.dart`
  - `hr_ops_service.dart`
  - `owner_ops_service.dart`

### `departments`
- Read fields:
  - `id`
  - `name`
  - `business_profile` (as available)
- Used by:
  - Owner/HR/Manager workforce + summary flows
- Services:
  - `owner_ops_service.dart`
  - `organization_service.dart`

### `request_invites`
- Read/write fields:
  - `id`
  - `status`
  - `business_profile`
  - invite metadata per current invite flow
- Used by:
  - Owner/HR invite flows
- Services:
  - `invite_service.dart`
  - `owner_ops_service.dart`

### `scan_requests`
- Read fields (canonical):
  - `id`
  - `business_profile`
  - `department`
  - `requested_by_user`
  - `target_member`
  - `status`
  - `cancelled`
  - `requested_at`
  - `due_at`
  - `completed_scan`
  - `completed_at`
  - `request_type`
- Write/update fields:
  - Create:
    - `business_profile`
    - `target_member` (must be `business_profile_members.id`)
    - `requested_by_user`
    - `department` (if available)
    - `status`
    - `cancelled`
    - `requested_at`
    - `due_at`
    - `request_type`
  - Update after scan (if allowed):
    - `completed_scan`
    - `completed_at`
    - `status`
- Used by:
  - Employee (self assigned requests via `target_member`)
  - Manager (team/department scope)
  - HR (workspace scope)
  - Owner (company scope)
- Services:
  - `request_service.dart`
  - `invite_service.dart`
  - `hr_ops_service.dart` (compliance overdue counts)
  - `owner_ops_service.dart` (pending request summary)

### `wellness_scans`
- Read fields:
  - `id`
  - `user`
  - `business_profile` (where available)
  - `status`
  - `started_at`
  - `completed_at`
  - `date_created`
- Write/update fields:
  - create scan session payload (schema-safe keys only)
  - patch completion/status when scan capture/upload completes
- Used by:
  - Employee scan flow + history
  - Manager/HR/Owner summaries
- Services:
  - `scan_service.dart`
  - `manager_ops_service.dart`
  - `hr_ops_service.dart`
  - `owner_ops_service.dart`

### `scan_media`
- Write/read fields (schema-safe):
  - `scan_id`/relation to scan
  - media file references
  - optional metadata (`duration_seconds` etc. if available)
- Used by:
  - Employee scan flow upload
- Services:
  - `scan_service.dart`

### `scan_results`
- Read fields (defensive by availability):
  - `id`
  - `scan_id`
  - `date_created`
  - readiness status field from allowed schema (`overall_state`/`readiness_state` as available)
  - `confidence`
  - `camera_confidence`
  - `voice_confidence`
  - `task_performance_score`
  - `confidence_drift`
  - summaries/actions if readable
- Write:
  - None from mobile for AI output generation.
- Used by:
  - Employee history/result details (pending-safe)
  - Manager/HR/Owner summaries
- Services:
  - `scan_service.dart`
  - `manager_ops_service.dart`
  - `hr_ops_service.dart`
  - `owner_ops_service.dart`

### `alerts`
- Read fields:
  - `id`
  - `title`
  - `body`
  - `type`
  - `status`
  - `severity`
  - `user`
  - `business_profile`
  - `department`
  - `scan_request`
  - `scan_id`
  - `date_created`
- Used by:
  - Employee/Manager/HR/Owner alerts tabs (role scoped by backend permissions)
- Services:
  - `notification_service.dart`
  - `manager_ops_service.dart`
  - `hr_ops_service.dart`
  - `owner_ops_service.dart`

### `notifications`
- Read fields:
  - `id`
  - `user`
  - `title`
  - `body`
  - `type`
  - `status`
  - `link_type`
  - `link_id`
  - `meta`
  - `date_created`
- Update fields:
  - `status` for mark-read if allowed
- Used by:
  - Employee/Manager/HR/Owner notification/alerts experiences
- Services:
  - `notification_service.dart`

### `activity_events`
- Read fields:
  - event feed fields used by activity screens/services
- Used by:
  - Activity/recent events surfaces
- Services:
  - `activity_service.dart`

## Role scope contract

- Employee:
  - Self only (`target_member` assignment, own scans/results/notifications).
- Manager:
  - Department/team scope only.
- HR:
  - Workspace people/compliance scope.
- Owner:
  - Company-wide workspace scope.

## Runtime state behavior contract (all roles)

- Empty:
  - Show clean empty state, never treated as error.
- 401:
  - Session reset + login route.
- 403:
  - Friendly permission message, no crash, no raw Directus response in UI.
- Missing/forbidden fields:
  - Fallback to pending/unavailable state; log in debug only.
- Network failure:
  - Friendly retry state.

## Legacy services in repository (must stay inactive in active runtime path)

Present in codebase but not part of active mobile runtime contract:
- `audit_log_service.dart` (`audit_logs`)
- `subscription_service.dart` (`subscriptions`, `plans`)
- `report_service.dart` (`reports_exports`)
- `business_center_service.dart` (`business_upgrade_requests`, `business_locations`, `business_automation_rules`, `business_invoices`)

These may remain for legacy/admin contexts but must not be reintroduced into active mobile role runtime flows.

---

## Canonical Active Runtime Collections

The following collections are the active runtime contract used by the Flutter mobile app and shared web/mobile flows:

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

The following collections exist for backend/infrastructure/internal use and are not part of the mobile runtime contract:

- `push_subscriptions`
- `consent_logs`
- `reports_exports`
- `employee_baselines`
- `scan_media_files`
- `shift_templates`
- `workspace_applications`

## Legacy / Duplicate Collections

- `requests` is a legacy duplicate of `scan_requests`.
- Do not use `requests` in new code.

## Missing But Referenced Collections

The following collections are referenced in the codebase or backend but are not yet part of the active runtime contract:

- `subscriptions`
- `plans`
- `audit_logs`
- `business_upgrade_requests`
- `business_locations`
- `business_automation_rules`
- `business_invoices`

## Canonical Field Naming Decisions

- `scan_requests.target_member` is canonical over `requested_for` / `requested_for_email`.
- `scan_requests.completed_scan` is canonical over `wellness_scan` fallback.
- `scan_results.risk_level` and `scan_results.readiness_score` are canonical over `readiness_state` / `overall_state` / `state` / `readiness_label`.
- `note` / `message` fields must not be written unless intentionally added to schema.

## Do Not Use In New Code

The following fields and patterns must not be used in new code:

- `requests`
- `requested_for`
- `requested_for_email`
- `note` / `notes` unless schema-approved
- `wellness_scan` fallback
- `readiness_state`
- `overall_state`
- `state`
- `readiness_label`

## Phase 0 Implementation Queue

- **0C**: permissions / RBAC
- **0D**: flows / secrets / hardcoded URLs
- **0E**: Flutter/backend contract fixes
- **0F**: security hardening
- **0G**: test checkpoint

## Not Production Ready Yet

The following areas are explicitly **not production ready**:

- `subscriptions` / `plans` / billing
- seat enforcement
- report exports
- `audit_logs` / immutable audit
- full data export / delete / retention
- SSO / SCIM / domain verification
