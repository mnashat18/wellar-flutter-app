# Wellar — Role-Based Full App Review

**Review date:** 2026-09-25  
**Review type:** Read-only static source review. No code was changed, and no analyzer, test suite, live API, or device test was run.  
**Payment scope:** Subscription, billing, and payment files and behavior were excluded entirely.

## Scope and evidence limits

The active role flows were derived from `lib/main.dart` and `RoleShellFactory` in `lib/screens/role_based_shells.dart:35-145,469-651`. The role tabs lazily mount their pages in an `IndexedStack` (`role_based_shells.dart:673-761`). I followed those tabs and the connected profile, notification, scan, request, and detail routes. Pre-authentication screens are shared by all roles. Files with no active route/caller are not treated as user-facing paths, though orphaned duplicate screens are noted where they create maintenance risk.

Findings distinguish confirmed source behavior from checks that require deployed Directus permissions, backend policy, real role accounts, or device interaction. “Break-it” results below are predicted from validation and async code paths; they are not represented as tests actually performed.

## OWNER

### 1. Code Quality & Bugs

#### Critical

None confirmed from the inspected active routes.

#### High

None confirmed as a client-side cross-role disclosure. The active owner route is built from the resolved membership role and checks the membership's user, workspace, and active/accepted status before entering the shell (`role_based_shells.dart:210-236`). That is useful client-side gating, but it does not prove server enforcement; see Security below.

#### Medium

- **Owner home/report data is assembled through several independent requests and state styles.** `OwnerHomeScreen` uses a `FutureBuilder` snapshot plus Riverpod providers (`owner_home_screen.dart:78-117`); `OwnerReportsScreen` composes requests, alerts, and readiness separately (`owner_reports_screen.dart:75-109`). Partial failures are now surfaced in the report view, but the split makes it easier for a future change to show mutually inconsistent totals. Expected behavior: a clearly timestamped, role/workspace-consistent snapshot or explicit partial status.
- **Owner and HR reuse a role-parameterized operations surface, while adjacent workflows remain separate implementations.** The owner shell uses `OwnerHrOpsScreen(role: 'owner')` and the HR shell uses `role: 'hr'` (`role_based_shells.dart:576-622`; `owner_hr_ops_screen.dart:27-45`). This is a reasonable reuse point, but authorization and data behavior must remain role-specific in every child/service. Expected behavior: role-aware actions and server authorization remain explicit and independently verified.
- **A duplicate Material import is present in the shared operations wrapper.** `owner_hr_ops_screen.dart:1-2` imports `package:flutter/material.dart` twice. It is low impact but signals lint/maintenance drift.
- **Unreferenced screen families coexist with the active owner flows.** The prior route inventory marks `company_dashboard_screen.dart`, `analytics_screen.dart`, `owner_more_screen.dart`, `owner_scan_history_screen.dart`, and `owner_requests_screen.dart` as legacy/orphaned; active Owner tabs instead use `OwnerHomeScreen`, `OwnerHrOpsScreen`, `AdminScanRequestsScreen`, and `OwnerReportsScreen` (`role_based_shells.dart:586-622`). Expected behavior: one maintained implementation per user journey so fixes do not diverge.

#### Low / Nice to have

- Extract shared error/loading/empty-state policies for the Owner dashboard and report surfaces; the report should continue to distinguish partial secondary-data failures from legitimate zeros (`owner_reports_screen.dart:82-109,147-154`).

### 2. UI / Design Consistency

| Screen | Role(s) | Design system | Notes |
|---|---|---|---|
| `splash_screen.dart`, `public_entry_screen.dart`, `login_screen.dart`, `register_screen.dart`, `workspace_access_screen.dart` | All, before role resolution | Old / inconsistent | Dark palette based on `AppColors`; differs from the role shell's `WellarTheme`. |
| `OwnerHomeScreen` | Owner | New, with Owner-specific layer | Uses `WellarTheme` plus `OwnerSurfaceCard`/Owner design widgets; metric hierarchy is distinct from HR. |
| `OwnerHrOpsScreen` → `OwnerWorkforceScreen` | Owner | New / role-specific | Shared wrapper, owner-specific workforce content. |
| `OwnerHrOpsScreen` → `OwnerCompanyScreen` | Owner | New / mixed | Compliance/setup content is wrapped by the shared shell but has a separate information hierarchy. |
| `AdminScanRequestsScreen` | Owner | Mixed | Shared with HR; dashboard design widgets coexist with standard Wellar cards. |
| `OwnerReportsScreen` | Owner | New / Owner-specific | `SectionHeader` and Owner report components sit alongside `WellarTheme`; visually polished but more bespoke than HR Home. |
| `ProfileScreen`, `NotificationsScreen` | Owner | New / shared | Uses Wellar cards, shared headers, and app-shell components. |
| `ScanFlowScreen`, `ScanDetailsScreen`, `HistoryScreen`, `EmployeeRequestsScreen`, request/alert details | Owner when opened from own scan/history or shared deep links | Mixed / scan-specific | Scan flow deliberately has a specialized camera/recording visual system; details and shared destinations use a mix of Wellar and older detail components. |

