# Wellar Full UX/UI and Flow Audit

**Review type:** source-based end-to-end UX review. No code was changed and no runtime/device testing was performed. Error and offline observations are based on the screen state and callback code, not on live service behavior.

## Route map used for this review

- `lib/main.dart` starts at `SplashScreen`.
- `SplashScreen` sends signed-out users to `PublicEntryScreen`; a saved session is validated and routed to workspace resolution or a role shell.
- `RoleShellFactory` in `lib/screens/role_based_shells.dart` defines the active primary tabs:
  - Owner: Today, Workforce, Requests, Compliance, Reports.
  - HR: Today, Workforce, Requests, Compliance, Reports.
  - Manager: Today, Scan, Workforce, Requests, Account.
  - Employee: Today, Scan, Results, Requests, Account.
- The shell lazily mounts tab pages and keeps them in an `IndexedStack`. `ProfileScreen` is the account tab for Employee and Manager, and a header/account destination for Owner and HR.
- Several files in `lib/screens/` are legacy or have no caller in the active shell. They are called out as such instead of being treated as normal user paths.

## Launch and authentication

## lib/screens/splash_screen.dart

**A. First impression / purpose — 4/5.** A branded dark splash quickly communicates Wellar and transitions directly to the correct entry or authenticated destination. Session/workspace skipping is already present, so a separate “skip intro” control is unnecessary. The wordmark is text rather than a recognizable brand mark.

**B. UI issues.** Strongly branded, centered layout with small status copy. The rotating startup labels are easy to miss and English-first; Arabic translations exist for some strings, but the app still contains many hardcoded English surfaces elsewhere. Long loading copy is constrained and scrollable.

**C. UX issues.** Normal and slow paths are distinct, and timeout has Retry plus a fallback route. The 1.4-second threshold avoids an artificial wait. A Retry button is useful, but users are not told which part of startup failed.

**D. Error handling.** Session/workspace timeout: **[Has proper error message]** retry/fallback state. Firebase exception: **[Generic error / retry if resolution also times out]**. Other exceptions in `_bootstrap`: **[Silent failure]**; they are only logged and leave the screen in its loading state without exposing Retry.

**E. Offline.** Needs network to validate session and resolve workspace. Timeout provides recovery, but no offline/cached workspace mode is apparent. Online-only routing is reasonable; the generic exception path should not leave an indefinite spinner.

**F. Animation / transition.** Wordmark reveal, ambient background, status transitions and reduced-motion handling are present. This is restrained enough for a splash; no extra animation is needed.

## lib/screens/public_entry_screen.dart

**A. First impression / purpose — 4/5.** Clear public entry with Sign in, Start organization, and invite-code paths. Users can understand the primary choices quickly.

**B. UI issues.** Polished card and contrast, but its visual language differs from the newer Wellar shell and the later onboarding page. Text and actions are English-only. Invite sheet is a secondary route that needs a little more context about who can supply a code.

**C. UX issues.** The three paths are understandable. “Start organization” immediately goes to account registration, so the handoff from sign-up to workspace creation may feel like extra steps. The invite sheet can be dismissed by dragging/back.

**D. Error handling.** Sign in / registration navigation: **[Has proper error message on destination]**. Invite code validation/lookup: **[Has proper validation/network error in destination]**. Failed external links are not part of this screen.

**E. Offline.** The entry screen itself works offline; login, registration, and invite lookup do not. Downstream forms give feedback, so this is an acceptable online-only entry.

**F. Animation / transition.** Static branded gradient; route transitions use the app’s fade/slide route. No further motion is needed.

## lib/screens/auth_intent_screen.dart

**A. First impression / purpose — 3/5.** The create/join choice is understandable, but this screen is not in the active launch path discovered from `main.dart` and `SplashScreen` (it is reachable only through the unreferenced `PublicHomeScreen`).

**B. UI issues.** Clear text and scroll adaptation; it duplicates the choices already presented by `PublicEntryScreen`. Copy uses “organisation” while other screens use “organization”, and English text is hardcoded.

**C. UX issues.** Create, join, and sign-in paths work if routed here. Having two public entry experiences creates inconsistency; this one also promises join-by-code behavior that the active entry page already handles differently.

**D. Error handling.** Navigation actions: **[Has proper error message on destination]**. No service action is performed here.

**E. Offline.** Static screen works offline; destinations are online-only.

**F. Animation / transition.** Route transition only. Sufficient for a choice screen.

## lib/screens/onboarding_screen.dart

**A. First impression / purpose — 3/5.** It presents Google sign-in, login, account creation, and pricing in a large marketing layout. It is not called by the current app launch route and should not be treated as the normal first-run experience.

**B. UI issues.** The large 44px hero copy can dominate smaller screens, although it is inside a scroll view. “Google sign-in only” conflicts with separate Login and Create Account options. Strings and feature claims are mostly hardcoded English.

**C. UX issues.** Its route choices work, but its existence beside `PublicEntryScreen` makes the intended entry path unclear. The plan CTA leads to pricing whose purchase actions are unavailable pending payment backend work.

**D. Error handling.** Google sign-in: **[Generic error]** visible banner. Login/register navigation: **[Has proper error message on destination]**. Pricing route: **[Has unavailable message on plan action]**.

**E. Offline.** Screen layout works offline; Google auth/pricing data require network. Google failure is visible.

**F. Animation / transition.** `FadeSlide` entrance and animated background. It already has enough motion; if this screen is retained, harmonize with the active public entry rather than adding animation.

## lib/screens/login_screen.dart

**Phase 3 — Fixed:** login and Google sign-in now warn and stop before submission when the connectivity state reports no network.

**A. First impression / purpose — 4/5.** Familiar email/password sign-in with recovery, registration and Google paths. Form hierarchy is clear.

**B. UI issues.** Visual treatment differs from newer Wellar screens and contains hardcoded English. Password visibility controls and scroll/keyboard behavior are understandable. Arabic alignment depends on directionality; no runtime RTL check was possible.

**C. UX issues.** Forgot password returns the entered email, which helps. Registration and invite links preserve useful context. Sign-in button remains disabled until required values pass local checks, which is clear but may hide why until inline validation appears.

**D. Error handling.** Invalid credentials/server/network: **[Has proper error message]** via `AuthFlowException`/friendly mapping. Google sign-in: **[Generic error]** visible. Forgot password: **[Has proper error message]**. Route actions: **[Has proper outcome on destination]**.

**E. Offline.** Login is online-only; connection/auth failures are surfaced in the form. No offline authentication mode is shown.

**F. Animation / transition.** Fade/slide route and field/form feedback. Adequate; prioritize reliable loading and error copy over extra movement.

## lib/screens/register_screen.dart

**Phase 3 — Fixed:** registration is blocked with offline feedback when no network is available; Terms/Privacy launch errors use `AppFeedback` styling.

**A. First impression / purpose — 3/5.** Complete registration form with legal acceptance and invite support; the form is usable but dense.

**B. UI issues.** Many field labels and validation strings are hardcoded English even when language selection is Arabic. Long validation copy and multiple fields make the screen tall, though it scrolls and responds to the keyboard. Terms and Privacy links use separate tap text styling.

**C. UX issues.** Local validation covers names, email, password, confirmation, and legal acceptance. Real-time field rebuilds now allow eligibility/errors to update while typing. Account creation may route through Splash and workspace setup, so the full sequence can feel indirect.

**D. Error handling.** Local validation: **[Has proper error message]**. Duplicate/network/server registration failure: **[Has friendly error message]**. Account-created-but-sign-in-needed: **[Has status message]**. Terms/Privacy link launch: **[Silent failure]** if the URL cannot open; no result feedback is shown.

