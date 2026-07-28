import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../services/member_identity_service.dart';
import '../services/owner_ops_service.dart';
import '../services/organization_service.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_wellar_card.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/owner/owner_design_system.dart';
import '../widgets/page_header_actions.dart';
import '../widgets/workforce_member_card.dart';

class OwnerWorkforceScreen extends ConsumerStatefulWidget {
  const OwnerWorkforceScreen({super.key});

  @override
  ConsumerState<OwnerWorkforceScreen> createState() =>
      _OwnerWorkforceScreenState();
}

class _OwnerWorkforceScreenState extends ConsumerState<OwnerWorkforceScreen> {
  static const String _allDepartmentsValue = '';
  static const String _unassignedDepartmentValue = '__unassigned__';

  late Future<OwnerWorkforceDirectoryData> _future;
  ProviderSubscription<ActiveWorkspaceContext?>? _workspaceSubscription;
  String _workspaceIdentity = '';
  String _roleFilter = 'all';
  String _departmentFilter = _allDepartmentsValue;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _workspaceIdentity = _identityOf(ref.read(activeWorkspaceContextProvider));
    _future = _loadWorkforceForCurrentRole();
    _workspaceSubscription = ref.listenManual(
      activeWorkspaceContextProvider,
      (previous, next) {
        final nextIdentity = _identityOf(next);
        if (nextIdentity == _workspaceIdentity) return;
        if (!mounted) return;
        final nextRole = _workspaceRole(next);
        if (nextRole != 'owner') {
          debugPrint(
            '[STALE_ROLE_WIDGET_BLOCKED] widget=OwnerWorkforceScreen expected=owner actual=$nextRole',
          );
          setState(() {
            _workspaceIdentity = nextIdentity;
            _roleFilter = 'all';
            _departmentFilter = _allDepartmentsValue;
            _query = '';
            _future = _idleWorkforceFuture();
          });
          return;
        }
        setState(() {
          _workspaceIdentity = nextIdentity;
          _roleFilter = 'all';
          _departmentFilter = _allDepartmentsValue;
          _query = '';
          _future = _loadWorkforceForCurrentRole(forceRefresh: true);
        });
      },
    );
  }

  @override
  void dispose() {
    _workspaceSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(activeWorkspaceContextProvider);
    final activeRole = _workspaceRole(workspace);
    if (activeRole != 'owner') {
      debugPrint(
        '[STALE_ROLE_WIDGET_BLOCKED] widget=OwnerWorkforceScreen expected=owner actual=$activeRole',
      );
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: WellarTheme.primary,
          ),
        ),
      );
    }
    final lang = ref.watch(appLanguageControllerProvider).language;
    final unread = ref.watch(unreadNotificationsProvider);
    final roleFilters = <_RoleFilterOption>[
      _RoleFilterOption(key: 'all', label: Tr.t(lang, 'all')),
      _RoleFilterOption(key: 'owner', label: Tr.t(lang, 'owner')),
      _RoleFilterOption(key: 'hr', label: Tr.t(lang, 'hr')),
      _RoleFilterOption(key: 'manager', label: Tr.t(lang, 'manager')),
      _RoleFilterOption(key: 'employee', label: Tr.t(lang, 'employee')),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: FutureBuilder<OwnerWorkforceDirectoryData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const OwnerSurfaceCard(
                child: SizedBox(
                  height: 180,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: WellarTheme.primary,
                    ),
                  ),
                ),
              );
            }
            if (snapshot.hasError) {
              final forbidden =
                  snapshot.error is DioException &&
                  (snapshot.error as DioException).response?.statusCode == 403;
              return SmartEmptyState(
                icon: Icons.people_alt_outlined,
                title: Tr.t(lang, 'unable_load_workforce'),
                subtitle: forbidden
                    ? Tr.t(lang, 'workforce_unavailable')
                    : Tr.t(lang, 'unable_load_workforce'),
                actionLabel: Tr.t(lang, 'retry'),
                onAction: () => setState(
                  () => _future =
                      OwnerOpsService.instance.fetchWorkforceDirectory(
                        forceRefresh: true,
                      ),
                ),
              );
            }

            final data = snapshot.data!;
            final filtered = _applyFilter(data.members);
            final hasUnassigned = data.members.any(
              (member) =>
                  member.departmentLabel ==
                  MemberIdentityService.noDepartmentLabel,
            );
            final businessProfileId =
                (workspace?.businessProfileId ?? '').trim();
            final membershipId = (workspace?.membershipId ?? '').trim();
            final role = (workspace?.finalEffectiveRole ??
                    workspace?.memberRole ??
                    'unknown')
                .trim();
            final departmentId = (workspace?.departmentId ?? '').trim();
            debugPrint(
              '[WORKFORCE_SOURCE] screen=OwnerWorkforce role=$role business_profile=$businessProfileId membership_id=$membershipId department=${departmentId.isEmpty ? "none" : departmentId}',
            );
            debugPrint(
              '[OWNER_WORKFORCE_RENDER] loaded_count=${data.members.length} visible_count=${filtered.length}',
            );
            if (_query.isNotEmpty) {
              debugPrint(
                '[OWNER_WORKFORCE_FILTER] query=$_query visible_count=${filtered.length}',
              );
            }

            return RefreshIndicator(
              onRefresh: () async => setState(
                () => _future =
                    OwnerOpsService.instance.fetchWorkforceDirectory(
                      forceRefresh: true,
                    ),
              ),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SectionHeader(
                    title: 'Workforce',
                    subtitle:
                        'Team directory, readiness, and department coverage.',
                    trailing: PageHeaderActions(
                      unreadCount: unread,
                      showAlertsTab: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  OwnerSurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          onChanged: (value) => setState(
                            () => _query = value.trim().toLowerCase(),
                          ),
                          style: const TextStyle(color: WellarTheme.text),
                          decoration: InputDecoration(
                            hintText: Tr.t(lang, 'search_by_name_email'),
                            hintStyle: const TextStyle(
                              color: WellarTheme.textMuted,
                            ),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: WellarTheme.textMuted,
                            ),
                            filled: true,
                            fillColor: const Color(0x16FFFFFF),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: roleFilters.map((filter) {
                            return ChoiceChip(
                              label: Text(filter.label),
                              selected: _roleFilter == filter.key,
                              onSelected: (_) {
                                setState(() => _roleFilter = filter.key);
                              },
                            );
                          }).toList(),
                        ),
                        if (data.departments.isNotEmpty || hasUnassigned) ...[
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _departmentFilter,
                            dropdownColor: const Color(0xFF172235),
                            style: const TextStyle(color: WellarTheme.text),
                            decoration: InputDecoration(
                              labelText: '${Tr.t(lang, 'department')} filter',
                            ),
                            items: [
                              DropdownMenuItem(
                                value: _allDepartmentsValue,
                                child: Text(
                                  '${Tr.t(lang, 'all')} ${Tr.t(lang, 'departments').toLowerCase()}',
                                ),
                              ),
                              ...data.departments.map(
                                (department) => DropdownMenuItem(
                                  value: department.id,
                                  child: Text(department.displayName),
                                ),
                              ),
                              if (hasUnassigned)
                                DropdownMenuItem(
                                  value: _unassignedDepartmentValue,
                                  child: const Text('No department'),
                                ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _departmentFilter =
                                    value ?? _allDepartmentsValue;
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _summaryChip(
                        Tr.t(lang, 'active_members'),
                        '${data.members.where((member) => member.isActive).length}',
                        const Color(0xFF6EE7A8),
                      ),
                      _summaryChip(
                        Tr.t(lang, 'departments'),
                        '${data.departments.length}',
                        const Color(0xFF7DBBFF),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (filtered.isEmpty)
                    SmartEmptyState(
                      icon: Icons.people_alt_outlined,
                      title: Tr.t(lang, 'no_workforce_members'),
                      subtitle: Tr.t(lang, 'members_appear_here'),
                    )
                  else
                    ...filtered.asMap().entries.map(
                      (entry) => AnimatedWellarCard(
                        delay: Duration(milliseconds: 40 + (entry.key * 20)),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: WorkforceMemberCard(
                            data: WorkforceMemberCardData(
                              name: entry.value.displayName,
                              email: entry.value.displayEmail,
                              status: entry.value.status,
                              department: entry.value.departmentLabel,
                              role: entry.value.role,
                              latestReadiness:
                                  entry.value.latestReadiness ??
                                  Tr.t(lang, 'pending'),
                              lastCheck: entry.value.lastCheckAt == null
                                  ? 'No recent check'
                                  : _formatDate(
                                      context,
                                      entry.value.lastCheckAt,
                                    ),
                              membershipId: entry.value.memberId,
                              userId: entry.value.userId,
                              requiresLinking: entry.value.requiresLinking,
                              accent: _memberAccent(entry.value),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<OwnerWorkforceDirectoryData> _loadWorkforceForCurrentRole({
    bool forceRefresh = false,
  }) {
    final workspace = ref.read(activeWorkspaceContextProvider);
    final activeRole = _workspaceRole(workspace);
    if (activeRole != 'owner') {
      debugPrint(
        '[STALE_ROLE_WIDGET_BLOCKED] widget=OwnerWorkforceScreen expected=owner actual=$activeRole',
      );
      return _idleWorkforceFuture();
    }
    return OwnerOpsService.instance.fetchWorkforceDirectory(
      forceRefresh: forceRefresh,
    );
  }

  List<OwnerMemberView> _applyFilter(List<OwnerMemberView> data) {
    var filtered = data.where((member) {
      if (_roleFilter == 'all') return true;
      return member.roleKey == _roleFilter;
    }).toList();

    if (_departmentFilter == _unassignedDepartmentValue) {
      filtered = filtered
          .where(
            (member) =>
                member.departmentLabel ==
                MemberIdentityService.noDepartmentLabel,
          )
          .toList();
    } else if (_departmentFilter.isNotEmpty) {
      filtered = filtered.where((member) {
        return member.departmentId?.trim() == _departmentFilter;
      }).toList();
    }

    if (_query.isEmpty) return filtered;
    return filtered.where((member) {
      final name = member.displayName.toLowerCase();
      final email = member.email.toLowerCase();
      return name.contains(_query) || email.contains(_query);
    }).toList();
  }

  Widget _summaryChip(String label, String value, Color accent) {
    return Container(
      constraints: const BoxConstraints(minWidth: 116),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: WellarTheme.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: WellarTheme.text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Color _memberAccent(OwnerMemberView item) {
    if (item.latestReadiness == 'High Risk') return const Color(0xFFFF7A8F);
    if (item.hasOpenAlert) return const Color(0xFF7DBBFF);
    if (item.hasOverdueRequest || item.missingCheck) {
      return const Color(0xFFFFC46B);
    }
    return WellarTheme.primary;
  }

  String _formatDate(BuildContext context, DateTime? value) {
    if (value == null) return '-';
    return MaterialLocalizations.of(context).formatMediumDate(value.toLocal());
  }

  String _identityOf(ActiveWorkspaceContext? workspace) {
    if (workspace == null) return '';
    return '${workspace.currentUserId}:${workspace.membershipId}:${workspace.businessProfileId}:${workspace.finalEffectiveRole}:${workspace.departmentId ?? ''}';
  }

  String _workspaceRole(ActiveWorkspaceContext? workspace) {
    if (workspace == null) return '';
    return workspace.finalEffectiveRole.trim().toLowerCase();
  }

  Future<OwnerWorkforceDirectoryData> _idleWorkforceFuture() {
    return Future<OwnerWorkforceDirectoryData>.value(
      const OwnerWorkforceDirectoryData(
        members: [],
        departments: [],
      ),
    );
  }
}

class _RoleFilterOption {
  final String key;
  final String label;

  const _RoleFilterOption({required this.key, required this.label});
}