#### Medium

- Owner Home and Reports use a bespoke Owner surface on top of `WellarTheme`, while login/workspace and scan views have different palettes and component language. These are recognizable as separate flows but make the product feel less unified. Evidence: `theme/app_theme.dart:3-25`, `widgets/owner/owner_design_system.dart:55-80`, `utils/app_colors.dart` (auth imports, e.g. `login_screen.dart:1-10`), and `screens/scan/scan_premium_components.dart` (used by `wellness_check_screen.dart:1-5`). Expected behavior: a shared typography/spacing/component baseline, with a clearly intentional scan exception.
- Arabic users still see English shell tab labels: `_translateNavLabel` returns literal `Today`, `Scan`, `Results`, and `Account` (`role_based_shells.dart:779-796`). Expected behavior: all visible navigation labels use the selected locale and directionality.

#### Low / Nice to have

- Align section spacing and heading typography across Owner Home, compliance, reports, and profile; the bespoke surfaces currently set their own title and card styling.

### 3. UX Flow

#### High

None confirmed as a dead end in the active owner tab sequence.

#### Medium

- **“Switch organization” does not switch organizations.** When multiple organizations are available, the profile button invokes `_showSwitchOrganizationNotice` (`profile_screen.dart:320-337`); the notice path is informational rather than selecting/applying another workspace (`profile_screen.dart:591-610`). This violates the label and leaves multi-workspace owners without the expected action. Expected behavior: either a real workspace selector with confirmation and refreshed role shell, or a disabled/unavailable state whose label says so.
- **Some profile and home strings remain hardcoded English.** Examples include profile-fetch fallback text (`profile_screen.dart:160-170`) and Owner Home headings/actions (`owner_home_screen.dart:158-166,247-266`). Expected behavior: consistent Arabic/English copy across the owner journey.
- **Reporting is dense.** Readiness totals, requests, alerts, trends, and drilldowns share a long scroll surface. The screen has retry and partial-data feedback, but scan hierarchy can still make “what needs action now?” less immediate. Expected behavior: prioritize urgent actions and keep filters/context visible.

#### Low / Nice to have

- After an owner changes workspace (where that behavior is available), show the selected workspace and role prominently before data refresh finishes.

### 4. Security & Connectivity

#### Critical

No confirmed exploitable client-side cross-role data leak was established from this review. Directus ACL/backend policy was not available for verification.

#### High

- **User and workspace personal data is written to debug logs.** `AuthService._loadMe` logs user ID and email (`auth_service.dart:416-424`); workspace resolution logs user email, profile/workspace name, IDs, membership role/status, department and response bodies (`organization_service.dart:1332-1360`). These values can appear in device logs or captured diagnostics and should be treated as personal/workforce information. Expected behavior: production logs omit or irreversibly minimize identity and response payloads; diagnostic detail is opt-in and redacted.

#### Medium

- **Client-side tab hiding is not proof of authorization.** The active shell chooses a role-specific tab list (`role_based_shells.dart:81-145,469-623`), and route resolution checks membership (`role_based_shells.dart:210-236`), but this repository view cannot establish whether every Directus collection, custom endpoint, and deep-link target enforces the same owner/HR/manager/employee rules server-side. Expected behavior: every read/write is rejected by the server for an unauthorized role, even if a route is opened directly. This is an unverified security control, not a confirmed exploit.
- **Connectivity reports network-interface availability, not guaranteed Internet access.** The shell banner displays when `connectivityStatusProvider` is `false` (`connectivity_status_banner.dart:11-35`); action guards also block only when the provider explicitly reports false. A connected captive portal or unavailable backend can still fail as a request error, and an unresolved state is not the same as an online check (`app_providers.dart:5`, `role_based_shells.dart:733-743`). Existing loaded data is retained. This section records the current boundary only; the completed connectivity implementation was not changed or proposed for modification.
- **API validation is split between client and server.** Forms perform local validation, but client validation can be bypassed by a modified client; no deployed API schema/permission rules were in this repo scope. Expected behavior: server validates role, workspace, field formats, and allowed state transitions independently.