**E. Offline.** Form and local validation work offline; account creation does not. Registration failure is visible, but there is no draft persistence if the app closes.

**F. Animation / transition.** Fade entrance, password visibility toggle, loading indicator and page transition. Useful feedback is present; avoid adding decorative movement to this long form.

## lib/screens/forgot_password_screen.dart

**A. First impression / purpose — 4/5.** Focused recovery form with a privacy-preserving success message that does not reveal whether an account exists.

**B. UI issues.** Clear but English-only, with a distinct older dark style. The success state gives the user clear next steps; the page is scrollable with keyboard.

**C. UX issues.** Back returns to sign-in with the typed email. Invalid email is inline; success replaces the form with “Back to sign in”.

**D. Error handling.** Validation: **[Has proper error message]**. Request failure: **[Generic error]** retryable. Success: **[Has proper confirmation]**.

**E. Offline.** Request is online-only; connection failure is visible. No offline capability is expected.

**F. Animation / transition.** Route transition only; static form is appropriate.

## lib/screens/invite_screen.dart

**A. First impression / purpose — 3/5.** Invitation details and claim action are direct, but status, sender, and request context can be small and English-only.

**B. UI issues.** Uses the older space background/card styling. Invalid and expired invitations share a sparse error card; when fetching throws, the future can have an error but the builder checks only `data == null`, so the user gets “Invalid invite” even for a network outage.

**C. UX issues.** Create account/sign in preserves the invite token. A claim routes to a forced scan or role shell. “Back to Home” routes to the role router and may not behave like a normal back action for signed-out users.

**D. Error handling.** Invite fetch: **[Generic/misclassified error]** network errors appear as invalid/expired. Claim: **[Generic error]** snackbar. Register/login actions: **[Has proper feedback on destination]**.

**E. Offline.** Invite lookup/claim is online-only; offline currently looks like an invalid invite, which can wrongly imply the code is bad.

**F. Animation / transition.** Fade entrance and route transition. Adequate; a distinct loading/error state would add more value than additional motion.

**Phase 2 — Fixed:** fetch exceptions now show a retryable load-error state; invalid/expired copy is reserved for a completed lookup that returns no invite.

## lib/screens/workspace_access_screen.dart

**A. First impression / purpose — 3/5.** Handles no workspace, pending invite, role selection, and access-resolution states in one screen. The logic is capable, but several states make this screen feel like a recovery console rather than a guided next step.

**B. UI issues.** Dense copy and hardcoded English across states. Membership chooser is a bottom sheet and now scrolls, but layout can still feel technical. State-specific titles/actions are important and should remain visually distinct.

**C. UX issues.** “Refresh access”, join invite, create workspace, and sign-in alternatives are available. Users can be unsure whether they need an invite or a new organization. Joining can return to home or scan, making the transition dependent on invitation type.

**D. Error handling.** Workspace refresh: **[Has proper error message]**. Invite validation/join: **[Has field-level/network message]**. Session expired: **[Has sign-in path]**. Push registration is fire-and-forget and failures are not surfaced, but it is not the main access action.

**E. Offline.** Workspace membership and invitation resolution are online-only. Error states offer refresh/sign-in; no cached membership mode is apparent.

**F. Animation / transition.** Animated background, transitions, modal chooser; useful for state changes. Keep reduced-motion behavior and prioritize clear status over effects.

## lib/screens/business_profile_wizard_screen.dart

**Phase 3 — Fixed:** workspace creation is stopped with offline feedback when disconnected; action failures use the shared error SnackBar, and unresolved access copy now explains the workspace exists but access is not ready.

**A. First impression / purpose — 3/5.** Three-step company setup makes workspace creation manageable, but this is a business setup flow, not a generic new-user form.

**B. UI issues.** English copy and custom fields vary from newer shell design. Three-step progress indicator helps; small-screen scrolling and validation are present.

**C. UX issues.** Back/Continue/Create workspace are explicit. The displayed plan name/cycle can imply a purchase/trial path although entitlement creation is fail-closed pending backend work. The screen can tell users the workspace exists while access is still activating, then expects them to refresh.

**D. Error handling.** Step validation: **[Has proper field errors]**. Create/API failure: **[Generic or status-specific SnackBar]**. Token refresh failure after create: **[Has proper but confusing recovery message]**. Push-device sync failure: **[Silent failure]**, but setup continues.

**E. Offline.** Online-only workspace creation. Failure is surfaced; entered form values remain only in widget state and are lost if the flow is abandoned.

**F. Animation / transition.** Animated space background and step transitions/progress. Appropriate for progress, but not essential to animate every form transition.

**Phase 2 — Fixed:** token-refresh failure now explicitly says workspace creation succeeded and directs the user to sign in again to complete setup.

## lib/screens/verification_screen.dart

**A. First impression / purpose — 2/5.** OTP verification UI exists, but source search found no production navigation caller. It is not part of the active registration/login path.

**B. UI issues.** English-only, older visual treatment. OTP component has accessibility/width/paste concerns from earlier audit context, but the route is dormant.

**C. UX issues.** Resend button only restarts a local cooldown and displays “Code sent”; no network resend call is visible. Continue only checks six digits and navigates; no code verification request is present. This is a significant orphan-flow risk if the route is re-enabled.

**D. Error handling.** Resend: **[Misleading success message]** because only a local timer restarts. Continue: **[Not handled at all]** for invalid/server code because no verification request exists.

**E. Offline.** UI works offline but code delivery/verification would require network; no backend request is wired.

**F. Animation / transition.** Timer/countdown and fade entrance. Functional timer is enough; route should not be exposed until real verification is connected.

## Role shells and primary screens

## lib/screens/role_based_shells.dart

**Phase 3 — Fixed:** role shells now show one persistent connectivity banner; Scan tabs are blocked with a clear offline message while disconnected.

**A. First impression / purpose — 4/5.** A consistent bottom navigation shell maps four roles to understandable sections and lazily creates tabs.

**B. UI issues.** Five tabs can compress labels on small phones. English tab labels are localized through the app shell, but selection/role-specific page strings are mixed. Bottom bar is present for detail views hosted inside tabs but not necessarily for pushed full-screen routes.

**C. UX issues.** Route mapping is coherent: Employee Today/Scan/Results/Requests/Account; Manager Today/Scan/Workforce/Requests/Account; HR/Owner Today/Workforce/Requests/Compliance/Reports. Unknown roles receive workspace access instead of a fake home page. Page state is cached in the IndexedStack; switching tabs preserves state.

**D. Error handling.** Shell construction has no user action that can fail. Workspace resolution has error screens upstream. Role mismatch inside Owner/Workforce screen implementations may show a permanent spinner rather than an access error.

**E. Offline.** Shell itself works offline, but its pages fetch remote data. No durable offline dashboard is evident.

**F. Animation / transition.** Tab selection and screen/card transitions are modest. Keep; no additional shell animation needed.

**Phase 2 — Verified:** the mismatch spinner is in `OwnerWorkforceScreen` itself; `RoleShellFactory` does not contain a second matching path.

## lib/screens/employee_home_screen.dart

**Phase 3 — Fixed:** pull-to-refresh and Start scan now warn and stop while offline, preserving already displayed data.

**A. First impression / purpose — 4/5.** Readiness status, Start scan, personal distribution and assigned requests put the employee’s key task first.

**B. UI issues.** New Wellar visual system is consistent. Some mixed hardcoded English remains. Request-load errors collapse to a short text message; the dashboard content is long and scrollable.

