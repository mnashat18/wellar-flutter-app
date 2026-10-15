import '../utils/safe_debug_log.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../services/auth_service.dart';
import '../services/directus_client.dart';
import '../services/organization_service.dart';
import '../services/workspace_selection_service.dart';
import '../services/push_notification_service.dart';
import '../services/hr_ops_service.dart';
import '../services/owner_ops_service.dart';
import '../state/app_providers.dart';
import '../utils/app_colors.dart';
import '../utils/app_feedback.dart';
import '../widgets/wellar_app_shell.dart';
import '../widgets/wellar_bottom_nav.dart';
import 'employee_home_screen.dart';
import 'hr_home_screen.dart';
import 'history_screen.dart';
import 'manager_home_screen.dart';
import 'manager_team_screen.dart';
import 'owner_home_screen.dart';
import 'owner_hr_ops_screen.dart';
import 'owner_reports_screen.dart';
import 'profile_screen.dart';
import 'employee_requests_screen.dart';
import 'admin_scan_requests_screen.dart';
import 'manager_scan_requests_screen.dart';
import 'public_entry_screen.dart';
import 'wellness_check_screen.dart';
import 'workspace_access_screen.dart';
import 'workspace_picker_screen.dart';

enum MobileRoleShell { owner, hr, manager, employee }

class RoleShellFactory {
  static String shellKey(ActiveWorkspaceContext context) {
    return 'role-shell:${context.businessProfileId.trim()}:${context.membershipId.trim()}:${context.finalEffectiveRole.trim().toLowerCase()}:${OrganizationService.instance.workspaceRevision}';
  }

  static Widget build(ActiveWorkspaceContext context) {
    final shell = _resolveShell(context.finalEffectiveRole);
    if (shell == null) {
      return const WorkspaceAccessScreen(
        message: 'Workspace access is unavailable for this account.',
      );
    }
    final keyValue = shellKey(context);
    safeDebugLog('[ROLE_SHELL_KEY] key=$keyValue');
    switch (shell) {
      case MobileRoleShell.owner:
        return OwnerMobileShell(
          key: ValueKey<String>(keyValue),
          context: context,
        );
      case MobileRoleShell.hr:
        return HrMobileShell(key: ValueKey<String>(keyValue), context: context);
      case MobileRoleShell.manager:
        return ManagerMobileShell(
          key: ValueKey<String>(keyValue),
          context: context,
        );
      case MobileRoleShell.employee:
        return EmployeeMobileShell(
          key: ValueKey<String>(keyValue),
          context: context,
        );
    }
  }

  static MobileRoleShell? _resolveShell(String role) {
    final normalized = role.trim().toLowerCase();
    if (normalized == 'owner') return MobileRoleShell.owner;
    if (normalized == 'hr') return MobileRoleShell.hr;
    if (normalized == 'manager' || normalized == 'manger') {
      return MobileRoleShell.manager;
    }
    if (normalized == 'employee') return MobileRoleShell.employee;
    return null;
  }

  static List<String> tabsForRole(String role) {
    final shell = _resolveShell(role);
    if (shell == null) return const ['Today', 'Account'];
    switch (shell) {
      case MobileRoleShell.employee:
        return const ['Today', 'Scan', 'Results', 'Requests', 'Account'];
      case MobileRoleShell.manager:
        return const ['Today', 'Scan', 'Workforce', 'Requests', 'Account'];
      case MobileRoleShell.hr:
        return const [
          'Today',
          'Workforce',
          'Requests',
          'Compliance',
          'Reports',
        ];
      case MobileRoleShell.owner:
        return const [
          'Today',
          'Workforce',
          'Requests',
          'Compliance',
          'Reports',
        ];
    }
  }