#### Low / Nice to have

- Add structured privacy-safe logs with correlation IDs and no raw response bodies.

### 5. Error Handling & “Break It” QA

#### High

None confirmed for the ordinary owner Home/Reports Retry paths inspected. Owner snapshot failures now show retry states (`owner_home_screen.dart:190-220,299-330`); report failures have a Retry action (`owner_reports_screen.dart:147-154`).

#### Medium

- **Rapid repeat taps / duplicate writes:** active create/cancel controls expose loading/cancelling flags in the scan-request flow, but source review cannot establish every service idempotency guarantee or server duplicate constraint. Expected behavior: disable while pending and use server idempotency/uniqueness for repeat submissions. Verify against a real owner account and API.
- **Invalid and oversized form input:** client validation is present in some forms, but no automated test matrix was found for very long text, Unicode, malformed IDs, or malformed deep-link values. Expected behavior: field-specific rejection before submission plus authoritative server validation.
- **Role/deep-link negative testing is missing.** The checked-in tests include organization-switch and auth/scan focused files, but no per-role authorization integration matrix (`test/organization_switch_flow_test.dart`, `test/auth_journey_screens_test.dart`, `test/scan_service_projection_test.dart`). Expected behavior: test owner access, HR restrictions, manager department scope, and employee self-only scope for each direct route and API operation.
- **Force-close mid-upload or mid-create:** the scan flow handles capture invalidation/stop failures (`scan_flow_impl_normalized.dart:2790-2810`), but persisted recovery and duplicate prevention after app termination are not established by this source review. Expected behavior: no false “completed” result; interrupted submissions have an explicit recoverable status.

#### Low / Nice to have

- Add widget/integration tests for empty fields, invalid formats, double taps, server errors, and back navigation across the owner-specific form surfaces.

## HR

### 1. Code Quality & Bugs

#### Critical

None confirmed from active source paths.

#### High

No confirmed unauthorized access was established. HR gets its own shell and an HR-role version of shared operations and reports (`role_based_shells.dart:547-583`); server enforcement remains unverified under Security.

#### Medium

- **HR reuses Owner-named widgets and services.** The HR workforce/compliance tabs instantiate `OwnerHrOpsScreen(role: 'hr')`; its role branch selects `HrWorkforceScreen`/`HrComplianceScreen` (`owner_hr_ops_screen.dart:27-45`). HR reports use `OwnerReportsScreen(roleOverride: 'hr')` (`role_based_shells.dart:576-583`). This reduces duplication but creates risk that a new owner-only action or data field is accidentally exposed in HR mode. Expected behavior: role-specific controls and service authorization have explicit tests.
- **Shared request tab is not the dedicated `HrRequestsScreen`.** The active HR shell mounts `AdminScanRequestsScreen` (`role_based_shells.dart:576-583`); standalone `hr_requests_screen.dart` is not that shell destination. This is a maintenance ambiguity: fixes in the standalone file do not necessarily affect HR users. Expected behavior: one documented, tested source of truth for active HR request actions.
- **Mixed async patterns complicate consistency.** HR Home uses a `FutureBuilder` snapshot (`hr_home_screen.dart:200-225`) with Riverpod profile/notification providers; compliance composes secondary calls and tracks partial failures (`hr_compliance_screen.dart:70-115`). Expected behavior: consistent loading/error/partial-data state semantics.

#### Low / Nice to have

- Remove or clearly label unreachable duplicate HR request/home screens once route ownership is confirmed.

### 2. UI / Design Consistency