**C. UX issues.** Start scan and Open requests are clear. Home data’s `maybeWhen` renders no explicit error state for failed scan/history data, so metric/summary sections can simply disappear. Assigned-request failure copy has no direct retry action in that card.

**D. Error handling.** Profile fetch: **[Generic but visible fallback]**. Assigned requests: **[Generic message, no retry on card]**. Home scan data failure: **[Silent/omitted section]**. Start scan and requests navigation: **[Has proper outcome on destination]**.

**E. Offline.** Cached Riverpod values may survive rebuilds within the process, but no offline mode/cache UX is provided. Failed request content is reduced to text; home metrics may disappear without explanation.

**F. Animation / transition.** Animated screen/cards and skeletons provide hierarchy. Useful on first load; staggered card animation should remain short for frequent daily visits.

## lib/screens/wellness_check_screen.dart

**Phase 3 — Fixed:** the Start readiness action is blocked with offline feedback, while previously captured scan data remains on screen if the network drops before submission.

**A. First impression / purpose — 4/5.** Clear pre-scan explanation of camera, voice, focus and approximate duration.

**B. UI issues.** Attractive specialized scan design, but it differs substantially from the Wellar business dashboard. English-only instructions and a tall page require scrolling before starting.

**C. UX issues.** Start readiness check and Cancel are explicit. Consent is handled in the next flow; surfacing the key camera/microphone requirements before this button would reduce surprise.

**D. Error handling.** Start/Cancel navigation: **[Has proper outcome on destination]**. Capture errors are handled in `scan_flow_impl_normalized.dart`.

**E. Offline.** Intro works offline; scan requires camera/microphone and network services. No offline scan submission is available.

**F. Animation / transition.** Premium scan panels and route transition. Animation supports progression but should not delay the task.

## lib/screens/scan_flow_impl_normalized.dart

**Phase 3 — Fixed:** capture and submission errors use `AppFeedback`; when the connectivity provider reports offline, the message identifies the connection problem.

**A. First impression / purpose — 3/5.** This is the core employee workflow: consent, permission readiness, camera video, audio, focus task, upload/processing. It is the highest-stakes interaction in the daily journey.

**B. UI issues.** Specialized visual design is clear step-by-step, but a long sequence with camera preview, timers, retake, upload, and task state can be cognitively heavy. English copy dominates and should be tested carefully in RTL. Camera/microphone platform behavior requires real-device verification.

**C. UX issues.** Back, retake, video/audio continuation, and submit actions are present. Users must grant multiple permissions and preserve a continuous capture sequence; interruption recovery is limited. “Back to dashboard” can appear in failure states even when the scan began from a request, so users may not realize whether the request remains pending.

**D. Error handling.** Camera/video/audio errors: **[Generic but visible SnackBar/retake state]**. Missing capture data: **[Has retry guidance]**. Prepare/submit failure: **[Generic visible error]**. Background result-resolution failures are mostly logged and retried; terminal timeout becomes a result-screen state. Some cleanup errors are intentionally swallowed during disposal and are not user actions.

**E. Offline.** Cannot complete offline because media upload and processing are server-backed. Permission and local capture steps may work briefly, but there is no explicit offline queue; the user risks repeating the scan after upload failure.

**F. Animation / transition.** Capture progress, timers, focus task and processing state use motion as feedback. This is appropriate; reduced-motion support and clear stable states matter more than adding further effects.

## lib/screens/history_screen.dart

**A. First impression / purpose — 4/5.** Personal scan history is chronological and opens the full result.

**B. UI issues.** Modern shell style and grouped cards are consistent. Some literal English (“No scans yet”) remains. Result details can expose many technical metrics; the summary should stay prominent.

**C. UX issues.** Retry, pull-to-refresh and tap-to-details are clear. Empty state gives a route back to scanning only indirectly through the Scan tab.

**D. Error handling.** History fetch: **[Has role/network-specific generic error and Retry]**. Detail navigation: **[Has loading/error handling on destination]**.

**E. Offline.** Remote timeline required; no explicit offline cache. Proper error/retry UI exists.

**F. Animation / transition.** Animated cards on entry; restrained and useful for long list hierarchy.

## lib/screens/employee_requests_screen.dart

**A. First impression / purpose — 4/5.** Assigned requests are filterable and make the assigned scan action explicit.

**B. UI issues.** Clear card hierarchy but hardcoded English subtitle. Filter chips and cards can make a long queue feel dense.

**C. UX issues.** All/Pending/Completed/Overdue filters, Start scan, and View details are clear. Search is not provided, which is acceptable for an employee’s personal list.

**D. Error handling.** Request load: **[Generic visible error and Retry]**. Start scan: **[Has destination error handling]**. Details: **[Has loading/retry state]**.

**E. Offline.** Request list is online-only; loading and retry/error states are provided, no cached offline queue is evident.

**F. Animation / transition.** Cards animate in with stagger. Fine for initial load; may become slow/noisy for large lists.

## lib/screens/manager_home_screen.dart

**Phase 3 — Fixed:** pull-to-refresh, snapshot Retry, and Start scan now warn and stop while offline, preserving displayed data.

**A. First impression / purpose — 4/5.** Team overview and action cards surface workforce, requests, scans, and alerts.

**B. UI issues.** New visual system is coherent. Profile errors use a mild fallback, but some labels remain English. Metrics can show unavailable placeholders rather than a full page failure.

**C. UX issues.** Today, Scan, Workforce, Requests, and Account tabs align with role. Shortcut cards for scan/history/request are useful. Some card labels rely on the user understanding the difference between personal readiness and team queue.

**D. Error handling.** Snapshot: **[Has visible unavailable state and Retry]**. Profile: **[Generic fallback]**. Navigation actions: **[Has outcome on destination]**.

**E. Offline.** Dashboard data is remote; snapshot error state offers Retry. No persisted offline team dashboard.

**F. Animation / transition.** Cards and shell transitions use short motion/skeleton loading. Appropriate for glanceable metrics.

## lib/screens/manager_team_screen.dart

**A. First impression / purpose — 4/5.** Workforce search and filters support manager triage.

**B. UI issues.** Consistent Wellar cards, but role/status filters and member details are compact. English labels remain.

**C. UX issues.** Search, role/status/missing-check/attention filters, and member cards are straightforward. Empty state explains that members appear here.

**D. Error handling.** Team fetch: **[Has error state and Retry]**; 403 has a distinct access message. Search/filter are local and do not fail.

**E. Offline.** Online directory only; no offline cache. Clear error state.

**F. Animation / transition.** Staggered card entry. Useful once; avoid replaying on every filter change if it becomes distracting.

## lib/screens/manager_scan_requests_screen.dart

**A. First impression / purpose — 4/5.** Team requests distinguish personal assignments from team-wide items and link to a scan.

**B. UI issues.** Cards are information dense; English subtitles remain. Local filter chips are clear.

**C. UX issues.** “Start self readiness scan” is separate from assigned work. Only assigned actionable requests can start a scan; disabled state is safer but should explain why on the card.

**D. Error handling.** Request fetch: **[Has role-specific or generic error and Retry]**. Start/detail routes: **[Has destination error handling]**.

**E. Offline.** Online request data and scan workflow; no offline queue. Refresh/retry state exists.

**F. Animation / transition.** Animated cards and route transitions; reasonable for request list.

## lib/screens/hr_home_screen.dart

**Phase 3 — Fixed:** pull-to-refresh, snapshot Retry, and Start scan now warn and stop while offline, preserving displayed data.

**A. First impression / purpose — 4/5.** HR sees workforce readiness, open alerts, request shortcuts, and distribution summaries.