  static List<String> _pageNamesForRole(String role) {
    final shell = _resolveShell(role);
    if (shell == null) return const ['_RolePagePlaceholder', 'ProfileScreen'];
    switch (shell) {
      case MobileRoleShell.employee:
        return const [
          'EmployeeHomeScreen',
          'WellnessCheckScreen',
          'HistoryScreen',
          'EmployeeRequestsScreen',
          'ProfileScreen',
        ];
      case MobileRoleShell.manager:
        return const [
          'ManagerHomeScreen',
          'WellnessCheckScreen',
          'ManagerTeamScreen',
          'ManagerScanRequestsScreen',
          'ProfileScreen',
        ];
      case MobileRoleShell.hr:
        return const [
          'HrHomeScreen',
          'OwnerHrOpsScreen(hr/workforce)',
          'AdminScanRequestsScreen',
          'OwnerHrOpsScreen(hr/compliance)',
          'OwnerReportsScreen(hr)',
        ];
      case MobileRoleShell.owner:
        return const [
          'OwnerHomeScreen',
          'OwnerHrOpsScreen(owner/workforce)',
          'AdminScanRequestsScreen',
          'OwnerHrOpsScreen(owner/compliance)',
          'OwnerReportsScreen(owner)',
        ];
    }
  }
}

enum VerifiedRouteKind {
  roleShell,
  workspaceSelection,
  workspaceAccess,
  workspaceAccessError,
  restrictedWorkspace,
  workspaceNotActivated,
  login,
}

class VerifiedRouteResult {
  final VerifiedRouteKind kind;
  final ActiveWorkspaceContext? context;
  final String? message;
  final List<WorkspaceMembershipChoice> memberships;

  const VerifiedRouteResult({
    required this.kind,
    this.context,
    this.message,
    this.memberships = const [],
  });
}

Future<VerifiedRouteResult> resolveVerifiedRouteResult({
  bool validateSession = true,
}) async {
  if (validateSession) {
    final sessionState = await AuthService.instance.validateSession();
    switch (sessionState) {
      case SessionValidationState.authenticated:
        break;
      case SessionValidationState.unauthenticated:
        return const VerifiedRouteResult(kind: VerifiedRouteKind.login);
      case SessionValidationState.validationUnavailable:
        return const VerifiedRouteResult(
          kind: VerifiedRouteKind.workspaceAccessError,
          message: 'We could not verify workspace access right now. Try again.',
        );
    }
  }

  final canonical = await OrganizationService.instance
      .fetchCanonicalWorkspaceContext(forceRefresh: true);
  if (canonical.status != CanonicalWorkspaceContextStatus.ok ||
      canonical.snapshot == null) {
    final result = WorkspaceResolveResult(
      status: switch (canonical.status) {
        CanonicalWorkspaceContextStatus.unauthenticated =>
          WorkspaceResolveStatus.unauthenticated,
        CanonicalWorkspaceContextStatus.forbidden =>
          WorkspaceResolveStatus.forbidden,
        CanonicalWorkspaceContextStatus.error => WorkspaceResolveStatus.error,
        CanonicalWorkspaceContextStatus.ok =>
          WorkspaceResolveStatus.noMembership,
      },
      message: canonical.message,
    );
    if (canonical.status == CanonicalWorkspaceContextStatus.ok) {
      OrganizationService.instance.clearActiveWorkspaceContext();
      return const VerifiedRouteResult(kind: VerifiedRouteKind.workspaceAccess);
    }
    return _workspaceResolveFailure(result);
  }

  final snapshot = canonical.snapshot!;
  final userId = snapshot.currentUserId.trim();
  final storedMembershipId = await WorkspaceSelectionStore.instance.read(
    userId,
  );
  final decision = WorkspaceSelectionPolicy.decide(
    memberships: snapshot.memberships,
    storedMembershipId: storedMembershipId,
  );
  if (decision.requiresPicker) {
    OrganizationService.instance.clearActiveWorkspaceContext();
    return VerifiedRouteResult(
      kind: VerifiedRouteKind.workspaceSelection,
      memberships: decision.memberships,
    );
  }
  final selectedMembership = decision.selection;
  if (selectedMembership == null) {
    OrganizationService.instance.clearActiveWorkspaceContext();
    if (storedMembershipId?.trim().isNotEmpty == true) {
      await WorkspaceSelectionStore.instance.clearForUser(userId);
    }
    return const VerifiedRouteResult(kind: VerifiedRouteKind.workspaceAccess);
  }
  if (storedMembershipId?.trim().isNotEmpty == true &&
      !decision.memberships.any(
        (membership) => membership.membershipId == storedMembershipId!.trim(),
      )) {
    await WorkspaceSelectionStore.instance.clearForUser(userId);
  }

  final currentContext = snapshot.activeContext;
  final ActiveWorkspaceContext selectedContext;
  if (currentContext?.membershipId == selectedMembership.membershipId) {
    selectedContext = currentContext!;
    OrganizationService.instance.applyActiveWorkspaceContext(
      selectedContext,
      source: 'canonical_context_selected',
    );
  } else {
    selectedContext = await OrganizationService.instance.syncWorkspaceSession(
      membershipId: selectedMembership.membershipId,
      trigger: 'deterministic_login_selection',
      expectedMembership: selectedMembership,
    );
  }
  await WorkspaceSelectionStore.instance.save(
    userId: userId,
    membershipId: selectedMembership.membershipId,
  );
  return _verifiedRouteFromContext(
    selectedContext,
    validateSession: validateSession,
  );
}