| Screen | Role(s) | Design system | Notes |
|---|---|---|---|
| Shared auth/workspace screens | All, before role resolution | Old / inconsistent | Dark `AppColors` treatment; English remains in parts of forms. |
| `HrHomeScreen` | HR | New Wellar | Uses common Wellar cards and metric grid. |
| `OwnerHrOpsScreen` → `HrWorkforceScreen` | HR | New / role-specific | Shared wrapper, HR workforce content. |
| `OwnerHrOpsScreen` → `HrComplianceScreen` | HR | New / mixed | Compliance dashboard has supporting-data banner and its own denser hierarchy. |
| `AdminScanRequestsScreen` | HR | Mixed | Shared with Owner; requires role-specific labels/permissions to remain clear. |
| `OwnerReportsScreen(roleOverride: 'hr')` | HR | New / Owner-specific | Same report component family as Owner, with HR data branch. |
| `ProfileScreen`, `NotificationsScreen` | HR | New / shared | Shared account/action center. |
| `ScanDetailsScreen`, request/invitation/alert details | HR where routed from shared notifications | Mixed | Specialized details and scan styling are not fully uniform with Home. |

#### Medium

- HR Home and shared reports use different title, metric, and card rhythms; the reports screen carries an Owner-oriented implementation name and styling even in HR mode. This weakens role identity and makes HR content look borrowed. Evidence: `hr_home_screen.dart:95-106`, `owner_reports_screen.dart:147-185`, `role_based_shells.dart:576-583`. Expected behavior: the same base design tokens, with HR-specific headings and terminology.
- Arabic shell navigation leaves “Today” in English (`role_based_shells.dart:779-796`).

#### Low / Nice to have

- Make “workforce scope,” readiness, and compliance definitions visible where HR metrics are shown, rather than relying on dashboard familiarity.

### 3. UX Flow

#### High

No dead end confirmed in the primary HR shell. Tabs provide Today, Workforce, Requests, Compliance, and Reports (`role_based_shells.dart:547-583`).

#### Medium

- **Role mode is implicit on shared Owner/HR screens.** HR users land in shared `OwnerReportsScreen` and `AdminScanRequestsScreen`, and the code passes an HR override/role context. If a label or failure message is owner-centric, the user may not know whether a restriction is expected. Expected behavior: HR-specific labels, actions, and permission-denied explanations throughout the shared screens.
- **Partial-data states can be easy to mistake for genuine zero values.** Compliance and Reports now track supporting failures (`hr_compliance_screen.dart:70-115`; `owner_reports_screen.dart:82-109`), which is an improvement, but their summary metrics remain mixed with zero/empty fallbacks. Expected behavior: keep the partial-data indicator visually adjacent to affected metrics so HR does not interpret an unavailable department/alert count as “none.”
- **Shared profile organization action is informational only.** When multiple workspaces are available it shows a notice rather than switching (`profile_screen.dart:320-337,591-610`). HR users with multiple memberships cannot complete the action implied by its label.
- **Several HR surfaces have hardcoded English text and the shell labels remain partly untranslated.** Expected behavior: all HR-specific copy and status labels use localization keys and Arabic reading order.

#### Low / Nice to have

- Add a short “what requires action today” summary to HR Home, separated from compliance/report totals.

### 4. Security & Connectivity

#### Critical

No confirmed HR-to-employee data disclosure was demonstrated from client source alone.

#### High

- The same user/workspace PII logging applies to HR sessions: `auth_service.dart:416-424` and `organization_service.dart:1332-1360` include email, profile/workspace identifiers/names, roles and raw API response bodies. Expected behavior: do not emit workforce identity or server payloads in production diagnostics.

#### Medium

- **HR permission enforcement requires backend verification.** The HR shell shows HR tabs and instantiates shared Owner/HR screens (`role_based_shells.dart:547-583`), but no deployed Directus policy was reviewed. Expected behavior: HR can read only authorized workspace data and cannot invoke owner-only mutations by manually navigating or calling the API.
- **Connectivity limits are shared.** A transport-present state does not prove that the Directus API is reachable; data screens require remote services and use retries/errors. Previously loaded data remains in the widget/provider state when the connectivity banner changes. This review did not alter or propose changes to the completed connectivity work.
- Form constraints visible in Flutter are not a security boundary; server-side role/workspace validation cannot be confirmed in this repository view.

#### Low / Nice to have

- Ensure API error logging redacts request data and any workforce details returned in error bodies.

### 5. Error Handling & “Break It” QA

#### High

None confirmed for HR Home/Compliance/Reports primary full-load paths; HR Home has Retry (`hr_home_screen.dart:200-225`), and secondary compliance/report failures are tracked (`hr_compliance_screen.dart:70-115`, `owner_reports_screen.dart:82-109`).