**B. UI issues.** Metrics are clear, but screen mixes Wellar card system with several hardcoded English labels. Long dashboard requires scrolling.

**C. UX issues.** Home links to HR requests, scan, history, and reports. It is not obvious that Requests tab is a different admin scan-request queue than the HR request shortcut.

**D. Error handling.** Snapshot: **[Has visible unavailable state and Retry]**. Profile: **[Fallback message]**. Refresh reloads related providers. Request/scan shortcuts: **[Destination handles errors]**.

**E. Offline.** Remote dashboard only; snapshot errors are visible and retryable. No durable cache.

**F. Animation / transition.** Animated Wellar cards and shimmer. Appropriate for dashboard loading.

## lib/screens/requests_screen.dart

**Phase 3 — Fixed:** refresh and Retry do not invalidate the existing request data while offline; they show the shared offline warning instead.

**Route status:** Reachable from the Employee Today screen's “Open requests” shortcut; distinct from the Employee Requests tab, which uses `EmployeeRequestsScreen`.

**A. First impression / purpose — 3/5.** This is an assigned-readiness-request list with status filters and scan entry. The purpose is clear, though a second employee request list makes the navigation model harder to predict.

**B. UI issues.** Wellar cards and loading/error states match the newer design system. The subtitle is hardcoded English, and filter labels/selection state should be checked in Arabic and at large text sizes.

**C. UX issues.** Status chips filter locally and refresh is available. Users may not understand why this list differs from the Requests tab; consolidate them or label the distinction clearly.

**D. Error handling.** Provider load: **[Has error state and Retry]**. Pull-to-refresh invalidates incoming requests but does not await a completed fetch. Opening a request depends on the detail/scan flow's states.

**E. Offline.** Requires remote request data; there is no cached list or offline scan submission queue. The error state is preferable to a blank screen.

**F. Animation / transition.** Screen/card entry animation and route transitions provide useful feedback; no additional motion is needed.

**Phase 2 — Fixed:** pull-to-refresh now waits for the invalidated incoming-requests provider to finish loading.

## lib/screens/hr_requests_screen.dart

**Phase 3 — Fixed:** create-request submission is blocked with offline feedback while disconnected; Phase 2’s typed cancellation errors retain shared feedback styling.

**A. First impression / purpose — 3/5.** HR’s request-management screen supports request creation and cancellation; it is reachable from an HR home shortcut, not the primary Requests tab.

**B. UI issues.** Dense request list and creation form; copy and errors are mostly English. Date/status controls need adequate tap targets on mobile.

**C. UX issues.** Create/cancel actions are present, but HR must understand how this differs from the Admin Scan Requests tab. This duplicate mental model is the main flow issue.

**D. Error handling.** Create/cancel: **[Has request-specific/generic SnackBar]**. Several fallback catches use generic copy. Validation errors are visible in the form.

**E. Offline.** Requests require network; action failures are surfaced. No offline draft for a partially composed request is apparent.

**F. Animation / transition.** Modal/form feedback and route transitions; adequate.

**Phase 2 — Verified:** create and cancel handlers already display typed service exception messages; generic copy remains only for untyped failures with no specific service message.

## lib/screens/hr_workforce_screen.dart

**A. First impression / purpose — 4/5.** Provides a directory with name/email search, role filters, department filters and workforce cards.

**B. UI issues.** Compact filters and department dropdown can be difficult on narrow widths; hardcoded English remains.

**C. UX issues.** Search and filters are local and clear. The role mismatch guard shows an error/retry; that is a useful defensive state.

**D. Error handling.** Directory fetch: **[Has unavailable state and Retry]**. HR 403: **[Generic access message]**. Filters: **[No remote failure]**.

**E. Offline.** Directory is online-only; error/retry exists. No cached member directory is shown.

**F. Animation / transition.** Animated cards; useful on entry, less useful for filter changes.

**Phase 2 — Fixed:** stale-role access now uses the same `WellarErrorState` treatment as the HR workforce guard.

## lib/screens/owner_workforce_screen.dart

**A. First impression / purpose — 4/5.** Owner workforce directory supports name/email search, role and department filters, and member cards.

**B. UI issues.** Similar to HR workforce, with compact filter controls and a separate owner design system; English copy is mixed in.

**C. UX issues.** Search and filters are clear. Its wrong-role guard returns a loading spinner rather than an access/retry state, so a retained stale page can look stuck.

**D. Error handling.** Directory fetch: **[Has unavailable state and Retry]**. Wrong-role branch: **[Not handled at all beyond spinner]**. Local filters: **[No remote failure]**.

**E. Offline.** Online directory only; error/retry exists. No cached directory is shown.

**F. Animation / transition.** Animated cards; useful on entry, less useful for filter changes.

## lib/screens/owner_hr_ops_screen.dart

**A. First impression / purpose — 4/5.** This is the active shell wrapper for Owner/HR Workforce and Compliance tabs; it selects the role-specific child screen and adds the shared background treatment.

**B. UI issues.** The wrapper itself is visually neutral. The selected child screens retain some differences in spacing and hardcoded English, so role variants do not feel entirely unified.

**C. UX issues.** The active shell lands on the intended workforce/compliance child. This wrapper has no title of its own, which is appropriate inside the shell but would be confusing if routed independently.

**D. Error handling.** It performs no network action itself; the selected child owns loading/error behavior.

**E. Offline.** The children use remote operational data and do not provide a useful cached offline view.

**F. Animation / transition.** Shared background entrance animation; subtle and adequate for a tab page.

## lib/screens/hr_compliance_screen.dart

**A. First impression / purpose — 3/5.** HR compliance summaries show request completion/readiness metrics and shortcuts.

**B. UI issues.** Many summary cards and range controls create visual density. Copy uses mixed translated and hardcoded labels; owner and HR styling is not fully unified.

**C. UX issues.** Range selectors and request shortcuts work. Partial-data states are not clear: multiple service failures are caught and converted to empty arrays/zero counts, so zeros can look like actual results.

**D. Error handling.** Primary request fetch: **[Has visible error and Retry]**. Secondary snapshots, departments, alerts/readiness: **[Silent failure / misleading zero or empty data]** in caught branches. Navigation shortcuts: **[Destination handles errors]**.

**E. Offline.** Online-only metrics. A failed primary request fetch is visible; failures of supporting services can quietly present incomplete data as a complete summary.

**F. Animation / transition.** Cards and range selectors use light transitions. Fine; better partial-data badges would add more value than extra motion.

## lib/screens/owner_company_screen.dart

**A. First impression / purpose — 3/5.** Owner compliance and operational summary with date ranges and request shortcuts.

**B. UI issues.** Summary cards and range controls make the screen dense. Copy mixes translation keys and hardcoded English; styling differs slightly from HR compliance.

**C. UX issues.** Range and request navigation are direct. Some supporting-data failures become empty/zero summaries, so the page can look successful while incomplete.

**D. Error handling.** Primary data failure: **[Has visible retry]**. Supporting readiness/member/alert failures: **[Silent failure / potentially misleading empty state]**. Navigation: **[Destination handles errors]**.

**E. Offline.** Online-only metrics; primary failure is visible, partial failures may not be.

**F. Animation / transition.** Light card transitions; appropriate.

## lib/screens/admin_scan_requests_screen.dart

**Phase 3 — Fixed:** opening/submitting the create-request form is blocked with offline feedback while disconnected.

**A. First impression / purpose — 4/5.** Owner/HR request queue supports review, creation and scan-request detail. The active role router uses this for the Requests tab.