VerifiedRouteResult _workspaceResolveFailure(WorkspaceResolveResult workspace) {
  return VerifiedRouteResult(
    kind: VerifiedRouteKind.workspaceAccessError,
    message:
        workspace.message ?? 'We could not verify workspace access right now.',
  );
}

Future<VerifiedRouteResult> _verifiedRouteFromContext(
  ActiveWorkspaceContext ctx, {
  required bool validateSession,
}) async {
  final hasValidMembership =
      ctx.currentUserId.trim().isNotEmpty &&
      ctx.membershipUserId.trim() == ctx.currentUserId.trim() &&
      ctx.businessProfileId.trim().isNotEmpty &&
      (ctx.membershipStatus == 'active' || ctx.membershipStatus == 'accepted');
  if (!hasValidMembership) {
    OrganizationService.instance.clearActiveWorkspaceContext();
    return const VerifiedRouteResult(kind: VerifiedRouteKind.workspaceAccess);
  }
  if (ctx.finalEffectiveRole == 'user') {
    return VerifiedRouteResult(
      kind: VerifiedRouteKind.workspaceNotActivated,
      context: ctx,
    );
  }

  try {
    await PushNotificationService.instance.syncCurrentDevice(
      trigger: validateSession ? 'session_restore' : 'workspace_ready',
      workspaceContext: ctx,
    );
  } catch (_) {}
  return VerifiedRouteResult(kind: VerifiedRouteKind.roleShell, context: ctx);
}

class RoleShellRouter extends ConsumerStatefulWidget {
  final ActiveWorkspaceContext? initialContext;

  const RoleShellRouter({super.key, this.initialContext});

  @override
  ConsumerState<RoleShellRouter> createState() => _RoleShellRouterState();
}