#### Medium

- **Permission-denied test:** a stale HR membership or a manually opened owner-only detail should produce an access-denied state, not an indefinite loader or leaked data. Source route selection is role-aware; backend response behavior must be exercised with real HR credentials.
- **Double-submit and malformed HR request input:** the active shell request tab is `AdminScanRequestsScreen`, not `HrRequestsScreen` (`role_based_shells.dart:576-583`). Verify that the active form validates all required values, disables while saving, and reports service validation rather than a generic failure. No test suite run was performed.
- **Connection drop mid-report refresh/export:** existing request failures should remain visible; actual export/file behavior under Android/iOS permissions and network interruption needs device testing.
- **Role-specific regression coverage is absent.** The same code serves Owner and HR data branches, but the checked-in tests listed above do not provide an owner-vs-HR action/visibility matrix.

#### Low / Nice to have

- Add HR-focused widget tests for empty teams, zero compliance, partial secondary fetch failures, 403 responses, and rapid repeated form submission.

## MANAGER

### 1. Code Quality & Bugs

#### Critical

None confirmed from active source paths.

#### High

No confirmed cross-role leak was established. Manager pages are selected from the manager membership shell (`role_based_shells.dart:508-544`); server-side enforcement remains unverified.

#### Medium

- **Manager screens mix Riverpod and manually managed futures.** Manager Home reads profile/history/notification providers and loads a manager snapshot separately (`manager_home_screen.dart:62-89,181-202`); Team and scan requests use their own futures/reload paths (`manager_team_screen.dart:58-75`, `manager_scan_requests_screen.dart:85-110`). This increases the chance that a workspace/department switch refreshes one section but leaves another stale. Expected behavior: all manager data is keyed to the current membership/workspace revision and refreshed together.
- **Unreachable parallel request screens create drift risk.** The manager shell’s Requests tab is `ManagerScanRequestsScreen` (`role_based_shells.dart:537-544`); standalone `ManagerRequestsScreen`/legacy `owner_requests_screen.dart` are not interchangeable with it. Expected behavior: make the active route explicit in tests and avoid duplicating request semantics.

#### Low / Nice to have

- Define a consistent manager-specific view model for team metrics and request queues rather than deriving the same status in multiple widgets.

### 2. UI / Design Consistency

| Screen | Role(s) | Design system | Notes |
|---|---|---|---|
| Shared auth/workspace screens | All, before role resolution | Old / inconsistent | `AppColors`-based style. |
| `ManagerHomeScreen` | Manager | New Wellar | Uses shared dashboard cards and department/team chips. |
| `WellnessCheckScreen` → `ScanFlowScreen` | Manager | Scan-specific | Premium scan components, camera/mic capture flow and a separate visual palette. |
| `ManagerTeamScreen` | Manager | New Wellar | Common Wellar cards/empty/error states. |
| `ManagerScanRequestsScreen` | Manager | New / mixed | Wellar cards and dedicated request actions. |
| `ProfileScreen`, `NotificationsScreen` | Manager | New / shared | Shared account and notification center. |
| `HistoryScreen`, `ScanDetailsScreen`, request/scan-request details | Manager when linked from scan/request flows | Mixed | Older scan/detail presentation alongside Wellar shell. |

#### Medium

- Manager Home and the Scan workflow have intentionally different visual languages, but transition labels, typography, and button treatment do not always signal that difference. Evidence: `manager_home_screen.dart:74-103` versus `wellness_check_screen.dart:1-5` and `scan_flow_impl_normalized.dart`. Expected behavior: retain scan-specific contrast while sharing typography, button semantics, and consistent back/cancel placement.
- Arabic shell navigation still returns English labels for Today, Scan, and Account (`role_based_shells.dart:779-796`).

#### Low / Nice to have

- Use the same department-scope label and iconography on Manager Home, Team, and Request details.

### 3. UX Flow

#### High

None confirmed as a primary-tab dead end. Manager has Today, Scan, Workforce, Requests, and Account (`role_based_shells.dart:508-544`).

#### Medium