**B. UI issues.** Many states/actions in one screen (filters, creation dialog, assignment, due dates) make it dense. On smaller devices the create form/dialog needs careful keyboard/large-text testing. Mixed hardcoded English remains.

**C. UX issues.** Create request and open details are findable. Status/assignment actions can have significant consequences, so confirmation and post-action status should stay prominent.

**D. Error handling.** Queue load: **[Has error state and Retry]**. Create/assignment actions: **[Has visible error feedback]** in catches. Form validation disables submit until valid; modal cancel/back is available.

**E. Offline.** Queue and mutations require network. Loading, retry and empty states exist; there is no offline draft/submission queue.

**F. Animation / transition.** Animated cards/dialog padding. These support state changes; keep transitions short in an operations workflow.

## lib/screens/owner_home_screen.dart

**Phase 3 — Fixed:** pull-to-refresh, dashboard Retry actions, and Start scan now warn and stop while offline, preserving displayed data.

**A. First impression / purpose — 3/5.** Owner dashboard prioritizes workspace metrics, alerts, self scan, results and history. It is information-rich but has multiple competing “priority”, summary, and action sections.

**B. UI issues.** Owner design system is distinct from employee/manager Wellar cards. Inconsistent labels and mixed hardcoded/translated English are visible. Header has brand/workspace, bell and account actions.

**C. UX issues.** Bell, profile, alert summary, send request, self scan and history are clear. Critical issue: when `_future` errors, major metric/priority areas continue rendering spinners because `data == null`; only the recent activity section shows a retry state. The page can therefore look partly stuck instead of clearly failed.

**D. Error handling.** Snapshot error: **[Partial error message]** in activity only; dashboard metrics/priority: **[Not handled at all beyond persistent spinner]**. Alert/readiness counts can also fall back to stale/zero values. Navigation actions: **[Destination handles errors]**.

**E. Offline.** Remote owner metrics, alerts and readiness; no offline cache. A failed snapshot leaves persistent loading placeholders in prominent areas.

**F. Animation / transition.** Animated dashboard cards and chart transitions; appropriate, but should not mask unresolved loading states.

## lib/screens/owner_reports_screen.dart

**A. First impression / purpose — 4/5.** Reports provides required/completed/pending/overdue/alerts/readiness with drilldowns.

**B. UI issues.** Clear metric grouping, but the disabled Export Coming Soon button is prominent and makes the section feel unfinished. Dense dashboards can compress on phones.

**C. UX issues.** Range filters and metric-card drilldowns are straightforward. “Export” is shown but disabled; this is transparent yet still a dead-end expectation. Reports receives a role override from the shell.

**D. Error handling.** Required requests failure: **[Has retry state]**. Alerts and readiness failures: **[Silent failure]** converted to empty alerts or zero/failed readiness summary, with partial-data flags not consistently surfaced. Export: **[Disabled with Coming Soon label]**.

**E. Offline.** Online-only reporting. Primary request failure is visible; supporting failures can make counts incomplete without a clear offline banner.

**F. Animation / transition.** Animated shell/cards and drilldown route transitions. Helpful for reading hierarchy; no additional motion needed.

## lib/screens/profile_screen.dart

**Phase 3 — Fixed:** account-deletion launch and remote-logout warnings now use the shared error feedback styling.

**A. First impression / purpose — 4/5.** Profile consolidates identity, role, workspace, privacy, organization switching, logout, and delete account.

**B. UI issues.** New Wellar style and card layout are consistent. Profile/workspace copy is partly localized and partly hardcoded; labels such as status can overstate freshness when profile fetch fails.

**C. UX issues.** Logout confirmation is clear. “Switch organization” opens an informational notice rather than an actual switch flow, which does not fulfill its button label. Delete account correctly explains an external secure page.

**D. Error handling.** Profile fetch: **[Generic fallback message]**. Logout: **[Silent failure]** for server/device unregister errors; local session is still cleared and user is routed to Login. Switch organization: **[No operation; notice only]**. Delete page launch: **[Has error message]**; unconfigured URL: **[Has clear unavailable message]**.

**E. Offline.** Identity may fall back to session data; workspace-switch data requires network. Logout can clear local session offline, while server token revocation failures are hidden.

**F. Animation / transition.** Animated cards and confirmation dialogs. Good feedback for account actions; no extra animation needed.

## lib/screens/notifications_screen.dart

**Phase 3 — Fixed:** failed notification/alert actions and linked-result lookup errors use shared feedback; notification read and alert mutations are blocked while offline.

**A. First impression / purpose — 4/5.** Notification and alert tabs, filters, mark-all-read, invitations and linked objects support operational follow-up.

**B. UI issues.** Cards may be dense and English copy is mixed with localized labels. Alerts are role-gated. Notification types do not always explain why a destination could not be opened.

**C. UX issues.** Pull-to-refresh, mark all read, read-on-open, alert details, invitation acceptance, and linked request/result navigation are available. `linkType` drives routes; unknown types fall back to a SnackBar. The same screen acts as both notifications and alerts, increasing complexity.

**D. Error handling.** Notification/alert list: **[Has visible error and Retry]**. Mark all read: **[Has localized error and optimistic rollback]**. Mark one read: **[Has localized error and rollback]**. Mark alert seen: false result **[Has error message]**, thrown network exception **[Not handled at all]**. Unknown result target: **[Generic fallback SnackBar]**. Result lookup exceptions are swallowed before fallback copy.

**E. Offline.** Lists and server read-state require network. No explicit offline mode; mutation failures roll back optimistic state and show feedback except thrown alert-close errors.

**F. Animation / transition.** Animated cards, state changes and route transitions. Useful for read/alert state; keep accessible reduced-motion behavior.

## lib/screens/scan_details_screen.dart

**A. First impression / purpose — 4/5.** Result summary, status explanation, recommended action and supporting signals provide a clear post-scan destination.

**B. UI issues.** Technical details can be long and dense; summary/status are strong. Hardcoded English and specialized scan colors differ from dashboard styling.

**C. UX issues.** Retake and return actions are clear. Loading/polling can take time; completion has a timeout screen, but users may not know whether the scan is still processing or should be retried.

**D. Error handling.** Result loading: **[Has connection/timeout state and retry/retake path]**. Retake: **[Has scan flow error handling]**. Certain fallback lookup exceptions are swallowed but followed by continued polling or timeout feedback.

**E. Offline.** Result is server-backed and cannot be fetched offline unless already in memory. Timeout and connection message are visible; no offline result cache is guaranteed.

**F. Animation / transition.** Reveal/section transitions and polling states support result comprehension. Appropriate if motion respects reduced-motion settings.

## lib/screens/request_details_screen.dart

**A. First impression / purpose — 3/5.** Detail view shows an assigned request and can navigate to its scan/result.

**B. UI issues.** Older card style and error/empty states are comparatively generic. Long request metadata should maintain clear title/status order.

**C. UX issues.** Back and Retry are available. A null request appears as a generic empty state, which can be confusing if the ID was valid but the connection failed.

**D. Error handling.** Fetch: **[Has generic error and Retry]**. Some result/scan lookup exceptions are caught without feedback; user may see no result link even when the lookup failed: **[Silent failure]**. Back: **[Has navigation outcome]**.

**E. Offline.** Online detail fetch; loading/error states exist. No cached request detail is guaranteed.

**F. Animation / transition.** Basic loading state and route transition. Static is fine.

## lib/screens/scan_request_details_screen.dart

**A. First impression / purpose — 3/5.** Shows a scan-request summary and distinguishes actions from read-only details.

**B. UI issues.** Status and owner/team context can be compact. Mixed English remains.