class _RoleShellRouterState extends ConsumerState<RoleShellRouter> {
  late Future<Widget> _future;
  ProviderSubscription<ActiveWorkspaceContext?>? _workspaceSubscription;
  String _currentWorkspaceIdentity = '';
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _isLoggingOut = DirectusClient.instance.isLogoutInProgress;
    _currentWorkspaceIdentity = _workspaceIdentity(widget.initialContext);
    if (!_isLoggingOut && widget.initialContext != null) {
      _scheduleSafeActiveWorkspaceSync(widget.initialContext!);
    }
    _future = _isLoggingOut
        ? Future<Widget>.value(const PublicEntryScreen())
        : widget.initialContext == null
        ? _resolveTarget()
        : Future<Widget>.value(_buildShell(widget.initialContext!));
    _workspaceSubscription = ref.listenManual<ActiveWorkspaceContext?>(
      activeWorkspaceContextProvider,
      (previous, next) {
        if (_isLoggingOut || DirectusClient.instance.isLogoutInProgress) {
          _isLoggingOut = true;
          return;
        }
        final nextIdentity = _workspaceIdentity(next);
        if (nextIdentity == _currentWorkspaceIdentity) return;
        if (!mounted) return;
        _currentWorkspaceIdentity = nextIdentity;
        setState(() {
          _future = next == null
              ? _resolveTarget()
              : Future<Widget>.value(_buildShell(next));
        });
      },
    );
  }

  @override
  void didUpdateWidget(covariant RoleShellRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isLoggingOut || DirectusClient.instance.isLogoutInProgress) return;
    if (_workspaceIdentity(oldWidget.initialContext) !=
        _workspaceIdentity(widget.initialContext)) {
      if (widget.initialContext != null) {
        _scheduleSafeActiveWorkspaceSync(widget.initialContext!);
      }
      setState(() {
        _future = widget.initialContext == null
            ? _resolveTarget()
            : Future<Widget>.value(_buildShell(widget.initialContext!));
      });
    }
  }

  @override
  void dispose() {
    _workspaceSubscription?.close();
    super.dispose();
  }

  String _workspaceIdentity(ActiveWorkspaceContext? context) {
    if (context == null) {
      return 'null:${OrganizationService.instance.workspaceRevision}';
    }
    return RoleShellFactory.shellKey(context);
  }

  void _scheduleSafeActiveWorkspaceSync(ActiveWorkspaceContext context) {
    final scheduledRevision = OrganizationService.instance.workspaceRevision;
    final scheduledSignature = OrganizationService.instance.workspaceSignature;
    final scheduledIdentity = RoleShellFactory.shellKey(context);

    Future<void>(() {
      if (!mounted ||
          _isLoggingOut ||
          DirectusClient.instance.isLogoutInProgress) {
        return;
      }

      final currentRevision = OrganizationService.instance.workspaceRevision;
      final currentSignature = OrganizationService.instance.workspaceSignature;
      final currentWorkspace = ref.read(activeWorkspaceContextProvider);
      final currentIdentity = currentWorkspace == null
          ? 'null:$currentRevision'
          : RoleShellFactory.shellKey(currentWorkspace);
      if (currentRevision != scheduledRevision ||
          currentSignature != scheduledSignature) {
        safeDebugLog(
          '[STALE_CONTEXT_WRITE_IGNORED] scheduled_identity=$scheduledIdentity current_identity=$currentIdentity scheduled_revision=$scheduledRevision current_revision=$currentRevision',
        );
        return;
      }

      if (currentWorkspace != null && currentIdentity == scheduledIdentity) {
        return;
      }

      if (currentWorkspace != null && currentIdentity != scheduledIdentity) {
        safeDebugLog(
          '[STALE_CONTEXT_WRITE_IGNORED] scheduled_identity=$scheduledIdentity current_identity=$currentIdentity scheduled_revision=$scheduledRevision current_revision=$currentRevision',
        );
        return;
      }

      ref.read(activeWorkspaceContextProvider.notifier).state = context;
      _currentWorkspaceIdentity = scheduledIdentity;

      safeDebugLog(
        '[ACTIVE_WORKSPACE_PROVIDER_SYNC] identity=$scheduledIdentity membership_id=${context.membershipId} role=${context.finalEffectiveRole}',
      );
    });
  }

  Future<Widget> _resolveTarget() async {
    if (_isLoggingOut || DirectusClient.instance.isLogoutInProgress) {
      return const PublicEntryScreen();
    }
    final result = await resolveVerifiedRouteResult();
    if (!mounted ||
        _isLoggingOut ||
        DirectusClient.instance.isLogoutInProgress) {
      return const PublicEntryScreen();
    }
    switch (result.kind) {
      case VerifiedRouteKind.login:
        ref.read(activeWorkspaceContextProvider.notifier).state = null;
        return const PublicEntryScreen();
      case VerifiedRouteKind.workspaceSelection:
        ref.read(activeWorkspaceContextProvider.notifier).state = null;
        return WorkspacePickerScreen(
          memberships: result.memberships,
          mandatory: true,
        );
      case VerifiedRouteKind.workspaceAccessError:
        ref.read(activeWorkspaceContextProvider.notifier).state = null;
        return WorkspaceAccessScreen(
          state: WorkspaceAccessViewState.accessResolutionError,
          message: result.message,
        );
      case VerifiedRouteKind.restrictedWorkspace:
        ref.read(activeWorkspaceContextProvider.notifier).state = null;
        return WorkspaceAccessScreen(
          state: WorkspaceAccessViewState.accessResolutionError,
          message: result.message,
        );
      case VerifiedRouteKind.workspaceAccess:
        ref.read(activeWorkspaceContextProvider.notifier).state = null;
        return const WorkspaceAccessScreen(
          state: WorkspaceAccessViewState.noWorkspace,
        );
      case VerifiedRouteKind.workspaceNotActivated:
        if (result.context != null) {
          _scheduleSafeActiveWorkspaceSync(result.context!);
        }
        return const WorkspaceAccessScreen(
          state: WorkspaceAccessViewState.workspaceNotActivated,
        );
      case VerifiedRouteKind.roleShell:
        if (result.context != null) {
          _scheduleSafeActiveWorkspaceSync(result.context!);
        }
        return _buildShell(result.context!);
    }
  }

  Widget _buildShell(ActiveWorkspaceContext ctx) {
    if (_isLoggingOut || DirectusClient.instance.isLogoutInProgress) {
      return const PublicEntryScreen();
    }
    final previousCachedRole = OrganizationService.instance.lastResolvedRole;
    final previousCachedUserId =
        OrganizationService.instance.lastResolvedUserId;
    final previousRole = previousCachedRole?.trim().toLowerCase() ?? '';
    final currentRole = ctx.finalEffectiveRole.trim().toLowerCase();
    if (previousRole.isNotEmpty && previousRole != currentRole) {
      safeDebugLog(
        '[ROLE_SWITCH_CLEANUP] from_role=$previousRole to_role=$currentRole',
      );
      OwnerOpsService.instance.clearOrganizationScopedCaches();
      HrOpsService.instance.clearOrganizationScopedCaches();
      safeDebugLog('[ROLE_SWITCH_CLEANUP] owner_providers_disposed=true');
      safeDebugLog(
        '[ROLE_SWITCH_CLEANUP] hr_providers_active=${currentRole == "hr"}',
      );
      ref.read(refreshTickProvider.notifier).state++;
      safeDebugLog('[ROLE_SWITCH_CLEANUP] refresh_tick_incremented=true');
    }
    final tabs = RoleShellFactory.tabsForRole(ctx.finalEffectiveRole);
    final selectedShell = _shellDebugName(
      RoleShellFactory._resolveShell(ctx.finalEffectiveRole),
    );
    safeDebugLog('[ROLE_DEBUG] selectedShell=$selectedShell');
    safeDebugLog(
      '[ROUTER] shell=$selectedShell previousCachedRole=$previousCachedRole previousCachedUserId=$previousCachedUserId',
    );
    safeDebugLog(
      'ROLE_SHELL_BUILD: memberRole=${ctx.finalEffectiveRole} visibleTabs=${tabs.join(",")} selectedShell=$selectedShell previousCachedRole=$previousCachedRole previousCachedUserId=$previousCachedUserId',
    );
    safeDebugLog(
      '[ROLE_SHELL_PAGES] role=${ctx.finalEffectiveRole} pages=${RoleShellFactory._pageNamesForRole(ctx.finalEffectiveRole).join(",")}',
    );
    final shellKey = RoleShellFactory.shellKey(ctx);
    safeDebugLog(
      '[ROLE_SHELL_REBUILT] role=${ctx.finalEffectiveRole} membership_id=${ctx.membershipId} business_profile=${ctx.businessProfileId}',
    );
    if (ctx.membershipId.trim().isNotEmpty ||
        ctx.businessProfileId.trim().isNotEmpty) {
      return KeyedSubtree(
        key: ValueKey(shellKey),
        child: RoleShellFactory.build(ctx),
      );
    }
    return RoleShellFactory.build(ctx);
  }

  String _shellDebugName(MobileRoleShell? shell) {
    switch (shell) {
      case MobileRoleShell.employee:
        return 'EmployeeShell';
      case MobileRoleShell.manager:
        return 'ManagerShell';
      case MobileRoleShell.hr:
        return 'HrShell';
      case MobileRoleShell.owner:
        return 'OwnerShell';
      case null:
        return 'WorkspaceAccess';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primarySoft),
            ),
          );
        }
        return snapshot.data ?? const WorkspaceAccessScreen();
      },
    );
  }
}