- **Manager scope needs to be explicit at every destination.** Manager Home shows a team/department scope chip (`manager_home_screen.dart:131-135,168-172`), but linked request and scan details should preserve that context so managers can tell which team the item belongs to. Expected behavior: keep workspace/department context visible in lists and detail pages.
- **Profile “Switch organization” is not an actual switch.** The shared profile action opens an informational notice (`profile_screen.dart:320-337,591-610`). A manager with multiple memberships cannot complete the named action.
- **Capture interruption remains a high-stress workflow.** The scan flow has cleanup for stopping audio/video on invalidation (`scan_flow_impl_normalized.dart:2790-2810`); source inspection cannot confirm whether the user always understands whether a partial capture was saved after backgrounding, permission revocation, or force-close. Expected behavior: clear “discarded / upload pending / completed” state with no ambiguous success.

#### Low / Nice to have

- Make the difference between a personal wellness check and a manager’s team action clear before starting capture.

### 4. Security & Connectivity

#### Critical

No confirmed client-side cross-role data leak was established.

#### High

- User identity/workspace details and raw error response bodies can be logged in all manager sessions through auth/workspace resolution (`auth_service.dart:416-424`, `organization_service.dart:1332-1360`). Workforce data is sensitive even when it is not an authentication secret. Expected behavior: privacy-safe production logs.

#### Medium

- **Department boundary depends on server rules.** Manager shell visibility is not enough to prove a manager cannot query another department’s members/requests directly. The client constructs role/workspace-specific screens (`role_based_shells.dart:508-544`), while manager service queries include workspace and department filters in relevant methods (`manager_ops_service.dart:292-294`). A client filter is not an authorization boundary. Expected behavior: server-enforced department scope for reads and writes; test with a manager token against another department ID.
- Connectivity uses a network-interface state; it cannot guarantee API reachability. Existing data stays rendered, and key scan/refresh actions show offline feedback per the completed connectivity pass. Mid-upload or captive-portal behavior still requires a live device/API test. No connectivity code was changed or proposed for modification.

#### Low / Nice to have

- Audit manager error telemetry for employee identifiers in request/scan server responses.

### 5. Error Handling & “Break It” QA

#### High

None confirmed on manager Home snapshot failure; the code renders `WellarErrorState` with Retry (`manager_home_screen.dart:181-202`). Team and request list failures also have Retry states (`manager_team_screen.dart:58-75`, `manager_scan_requests_screen.dart:85-110`).

#### Medium

- **Try direct owner/HR route access with a manager session.** The shell only presents manager tabs, but the report cannot establish server denial for copied/deep-linked routes. Expected: access denied at route and API layer, with no details returned.
- **Double-tap manager scan/request action during slow network.** Busy-state handling is visible on list/forms, but service idempotency and duplicate server records were not tested. Expected: one operation, one result, retry-safe error on timeout.
- **Input edge cases:** manager flows include scan/report filters and assignment/detail actions; malformed IDs and unusually long/free-form values need field-specific client validation and server validation. Static source is not evidence that all edge cases pass.
- **Force-close/background during camera/audio capture:** cleanup catches stop exceptions, but real camera/microphone ownership and upload cancellation are platform-dependent. Test permission revocation, app backgrounding, incoming call, and process death on both platforms.

#### Low / Nice to have

- Add manager-specific integration tests for department isolation, repeated actions, scan interruption, and offline-to-online recovery.

## EMPLOYEE

### 1. Code Quality & Bugs

#### Critical

No confirmed self-data leakage was found in the inspected history provider. It obtains the active workspace and fetches history with the current session user (`app_providers.dart:197-212`, `scan_service.dart:153-203`). Backend ACLs still need separate validation.

#### High

None confirmed from the active Employee shell.

#### Medium

- **Home uses an owner-named history provider for an employee-facing personal readiness card.** `EmployeeHomeScreen` reads `ownerHistoryTimelineProvider` (`employee_home_screen.dart:43-45`); the provider filters by current user and workspace (`app_providers.dart:197-212`, `scan_service.dart:153-203`), so this is not itself proof of leakage, but the naming obscures the contract and invites unsafe reuse. Expected behavior: a clearly personal-history provider name and a test proving user/workspace filtering.
- **A failed assigned-request fetch has no retry action in the Home preview.** On Employee Home, `requestsAsync` error renders only an unavailable text message (`employee_home_screen.dart:294-302`); the dedicated Requests tab does have Retry (`employee_requests_screen.dart:69-77`). Expected behavior: give the user a retry from the failed preview or a clear route to the working Requests screen.
- **Orphaned Home/detail alternatives remain in the source tree.** Active employee tabs use `EmployeeHomeScreen`, `WellnessCheckScreen`, `HistoryScreen`, and `EmployeeRequestsScreen` (`role_based_shells.dart:498-505`); `home/*_view.dart`, `home_screen.dart`, and other older variants are not equivalent. Expected behavior: avoid editing an unmounted screen when fixing the active employee journey.

