# Wellar Broken Interactions Audit

**Scope:** interactive controls in `lib/screens/` and `lib/widgets/` that are visibly actionable but currently no-op, fail, save nothing, or terminate in a placeholder. This is an interaction audit only; it does not assess tenant scope, authorization, or other security concerns.

**Review method:** searched the screen/widget source for interactive callbacks, empty callback bodies, stub/TODO/placeholder language, and service methods called by candidate controls; inspected candidates and surrounding UI in context. Empty callbacks in commented-out legacy code were excluded. Controls disabled explicitly while an operation is in progress were also excluded. Line references below refer to the source reviewed.

## Authentication

### 1. Registration fields do not update submit eligibility as the user types

- **Location:** [register_screen.dart](/D:/flutter_app/wellar-flutter-app/lib/screens/register_screen.dart:699)
- **Control:** first name, last name, email, password, and confirmation fields in the shared `_FieldColumn`.
- **Current behavior:** the `TextField` callback is `onChanged: (_) {}`. The parent computes `canSubmit` from the controllers while building, but does not rebuild on each edit. Focus listeners trigger a rebuild on blur, so the button and validation state can stay stale during typing.
- **Expected behavior:** refresh field errors and the Register button state as input changes.
- **Implementation status:** the form submit handler and validation already exist (`_register`, controller-based validators); wire the field change callback to the parent rebuild/state update.
- **Remediation — Fixed:** each registration field now rebuilds its parent on edit, so `canSubmit` and inline validation update while the user is typing.

## Employee home and daily use

### 2. Insights pull-to-refresh performs no refresh

- **Location:** [insights_screen.dart](/D:/flutter_app/wellar-flutter-app/lib/screens/insights_screen.dart:44)
- **Control:** pull down on the Insights content.
- **Current behavior:** `RefreshIndicator.onRefresh` awaits an empty async function, so the spinner appears but the displayed data is not requested again.
- **Expected behavior:** reload the same insights/home data used by the screen.
- **Implementation status:** yes. The screen already watches `homeDataProvider`, and the Retry action in its error state invalidates that provider at line 36. Reuse that invalidation for pull-to-refresh.
- **Remediation — Fixed:** pull-to-refresh invalidates `homeDataProvider` and awaits its refreshed future.

### 3. Permission view refresh is a no-op (component currently has no caller)

- **Location:** [permission_view.dart](/D:/flutter_app/wellar-flutter-app/lib/screens/home/permission_view.dart:23)
- **Control:** pull down on the permission message.
- **Current behavior:** refresh callback is empty. The view cannot re-check access or reload its parent state.
- **Expected behavior:** refresh the permission/workspace state, or omit the refresh affordance if the view cannot perform that work.
- **Implementation status:** access/membership reloads exist elsewhere (for example the workspace access flow), but this component accepts no refresh callback and has no references from current `lib/` callers. It needs caller wiring before it can refresh; as currently unreachable, ordinary users do not encounter it through a discovered route.
- **Remediation — Confirmed dead code, left as-is:** repository search confirms no `lib/` caller; a source comment now documents that this legacy widget is unused.

### 4. Permission view `Got it` button does nothing (component currently has no caller)

- **Location:** [permission_view.dart](/D:/flutter_app/wellar-flutter-app/lib/screens/home/permission_view.dart:56)
- **Control:** `Got it` check button.
- **Current behavior:** empty `onPressed`; tapping does not dismiss the message or navigate away.
- **Expected behavior:** acknowledge/dismiss the notice or return to a usable screen.
- **Implementation status:** no dismissal/navigation callback is exposed. It needs a small UI action and caller wiring; the component currently has no references from `lib/` callers, so this is not presently a normal-user route.
- **Remediation — Confirmed dead code, left as-is:** repository search confirms no `lib/` caller; a source comment now documents that this legacy widget is unused.

### Verification note: scan-history list item routes to scan details

- **Status:** checked; not a finding. Its tap handler opens the selected result details. Empty callbacks in the commented-out legacy `home/history_view.dart` implementation were excluded because they are not active UI.

## Pricing and subscriptions

### 5. Pricing plan purchase actions stop with `Subscriptions are not available yet`

- **Location:** [pricing_screen.dart](/D:/flutter_app/wellar-flutter-app/lib/screens/pricing_screen.dart:242)
- **Control:** each plan card’s primary action (for example Subscribe/Start trial, passed as `onAction` around line 101).
- **Current behavior:** selecting a plan only shows a SnackBar and returns. The old client-side flow is commented out and cannot complete a purchase.
- **Expected behavior:** begin a legitimate checkout and reflect the verified result, or present the unavailable state without an actionable purchase button.
- **Implementation status:** requires the planned payment provider and protected entitlement backend; no working checkout is present in this path. This is an intentional fail-closed block, but the visible plan action still promises a flow it cannot start.

### 6. `Upgrade Plan` always fails