class EmployeeMobileShell extends _BaseRoleShell {
  const EmployeeMobileShell({super.key, required super.context})
    : super(
        role: 'employee',
        tabs: const ['Today', 'Scan', 'Results', 'Requests', 'Account'],
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Today',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt_outlined),
            label: 'Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            label: 'Results',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            label: 'Requests',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Account',
          ),
        ],
      );

  @override
  List<Widget> buildPages() => const [
    EmployeeHomeScreen(),
    WellnessCheckScreen(),
    HistoryScreen(),
    EmployeeRequestsScreen(),
    ProfileScreen(),
  ];
}

class ManagerMobileShell extends _BaseRoleShell {
  const ManagerMobileShell({super.key, required super.context})
    : super(
        role: 'manager',
        tabs: const ['Today', 'Scan', 'Workforce', 'Requests', 'Account'],
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Today',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt_outlined),
            label: 'Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.groups_outlined),
            label: 'Workforce',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            label: 'Requests',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Account',
          ),
        ],
      );

  @override
  List<Widget> buildPages() => const [
    ManagerHomeScreen(),
    WellnessCheckScreen(),
    ManagerTeamScreen(),
    ManagerScanRequestsScreen(),
    ProfileScreen(),
  ];
}

class HrMobileShell extends _BaseRoleShell {
  const HrMobileShell({super.key, required super.context})
    : super(
        role: 'hr',
        tabs: const ['Today', 'Workforce', 'Requests', 'Compliance', 'Reports'],
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Today',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.groups_outlined),
            label: 'Workforce',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            label: 'Requests',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.verified_user_outlined),
            label: 'Compliance',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            label: 'Reports',
          ),
        ],
      );

  @override
  List<Widget> buildPages() => [
    const HrHomeScreen(),
    const OwnerHrOpsScreen(role: 'hr', initialTab: OwnerHrOpsTab.workforce),
    const AdminScanRequestsScreen(),
    const OwnerHrOpsScreen(role: 'hr', initialTab: OwnerHrOpsTab.compliance),
    const OwnerReportsScreen(roleOverride: 'hr'),
  ];
}