#### Low / Nice to have

- Move repeated “profile information unavailable” fallback copy and readiness display mapping into shared presentation helpers.

### 2. UI / Design Consistency

| Screen | Role(s) | Design system | Notes |
|---|---|---|---|
| Shared auth/workspace screens | All, before role resolution | Old / inconsistent | Dark `AppColors` treatment. |
| `EmployeeHomeScreen` | Employee | New Wellar | Home header, personal check CTA, history distribution and assigned-request preview. |
| `WellnessCheckScreen` → `ScanFlowScreen` | Employee | Scan-specific | Camera/recording-focused palette and controls; deliberately more immersive than Home. |
| `HistoryScreen` / `ScanDetailsScreen` | Employee | Mixed | New list/error wrappers around scan-specific/older detail styling. |
| `EmployeeRequestsScreen` | Employee | New Wellar | Shared cards, skeleton, empty and retry states. |
| `ProfileScreen`, `NotificationsScreen` | Employee | New / shared | Same account and notification pages used by all roles. |
| `RequestDetailsScreen`, `ScanRequestDetailsScreen`, invitation and alert details | Employee when routed from notifications | Mixed | Shared destination pages with older English-heavy sections. |

#### Medium

- Employee Home is a newer card system but the scan journey uses a separate visual language; the transition can feel like entering a different app. Evidence: `employee_home_screen.dart:51-90` and `wellness_check_screen.dart:1-5`. Expected behavior: preserve a focused capture experience while sharing typography, localization, and navigation affordances.
- The employee navigation still shows “Today,” “Scan,” “Results,” and “Account” as English strings in Arabic mode (`role_based_shells.dart:779-796`).
- Several scan/request detail surfaces contain hardcoded English copy. This makes safety/status instructions harder to follow for Arabic-first users.

#### Low / Nice to have

- Keep personal versus team/workspace data visually labeled on every card so employees do not mistake workplace metrics for their own health/readiness results.

### 3. UX Flow

#### High

None confirmed as a core Employee tab dead end. The primary action is the readiness check; History and Requests are separate tabs (`role_based_shells.dart:469-505`).

#### Medium

- **Home request-preview failure is not actionable.** It displays a message but no retry (`employee_home_screen.dart:297-302`), even though the Requests tab can retry (`employee_requests_screen.dart:69-77`). This leaves a common Home error with no next step.
- **Force-close during a scan can lose in-progress work.** The capture flow invalidates and stops recorder/camera on invalidation (`scan_flow_impl_normalized.dart:2790-2810`), but no durable draft/recovery behavior is established in source. Expected behavior: tell the employee whether the capture was discarded, saved locally, or accepted by the server; never imply a result exists before confirmation.
- **Profile workspace switch action is misleading for multi-workspace users.** The button opens a notice rather than switching (`profile_screen.dart:320-337,591-610`).
- Readiness results and scan request detail labels mix personal wellness, assignment status, and workspace language; users should not need to infer which item requires their action.

#### Low / Nice to have

- Give employees a short explanation of why a readiness check is requested and how a completed result is used, before they grant camera/microphone access.

### 4. Security & Connectivity

#### Critical

No client-side disclosure to another employee was confirmed in the inspected employee history query. The user filter is present (`scan_service.dart:158-203`); enforce the same rule server-side.

#### High

- Employee sessions can trigger the shared auth/workspace logs containing user email, workspace/member identifiers, roles, department names, and raw API error bodies (`auth_service.dart:416-424`, `organization_service.dart:1332-1360`). This is workforce personal data and should not be exposed in production logs.

#### Medium