**C. UX issues.** Details and Start scan are explicit when eligible. Disabled/secondary actions need explanatory copy so users know why they cannot act.

**D. Error handling.** Start scan: **[Has destination error handling]**. Details are passed in as an object rather than fetched here, so stale/missing data is not refreshed on this screen.

**E. Offline.** Screen can render passed-in data offline, but starting/completing a scan requires network.

**F. Animation / transition.** Simple route transition. No additional animation needed.

## lib/screens/scan_request_open_screen.dart

**A. First impression / purpose — 3/5.** This notification deep-link resolver finds an assigned scan request, checks whether it is still actionable, then opens its detail screen. It is a functional bridge rather than a full destination page.

**B. UI issues.** Loading is a centered spinner and blocked states use a compact legacy-style card. Copy is English-only, but the blocked reason is explicit.

**C. UX issues.** Invalid, completed, unassigned, or unavailable requests get Retry and Open Requests actions. Successful resolution immediately replaces this route with request details, which is efficient but provides no loading context beyond the spinner.

**D. Error handling.** Request/workspace fetch exception: **[Has generic error and Retry]**. Null/invalid/completed request: **[Has specific explanation]**. Open Requests and Back: **[Has navigation outcome]**.

**E. Offline.** Requires request and workspace data from services. Offline fetch errors reach a blocked/retry state; the request cannot be started offline.

**F. Animation / transition.** Uses shared screen and route transitions; adequate for this short routing state.

## lib/screens/alert_detail_screen.dart

**A. First impression / purpose — 3/5.** Alert details connect a readiness event to scan context and follow-up controls.

**B. UI issues.** Dense metrics and technical signal fields can overwhelm a manager; English-only labels and older styling are inconsistent.

**C. UX issues.** Back and follow-up navigation exist. The useful user question is “what should I do next?”; keep the recommended action more prominent than raw metrics.

**D. Error handling.** Related scan fetch uses `FutureBuilder`; errors/null may yield a limited detail view. Action callbacks should be verified against service outcomes; no consistent retry state is evident in all paths.

**E. Offline.** Alert object can render, linked scan data is online. Missing scan data may be partial without a strong offline message.

**F. Animation / transition.** Minimal; static detail is appropriate.

## lib/screens/company_readiness_results_screen.dart

**A. First impression / purpose — 4/5.** Owner/HR can review workspace readiness history and drill into individual scans.

**B. UI issues.** Large table/list of readiness records, filters and summaries are information-heavy. On narrow screens, horizontal comparison and details can be hard to scan.

**C. UX issues.** Retry, range/filter changes and row-to-scan navigation are available. Export/permission actions depend on role/configuration and should explain disabled states.

**D. Error handling.** Main fetch: **[Has retry state]**. Export/file open: permission/file errors are converted to user messages in many paths; some catches silently fall back to empty/alternate data. **[Generic error]** for unsupported/permission failures.

**E. Offline.** Requires remote readiness data and file export; no durable cache is apparent. Main load error is visible.

**F. Animation / transition.** Table/card transitions and drilldowns. Use motion sparingly in a dense reporting surface.

## lib/screens/report_metric_detail_screen.dart

**A. First impression / purpose — 3/5.** A focused drilldown from report metrics with a back action and row-specific action.

**B. UI issues.** Useful but can be sparse for empty metrics. Export is visibly disabled and labeled as coming soon.

**C. UX issues.** The summary context should make clear which report range/category the user drilled into. Empty-state action may route to the associated request/scan.

**D. Error handling.** Most content is passed in, so no remote load. Disabled Export: **[Disabled, transparent]**. Row actions delegate to the supplied callback; failures depend on destination.

**E. Offline.** Passed-in data renders offline; destination actions may be online-only.

**F. Animation / transition.** Route transition only is sufficient.

## lib/screens/organization_invitation_screen.dart

**Phase 3 — Fixed:** invitation accept/decline actions are blocked with offline feedback when disconnected.

**A. First impression / purpose — 3/5.** Accept/decline invitation screen has clear choice and confirmation for decline.

**B. UI issues.** Some labels and messages are English-only; invitation details should make invited workspace and role easy to confirm before accepting.

**C. UX issues.** Accept/decline are direct; decline confirmation prevents accidental rejection. Result returns to notifications for a status message.

**D. Error handling.** Accept/decline: **[Has service error message]** in catch handlers. Dialog Cancel/Confirm: **[Has clear outcome]**.

**E. Offline.** Invitation mutation requires network; failures are visible and retry is possible by returning to the invitation.

**F. Animation / transition.** Dialog/route transitions. Appropriate.

## lib/screens/business_members_manage_screen.dart

**A. First impression / purpose — 3/5.** It shows the current membership and provides add/update by registered email. It is reachable through `CompanyDashboardScreen`, which is not linked from the active role shell discovered here.

**B. UI issues.** Older visual system, compact table and English copy. The registered-user-only limitation is now stated. Form success collapses the form; users can reopen it.

**C. UX issues.** Email/role/save path is now wired. Unknown users cannot be invited from here, which limits what “Add / Update Member” means. Team page also states “Showing your account only” in its header, making its purpose feel incomplete.

**D. Error handling.** Member load: **[Has visible error and Retry]**. Save/validation: **[Has inline service/validation error]**. Success: **[Has success SnackBar and refresh]**.

**E. Offline.** Member load/save require network; errors are visible. No offline editing queue.

**F. Animation / transition.** Skeleton and simple form collapse. Enough feedback; no decorative animation required.

### Logout and account secondary actions

Profile is the active Account tab for Employee/Manager and a reachable account destination for Owner/HR. Its identity/workspace summary is useful but partial profile failures fall back quietly. Logout asks for confirmation, then routes to Login and clears local state. Server/device logout errors are swallowed by `AuthService.logout`, so user sees a successful local logout with no indication that remote revocation failed. Delete account has confirmation and explicit external-page failure handling. “Switch organization” currently opens a notice rather than switching.

### Notification and alert destinations

Reached from role-home bells and owner alerts. List errors have retry, read failures roll back and show messages, and linked details route to request/scan/alert screens. Alert close can throw without a catch; unknown result links show a generic fallback. Offline refresh has no specific offline banner.

## lib/screens/business_profile_summary_screen.dart

**A. First impression / purpose — 3/5.** Summarizes a business profile with Back actions; reached from the legacy company dashboard, not from the current role tabs.

**B. UI issues.** Static field/value rows are readable but sparse; errors/empty values can look like missing profile setup.

**C. UX issues.** Back is clear. There is no obvious edit action from the summary itself.

**D. Error handling.** Fetch: **[Inspect destination state]**; the FutureBuilder has loading and null/error handling but no dedicated retry in the reviewed path.

**E. Offline.** Remote profile data required; no cached view guaranteed.

**F. Animation / transition.** Minimal, appropriate.

## lib/screens/pricing_screen.dart

**A. First impression / purpose — 2/5.** Plan comparison has a clear catalog presentation but the purchase action is intentionally unavailable until payment backend work exists. Its route is only exposed through legacy/unreferenced entry points found in this code review.

**B. UI issues.** Hardcoded pricing fallback has already been removed; empty catalog has an unavailable state. Some plan descriptions/features are dense.

**C. UX issues.** Billing cycle and Manage are clear. Subscribe/Start trial leads only to an unavailable SnackBar, so actionable purchase controls do not fulfill their label.

**D. Error handling.** Catalog fetch: **[Has Retry/unavailable state]**. Plan action: **[Has explicit unavailable message]**. Manage route: **[Has navigation outcome]**.