class OwnerMobileShell extends _BaseRoleShell {
  const OwnerMobileShell({super.key, required super.context})
    : super(
        role: 'owner',
        tabs: const ['Today', 'Workforce', 'Requests', 'Compliance', 'Reports'],
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Today',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.groups_outlined),
            label: 'Workforce',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            label: 'Requests',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.verified_user_outlined),
            label: 'Compliance',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            label: 'Reports',
          ),
        ],
      );

  @override
  List<Widget> buildPages() => [
    const OwnerHomeScreen(),
    const OwnerHrOpsScreen(role: 'owner', initialTab: OwnerHrOpsTab.workforce),
    const AdminScanRequestsScreen(),
    const OwnerHrOpsScreen(role: 'owner', initialTab: OwnerHrOpsTab.compliance),
    const OwnerReportsScreen(roleOverride: 'owner'),
  ];
}

class LimitedRoleMobileShell extends _BaseRoleShell {
  const LimitedRoleMobileShell({super.key, required super.context})
    : super(
        role: 'limited',
        tabs: const ['Today', 'Account'],
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Today',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Account',
          ),
        ],
      );

  @override
  List<Widget> buildPages() => const [
    _RolePagePlaceholder(
      title: 'Workspace access unavailable',
      subtitle:
          'Your workspace role is unavailable. Contact your administrator.',
    ),
    ProfileScreen(),
  ];
}

abstract class _BaseRoleShell extends ConsumerStatefulWidget {
  final ActiveWorkspaceContext context;
  final String role;
  final List<String> tabs;
  final List<BottomNavigationBarItem> items;

  const _BaseRoleShell({
    required this.context,
    required this.role,
    required this.tabs,
    required this.items,
    super.key,
  });

  List<Widget> buildPages();

  @override
  ConsumerState<_BaseRoleShell> createState() => _BaseRoleShellState();
}

class _BaseRoleShellState extends ConsumerState<_BaseRoleShell> {
  int _index = 0;
  late List<Widget?> _pageCache;
  late List<bool> _mountedTabs;

  String _shellIdentity(ActiveWorkspaceContext context) {
    return RoleShellFactory.shellKey(context);
  }

  @override
  void initState() {
    super.initState();
    _pageCache = List<Widget?>.filled(widget.items.length, null);
    _mountedTabs = List<bool>.filled(widget.items.length, false);
    _mountedTabs[0] = true;
  }