- **Self-only access cannot be concluded from client filters.** The employee history service supplies `filter[user][_eq]` and a workspace filter (`scan_service.dart:158-203`), but employee-only server permission rules and result endpoints were not available for review. Expected behavior: a modified client cannot read another employee’s scan result by changing an ID.
- Connectivity warning/action handling is app-shell level plus targeted operation guards; connected Wi-Fi does not prove Internet/backend availability. Already-loaded data stays visible, while scans and refreshes can show an offline warning. Upload interrupted mid-request, permission-denied camera/microphone, and API timeout outcomes need real device testing. This audit does not propose edits to the completed connectivity implementation.
- Sensitive scan/readiness values are health-adjacent workforce information. No secure local database was found in the active path; session credentials are stored using `FlutterSecureStorage` (`state/session.dart:1-7,28-36`). This is a positive control, but it does not establish encryption or access control for server-side records/logging.

#### Low / Nice to have

- Keep employee-specific results out of notification previews and debug logs unless the display is necessary and privacy-safe.

### 5. Error Handling & “Break It” QA

#### High

None confirmed as an unhandled failure in the active Employee tab fetch paths. Employee requests has a Retry state (`employee_requests_screen.dart:69-77`), readiness lookup has an unavailable message (`employee_home_screen.dart:219-239`), and scan-result polling maps transient failures to retry/timeout states (`scan_details_screen.dart:247-280`).

#### Medium

- **Empty/invalid input:** employee scan starts without a text form, but consent/permission conditions and scan prerequisites need on-device verification. Expected: explain each denied permission and offer a safe cancel/retry path; do not start capture partially.
- **Double tap Start check / rapid retake:** the role shell warns when offline and opens the scan flow (`role_based_shells.dart:729-743`; `wellness_check_screen.dart:119-134`). Verify the flow prevents duplicate camera sessions and duplicate submissions while upload/processing is pending.
- **Connection loss mid-recording/upload:** source contains capture cleanup and result polling error UI (`scan_flow_impl_normalized.dart:2790-2810`, `scan_details_screen.dart:247-280`), but network disconnect, server accepted-but-client-timed-out, and process death require device/API tests. Expected: reconcile status before allowing a duplicate scan.
- **Directly open another user’s result/request ID:** the client UI role does not prove server authorization. Test with an Employee token and another employee’s identifier; expected result is a non-enumerating denial/not-found state.
- **Test coverage gap:** no employee end-to-end suite was found for own-data isolation, permission revocation, upload interruption, or double-submit. Existing scan tests are service/model focused (`test/scan_service_projection_test.dart`, `test/scan_result_polling_policy_test.dart`, `test/scan_result_model_test.dart`).

#### Low / Nice to have

- Test very long display names, Unicode/emoji in profile fields, large text, RTL, and landscape on the Home, scan, result, and request pages.

## Findings that affect multiple roles

- **All roles:** sensitive user/workspace fields and raw API response bodies appear in diagnostic logs (High; `auth_service.dart:416-424`, `organization_service.dart:1332-1360`).
- **All roles:** hardcoded shell navigation labels remain English in Arabic mode (Medium; `role_based_shells.dart:779-796`).
- **All roles:** client-side role/tab routing is not a substitute for server-enforced authorization; deployed Directus access policies were not part of the available review (Medium verification risk; `role_based_shells.dart:81-145,210-236`).
- **All roles:** `connectivity_plus` detects available network transport, not end-to-end Internet/API reachability. Existing loaded data is retained, but interruption during active requests/uploads needs device-level verification. No connectivity code was modified or proposed for modification.
- **All roles:** one profile control claims to switch organizations but currently opens a notice only (`profile_screen.dart:320-337,591-610`).

## Summary counts

Counts below are role-specific occurrences; shared findings count once for each affected role. “Critical” means a confirmed immediate security or data-loss defect from source. The security-sensitive logging finding is High. Unverified server controls are Medium verification risks, not confirmed exploits.

| Role | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|
| Owner | 0 | 1 | 16 | 5 |
| HR | 0 | 1 | 16 | 5 |
| Manager | 0 | 1 | 13 | 5 |
| Employee | 0 | 1 | 17 | 5 |

## Overall assessment

The app has clear role-specific primary tabs and its core Home/scan/request list states often include loading, empty, error, and retry handling. The main risks from this source review are privacy-sensitive diagnostics, the gap between client-side role selection and unverified server authorization, inconsistent Arabic localization/design across entry, shell, and scan surfaces, and insufficient role-by-role integration testing. No live role accounts, backend permission configuration, physical-device permissions, or offline upload scenarios were available, so these remain verification items rather than claims of observed runtime behavior.