**E. Offline.** Catalog is remote; empty/error state is visible. No offline purchase.

**F. Animation / transition.** Plan card transitions only. Static comparison is appropriate.

## lib/screens/subscription_management_screen.dart

**A. First impression / purpose — 2/5.** Shows current plan/status and management actions, but the page is only reachable via Pricing’s Manage path and is currently effectively orphaned from the active role shell.

**B. UI issues.** Status and renewal details are readable, but unavailable actions can dominate the screen.

**C. UX issues.** Upgrade/Renew/Cancel buttons imply operations the client deliberately blocks pending payment backend. This is fail-closed but a poor live UX until buttons are replaced with clear unavailable/support guidance.

**D. Error handling.** Subscription load: **[Has Retry/empty state]**. Upgrade/Renew/Cancel: **[Generic visible failure SnackBar]** because service methods throw unavailable errors; this review does not recommend changing subscription logic.

**E. Offline.** Needs remote subscription data; no offline management. Failure is visible.

**F. Animation / transition.** Simple list/dialog transitions; static is fine.

## lib/screens/subscription_paywall_screen.dart

This screen is not reached from active role-shell routes found in this pass. It links into Pricing, whose purchase entry is blocked. No payment flow is changed or endorsed in this review. **D.** Navigation: **[Has route outcome]**; checkout is not performed here. **E.** Requires the downstream plan catalog. **F.** Static paywall layout is adequate.

## lib/screens/subscription_success_screen.dart

This screen is not reached from active role-shell routes found in this pass. It presents a success state and links to management/member destinations; it must only be reachable after a verified backend purchase. No payment flow is changed or endorsed in this review. **D.** Navigation: **[Has route outcome]**. **E.** Uses passed-in subscription data. **F.** Success animation is appropriate only after a verified success.

## Secondary screens reachable only through legacy/orphan routes

These files exist and contain UX but were not found in the active `RoleShellFactory` page list or a current route from its home pages. They should not be counted as normal user paths until a caller is restored.

## lib/screens/home/home_screen.dart

This older tab shell is not instantiated by the active app route. It should not be mistaken for the active employee home. Its profile route works, but old notification and request navigation belong to an inactive shell.

## lib/screens/home/home_dashboard.dart

Not used by the active role shell. Its dashboard links to Insights, Analytics, Activity, Export, and Company Dashboard, making those features appear available in code but not in current role navigation.

## lib/screens/insights_screen.dart

Legacy route from `home_dashboard.dart`, not active role tabs. Good summary cards and empty state. Retry invalidates home data; pull-to-refresh also invalidates and awaits refresh. Load failure is visible. Online-only data; fade/card animation is acceptable.

## lib/screens/analytics_screen.dart

Legacy route from `home_dashboard.dart`/Company Dashboard, not active role tabs. Dense chart/filter interface and export/upgrade CTAs. Retry is available for provider errors; network-backed datasets have no durable offline mode. Some sections can degrade independently, so users need visible partial-data labeling. Chart animation is useful only when it clarifies change.

## lib/screens/activity_screen.dart

Legacy route from `home_dashboard.dart`, not active role tabs. Filters and empty state are clear; data error has Retry. Pull-to-refresh reloads. Online-only events; static list with small transitions is suitable.

## lib/screens/export_screen.dart

Legacy route from old dashboard/report surfaces, not an active tab. Export form has format/template/range filters and request action. Permission, unauthenticated, file-open, and generic failures have distinct or generic feedback. It requires network and device file access; export cannot be used offline. Preview/selection feedback is present; no extra animation needed.

## lib/screens/company_dashboard_screen.dart

Legacy business dashboard; no active role-shell route found. It combines company summary, profile, member management, analytics, export and requests, duplicating newer Today/Workforce/Reports destinations. Multiple supporting-data exceptions are swallowed and converted into empty values; main access retry exists. Offline summary is not available. It is the largest source of route duplication and should either be restored intentionally or removed from product navigation.

## lib/screens/owner_more_screen.dart

No active shell caller was found. It offers Reports, Compliance, Notifications and Profile shortcuts that duplicate active role tabs/header actions. If re-enabled, it needs a clearer purpose; these routes already exist elsewhere.

## lib/screens/owner_scan_history_screen.dart

No caller from the active role shell or current home routes was found. It is an older owner scan-history browser that links to scan details. It uses remote history data, so it needs a visible load-error state and has no offline cache; its legacy styling should be reviewed before restoring it.

## lib/screens/auth_welcome_screen.dart

No caller from active launch/auth navigation was found. It is a generic welcome interstitial that pushes a supplied next screen; if restored, verify it does not add an unnecessary step between the branded splash/public entry and authentication.

## lib/screens/owner_requests_screen.dart

Not the owner Requests tab destination in the active shell (that is `AdminScanRequestsScreen`). It is an older alternate request list. Load/actions use remote services; request mutation errors are generally surfaced generically. **E.** No offline queue. **F.** Legacy card transitions.

**Phase 2 — Skipped:** source search confirms no active caller; the audit marks this alternate screen legacy.

## lib/screens/manager_requests_screen.dart

Not the Manager Requests tab destination in the active shell (that is `ManagerScanRequestsScreen`). It is an older alternate manager request path. Cancellation and fallback errors are generally surfaced generically; one fallback catch is quiet. **E.** Remote-only. **F.** Legacy card/dialog transitions.

## lib/screens/home/requests_view.dart

Part of the unmounted legacy home implementation, not the active role shell. It provides request actions but its network error fallback is generic. **E.** Remote-only. **F.** Inherits animation from the old home screen.

## lib/screens/home/history_view.dart

Part of the unmounted legacy home implementation. It shows scan history and opens scan details, but is not the active Employee Results tab (`HistoryScreen`). Remote history requires connectivity; failed or absent results should not be treated as a durable offline history.

## lib/screens/home/create_request_view.dart

Part of the unmounted legacy home implementation. Local form validation and request-specific errors exist; several helper catches are silent before the submit path, so intermediate lookups can fail without a dedicated message. **E.** Cannot create offline. **F.** Modal/form transitions.

## lib/screens/home/audit_logs_view.dart

Part of the unmounted legacy home implementation, not in the active role tabs. Its submit/reply handlers have visible error handling in their main paths. **E.** Remote-only logs. **F.** Modal details and reply-state feedback.

## lib/screens/mobile_auth_screen.dart

No caller from active launch or role routes was found. It links phone/email entry to the dormant OTP screen. Local validation is visible, but delivery is not performed before navigation. **Offline:** local form only. **Animation:** fade and background.

## lib/screens/public_home_screen.dart

No active caller from launch/role routes found. It routes to Login and AuthIntent, whereas the active launch uses PublicEntry. This is a duplicate public entry surface. **D.** Navigation: **[Has route outcome]**. **E.** Static screen works offline. **F.** Route transition only.

## lib/screens/home/permission_view.dart

No active caller from launch/role routes found. Its refresh and Got it callbacks are no-ops, but cannot currently be reached by a user. **D.** Both controls: **[Silent failure if invoked]**. **E.** Static. **F.** No animation.

## lib/screens/push_diagnostics_screen.dart

Debug-only diagnostics for push registration. No actual caller from `ProfileScreen` was found, despite the screen's own copy claiming a Profile developer-section route. If manually routed in a debug build, Refresh reports registration state; failures should be checked in its service result. **E.** Requires push/network state. **F.** Static diagnostics are appropriate.

### `lib/screens/verification_screen.dart` and `lib/widgets/otp_input.dart` (dormant OTP component)