  @override
  void didUpdateWidget(covariant _BaseRoleShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousIdentity = _shellIdentity(oldWidget.context);
    final nextIdentity = _shellIdentity(widget.context);
    if (previousIdentity == nextIdentity) return;
    safeDebugLog(
      '[ROLE_SHELL_TAB_RESET] reason=workspace_or_role_changed from=$previousIdentity to=$nextIdentity',
    );
    safeDebugLog(
      '[ROLE_SHELL_DISPOSED] old_role=${oldWidget.role} old_membership=${oldWidget.context.membershipId}',
    );
    setState(() {
      _index = 0;
      _pageCache = List<Widget?>.filled(widget.items.length, null);
      _mountedTabs = List<bool>.filled(widget.items.length, false);
      _mountedTabs[0] = true;
    });
  }

  @override
  void dispose() {
    safeDebugLog(
      '[ROLE_SHELL_DISPOSED] old_role=${widget.role} old_membership=${widget.context.membershipId}',
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final pages = _materializePages();
    safeDebugLog(
      'ROLE_SHELL_BUILD: memberRole=${widget.context.memberRole} visibleTabs=${widget.tabs.join(",")} selectedShell=${widget.role} previousCachedRole=${OrganizationService.instance.lastResolvedRole} previousCachedUserId=${OrganizationService.instance.lastResolvedUserId}',
    );
    return WellarAppShell(
      bottomNavigationBar: WellarBottomNav(
        currentIndex: _index,
        onTap: (value) {
          final opensScan =
              value >= 0 &&
              value < widget.tabs.length &&
              widget.tabs[value].toLowerCase() == 'scan';
          if (opensScan &&
              ref.read(connectivityStatusProvider).asData?.value == false) {
            AppFeedback.showOffline(context);
            return;
          }
          setState(() {
            _index = value;
            if (value >= 0 && value < _mountedTabs.length) {
              _mountedTabs[value] = true;
            }
          });
        },
        items: _localizedItems(lang),
      ),
      child: IndexedStack(
        key: ValueKey(_shellIdentity(widget.context)),
        index: _index.clamp(0, pages.length - 1),
        children: pages,
      ),
    );
  }

  List<Widget> _materializePages() {
    final builtPages = widget.buildPages();
    return List<Widget>.generate(builtPages.length, (index) {
      if (_mountedTabs[index]) {
        return _pageCache[index] ??= builtPages[index];
      }
      return const SizedBox.shrink();
    });
  }

  List<BottomNavigationBarItem> _localizedItems(dynamic lang) {
    return widget.items
        .map(
          (item) => BottomNavigationBarItem(
            icon: item.icon,
            activeIcon: item.activeIcon,
            label: _translateNavLabel(lang, item.label ?? ''),
            tooltip: item.tooltip,
            backgroundColor: item.backgroundColor,
          ),
        )
        .toList();
  }

  String _translateNavLabel(dynamic lang, String label) {
    final v = label.trim().toLowerCase();
    if (v == 'today') return Tr.t(lang, 'today');
    if (v == 'scan') return Tr.t(lang, 'scan');
    if (v == 'results') return Tr.t(lang, 'results');
    if (v == 'account') return Tr.t(lang, 'account');
    if (v == 'home') return Tr.t(lang, 'home');
    if (v == 'requests') return Tr.t(lang, 'requests');
    if (v == 'history') return Tr.t(lang, 'history');
    if (v == 'alerts') return Tr.t(lang, 'alerts');
    if (v == 'profile') return Tr.t(lang, 'profile');
    if (v == 'workforce') return Tr.t(lang, 'workforce');
    if (v == 'compliance') return Tr.t(lang, 'compliance');
    if (v == 'ops') return Tr.t(lang, 'ops');
    if (v == 'company') return Tr.t(lang, 'company');
    if (v == 'reports') return Tr.t(lang, 'reports');
    if (v == 'more') return Tr.t(lang, 'owner_more_nav');
    return label;
  }
}

class _RolePagePlaceholder extends StatelessWidget {
  final String title;
  final String subtitle;

  const _RolePagePlaceholder({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(subtitle),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