- **Location:** [subscription_management_screen.dart](/D:/flutter_app/wellar-flutter-app/lib/screens/subscription_management_screen.dart:203)
- **Control:** `Upgrade Plan`.
- **Current behavior:** it can open a plan picker, but choosing a plan calls `upsertSubscriptionForProfile`, which throws `Subscriptions are not available yet`; the screen catches it and displays `Upgrade failed`.
- **Expected behavior:** launch payment/checkout and apply the upgrade only after a verified payment result.
- **Implementation status:** plan catalog and display exist; payment/entitlement processing must be built with the backend integration.

### 7. `Renew Subscription` always fails

- **Location:** [subscription_management_screen.dart](/D:/flutter_app/wellar-flutter-app/lib/screens/subscription_management_screen.dart:211)
- **Control:** `Renew Subscription`.
- **Current behavior:** calls `renewSubscription`, which routes to the disabled upsert and throws; the UI displays `Renew failed`.
- **Expected behavior:** initiate a renewal checkout or provider-managed renewal, then reload subscription state after confirmation.
- **Implementation status:** needs payment provider/backend work. The UI error path is wired, but the renewal operation is not available.

### 8. `Cancel Subscription` always fails

- **Location:** [subscription_management_screen.dart](/D:/flutter_app/wellar-flutter-app/lib/screens/subscription_management_screen.dart:218)
- **Control:** `Cancel Subscription`.
- **Current behavior:** calls `cancelSubscription`, which always throws `Subscription changes are not available yet`; the UI displays `Cancel failed`.
- **Expected behavior:** submit a cancellation request to the payment provider/backend and show the resulting effective date/status.
- **Implementation status:** requires a backend/provider cancellation operation. No working client cancellation path exists.

## Organization and management

### 9. Team role dropdown changes a local value that cannot be saved

- **Location:** [business_members_manage_screen.dart](/D:/flutter_app/wellar-flutter-app/lib/screens/business_members_manage_screen.dart:419)
- **Control:** Role dropdown (Owner/Admin/Manager/Member).
- **Current behavior:** changing the selection updates `_selectedRole`, while nearby copy says role selection is disabled. No save path uses the value because `_saveMember` only opens a Coming Soon dialog.
- **Expected behavior:** either provide a working invitation/member role save or disable the dropdown and present accurate availability text.
- **Implementation status:** `OrganizationService.upsertBusinessMemberByEmail` exists (around line 1584), so membership persistence has partial service support. The invitation/member form flow is not wired to it and may need invitation/backend work for unknown users.
- **Remediation — Fixed:** the role is now passed to `upsertBusinessMemberByEmail`; the UI states that only already-registered Wellar users can be added and that this screen cannot invite new users.

### 10. `Save Member` only opens a Coming Soon dialog

- **Location:** [business_members_manage_screen.dart](/D:/flutter_app/wellar-flutter-app/lib/screens/business_members_manage_screen.dart:448); handler at line 123.
- **Control:** `Save Member`.
- **Current behavior:** `_saveMember()` calls `_showComingSoonDialog()` and does not validate the email, save a role, invite anyone, or update the member list. The dialog confirms invitations will be available in a future update.
- **Expected behavior:** validate the email and create/update/invite a member, then refresh the list and confirm the outcome; until implemented, the form should not look submittable.
- **Implementation status:** member listing and membership upsert exist in `OrganizationService`, but a complete invitation flow is not wired to this screen; invitation behavior needs to be built or connected to the proper backend contract.
- **Remediation — Fixed:** validates email, saves the selected role, displays service errors inline, refreshes the member list, closes the form on success, and shows a success message. Unknown users cannot be invited because the service requires a matching existing user record.

## Settings and admin

No additional confirmed no-op callbacks, placeholder routes, or unhandled visible tap-time null failures were found in the remaining inspected screen/widget candidates. Controls whose callbacks are explicitly `null` while busy or unavailable were treated as disabled rather than broken. This report records source-visible behavior; device-only behavior such as platform permission prompts is outside this source audit.

## Count and top 10 most user-visible

**Total confirmed broken/partial interactions: 10.** The permission view contributes two findings but currently has no caller in `lib/`; all three subscription management controls fail visibly after use. Counts are by distinct interactive control or behavior, not by every plan card instance.

For a normal employee doing wellness checks, the most relevant items are:

1. Registration fields may leave the Register button and inline validation stale while typing (finding 1; new users only).
2. Insights pull-to-refresh does not reload data (finding 2; users opening Insights).
3. Permission-view `Got it` does nothing (finding 4; currently no discovered caller).
4. Permission-view pull-to-refresh does nothing (finding 3; currently no discovered caller).
5. Pricing plan action displays an unavailable message instead of starting checkout (finding 5; business owners only).
6. Subscription upgrade action fails after plan selection (finding 6; business owners only).
7. Subscription renewal action fails (finding 7; business owners only).
8. Subscription cancellation action fails (finding 8; business owners only).
9. Team role selection changes only an unsaved local value (finding 9; managers/admins only).
10. Save Member only opens a Coming Soon dialog (finding 10; managers/admins only).