OTP route has no production caller. It currently has a local resend timer without a resend service call and a Continue path that only checks code length before routing; do not expose it as verification until a backend check exists. Offline behavior is not supported. Timer animation is functional, but the flow is incomplete.

Used only by the dormant verification screen in the current source graph. Digit entry and paste/width behavior require runtime testing if that route is restored; it is not part of the active login/register flow.

## Executive Summary

### 1. Is the first launch screen production-appropriate?

The current first screen is a **reasonable branded splash**, not a full onboarding page. It already skips ahead for an existing session and sends signed-out users to the public entry screen, which is the right production pattern. It does **not** need a completely different approach or a long animated intro. It does need one serious reliability fix: unexpected startup exceptions are logged without switching to the error/retry state, so some failures can leave the user staring at a spinner. Brand polish (logo mark and consistent Arabic localization) is secondary.

### 2. Top five screens needing UX work, ranked by user impact

1. **`lib/screens/scan_flow_impl_normalized.dart`** — Most frequent high-consequence workflow; camera/microphone permissions, multi-step capture, interruption recovery and server submission need device-level usability testing.
2. **`lib/screens/workspace_access_screen.dart`** — Users blocked at workspace resolution need a clearer single next step; invite/create/join/session states are crowded.
3. **`lib/screens/employee_home_screen.dart`** — Daily start screen can silently omit data sections when providers fail and gives no in-card retry for assigned requests.
4. **`lib/screens/owner_home_screen.dart`** — Prominent metric areas can spin forever on snapshot failure even while a lower section exposes Retry.
5. **`lib/screens/notifications_screen.dart`** — Central action center has multiple destinations and one thrown alert-update path without feedback; it is important for timely operational response.

### 3. Buttons/actions with no user-facing error message (silent or unhandled)

- Splash startup: unexpected non-timeout/non-Firebase exception is only logged; screen remains in loading state.
  - **Phase 1 — Fixed:** generic and nested startup failures now use the existing splash Retry state.
- Registration Terms and Privacy links: failed URL launch has no visible feedback.
  - **Phase 1 — Fixed:** false URL-launch results and thrown launch errors show a localized SnackBar.
- Business profile wizard push-device registration: failure is swallowed while workspace setup proceeds (non-blocking side effect).
- HR and Owner compliance summaries: failures from supporting snapshots, member/department/alert/readiness requests are caught and presented as empty/zero data, without a partial-data warning.
  - **Phase 1 — Fixed:** HR compliance and Owner reports now show a partial-data banner only when supporting requests fail. `OwnerCompanyScreen` uses `Future.wait` and already shows its full error/Retry state if a request fails, so it was not changed.
- Owner reports: alerts fetch failure becomes an empty alert list; readiness failure becomes a zero/failed summary without a consistent partial-data banner.
  - **Phase 1 — Fixed:** alert/readiness failures are tracked and shown in the same partial-data banner.
- Owner home: snapshot failure leaves the metrics and priority sections in permanent loading placeholders; only the lower activity section exposes retry.
  - **Phase 1 — Fixed:** snapshot errors now show the existing Retry state in metrics, priority, and readiness sections.
- Notifications: `markAlertClosed` thrown exception in `_markAlertSeen` is not caught; only a false return gets a SnackBar.
  - **Phase 1 — Fixed:** thrown errors now use the same failure SnackBar as a false result.
- Profile logout: device unregister, server logout, Google sign-out, and Firebase sign-out failures are swallowed; local logout still proceeds without telling the user remote revocation failed.
  - **Phase 1 — Fixed:** local logout and navigation continue; bounded remote steps report whether any failed, then Login shows a non-blocking message.
- Legacy `CompanyDashboardScreen`: several supporting-data errors are swallowed and converted to empty values.
- Legacy request/scan detail lookups: some caught lookup failures result in absent detail/link rather than an error message.
- Dormant OTP verification: Continue does not call a verification backend; the route is currently unreachable, but would be unsafe/confusing if exposed.

### 4. Overall app maturity

| Area | Score | Rationale |
|---|---:|---|
| Visual Design | **7/10** | New Wellar screens are polished and readable, but older dark/glass/scan design systems and English-only copy still coexist. |
| UX Flow | **6/10** | Role tabs and the main scan/request paths are understandable, but launch alternatives, legacy routes, workspace recovery, and disabled subscription/export actions create inconsistent expectations. |
| Error Handling | **6/10** | Many primary operations have retry/error states, but silent partial-data fallbacks, the splash generic-exception path, and alert/logout exceptions weaken trust. |
| Offline Handling | **3/10** | Most core screens depend on remote data and there is no clear app-wide offline state or durable cached workflow; some screens show retry, while others silently omit or misclassify data. |

## Phase 3 — Connectivity and error feedback

Connectivity awareness is provided by `connectivity_plus` through `connectivityStatusProvider` in `lib/state/app_providers.dart`. `WellarAppShell` renders one minimal persistent banner for role-shell screens. Existing in-memory page data is not invalidated when connectivity changes. Offline warning/blocking was added to role-shell Scan tabs, all role Home refresh/retry actions and direct Start scan actions, the wellness-check entry and scan submission, login/Google sign-in, registration, workspace creation, HR/Owner request creation, notification read/alert mutations, and invitation accept/decline. Other operations remain online-only and rely on their existing service error UI; durable offline use is out of scope.

`connectivity_plus` reports available network transports and does not prove Internet reachability (for example, a connected Wi-Fi hotspot may have no Internet). Request failures therefore remain handled by their existing error paths. See [connectivity_plus documentation](https://pub.dev/packages/connectivity_plus/versions/6.1.5).

**Phase 3 — Part B screens swept:** active route-map screens were searched for SnackBars, silent catches, and generic error fallbacks: `splash_screen.dart`, `public_entry_screen.dart`, `login_screen.dart`, `register_screen.dart`, `forgot_password_screen.dart`, `invite_screen.dart`, `workspace_access_screen.dart`, `business_profile_wizard_screen.dart`, `role_based_shells.dart`, `employee_home_screen.dart`, `wellness_check_screen.dart`, `scan_flow_impl_normalized.dart`, `history_screen.dart`, `employee_requests_screen.dart`, `manager_home_screen.dart`, `manager_team_screen.dart`, `manager_scan_requests_screen.dart`, `hr_home_screen.dart`, `requests_screen.dart`, `hr_requests_screen.dart`, `hr_workforce_screen.dart`, `hr_compliance_screen.dart`, `owner_company_screen.dart`, `admin_scan_requests_screen.dart`, `owner_home_screen.dart`, `owner_reports_screen.dart`, `profile_screen.dart`, `notifications_screen.dart`, `scan_details_screen.dart`, `request_details_screen.dart`, `scan_request_details_screen.dart`, `scan_request_open_screen.dart`, `alert_detail_screen.dart`, `company_readiness_results_screen.dart`, `report_metric_detail_screen.dart`, and `organization_invitation_screen.dart`. Error-display/connectivity changes were made in `login_screen.dart`, `register_screen.dart`, `business_profile_wizard_screen.dart`, `role_based_shells.dart`, the four role Home screens, `wellness_check_screen.dart`, `requests_screen.dart`, `hr_requests_screen.dart`, `admin_scan_requests_screen.dart`, `profile_screen.dart`, `notifications_screen.dart`, `scan_flow_impl_normalized.dart`, and `organization_invitation_screen.dart`. Legacy/orphan screens listed below the route map’s “Secondary screens reachable only through legacy/orphan routes” heading were excluded. `request_details_screen.dart` was checked: its catch is payload formatting fallback, not the result/scan network lookup described in the earlier audit; no service failure is swallowed there.
