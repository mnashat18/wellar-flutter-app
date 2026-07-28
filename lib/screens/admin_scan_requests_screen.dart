import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../models/request_item.dart';
import '../services/admin_request_service.dart';
import '../services/member_identity_service.dart';
import '../services/owner_ops_service.dart';
import '../services/request_service.dart';
import '../state/app_providers.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../utils/page_transition.dart';
import '../utils/request_status_normalizer.dart';
import '../widgets/animated_wellar_card.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/owner/owner_design_system.dart';
import '../widgets/wellar_button.dart';
import '../widgets/wellar_card.dart';
import '../widgets/wellar_empty_state.dart';
import '../widgets/wellar_error_state.dart';
import '../widgets/wellar_header.dart';
import '../widgets/wellar_metric_card.dart';
import '../widgets/wellar_skeleton_shimmer.dart';
import '../widgets/page_header_actions.dart';
import 'scan_request_details_screen.dart';
import 'wellness_check_screen.dart';

class _OwnerRequestsData {
  final List<RequestItem> requests;
  final Map<String, OwnerAssessmentResult> assessmentsByScanId;
  final bool assessmentsQueryFailed;

  const _OwnerRequestsData({
    required this.requests,
    required this.assessmentsByScanId,
    required this.assessmentsQueryFailed,
  });
}

class AdminScanRequestsScreen extends ConsumerStatefulWidget {
  const AdminScanRequestsScreen({super.key});

  @override
  ConsumerState<AdminScanRequestsScreen> createState() =>
      _AdminScanRequestsScreenState();
}

class _AdminScanRequestsScreenState
    extends ConsumerState<AdminScanRequestsScreen> {
  late Future<_OwnerRequestsData> _future;
  String _filter = 'all';
  ProviderSubscription<int>? _refreshSubscription;

  @override
  void initState() {
    super.initState();
    _future = _loadRequestsData();
    _refreshSubscription = ref.listenManual<int>(refreshTickProvider, (
      _,
      __,
    ) {
      if (!mounted) return;
      setState(() {
        _future = _loadRequestsData();
      });
    });
  }

  @override
  void dispose() {
    _refreshSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final workspace = ref.watch(activeWorkspaceContextProvider);
    final role = workspace?.finalEffectiveRole.toUpperCase() ?? 'ADMIN';
    final unread = ref.watch(unreadNotificationsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        child: FutureBuilder<_OwnerRequestsData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const WellarCard(
                child: WellarSkeletonShimmer(height: 220),
              );
            }
            if (snap.hasError) {
              final roleUnavailable =
                  snap.error is RequestRoleUnavailableException;
              debugPrint(
                '[OWNER_REQUESTS_UI] future_error error=${snap.error} roleUnavailable=$roleUnavailable',
              );
              return WellarErrorState(
                title: roleUnavailable
                    ? Tr.t(lang, 'access_unavailable')
                    : Tr.t(lang, 'unable_load_requests'),
                body: roleUnavailable
                    ? Tr.t(lang, 'role_unavailable_info')
                    : Tr.t(lang, 'unable_load_scan_requests'),
                onRetry: _reload,
              );
            }
            final data = snap.data;
            final allItems = data?.requests ?? const [];
            final items = _applyFilter(allItems);
            final counts = _statusCounts(allItems);
            final pending = counts[NormalizedRequestStatus.pending] ?? 0;
            final completed = counts[NormalizedRequestStatus.completed] ?? 0;
            final overdue = counts[NormalizedRequestStatus.overdue] ?? 0;
            debugPrint(
              '[REQUESTS_PAGE_COUNTS] pending=$pending completed=$completed overdue=$overdue',
            );
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  WellarHeader(
                    title: Tr.t(lang, 'readiness_requests'),
                    subtitle: Tr.t(lang, 'readiness_requests_subtitle'),
                    trailing: PageHeaderActions(
                      unreadCount: unread,
                      showAlertsTab: true,
                    ),
                  ),
                  if (data?.assessmentsQueryFailed == true) ...[
                    const SizedBox(height: 10),
                    const WellarCard(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Assessment results are unavailable right now.',
                          style: TextStyle(color: WellarTheme.textMuted),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  WellarCard(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: WellarTheme.surfaceSoft.withValues(
                              alpha: 0.45,
                            ),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            role,
                            style: const TextStyle(color: WellarTheme.text),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            workspace?.businessProfileName ??
                                Tr.t(lang, 'workspace_default'),
                            style: const TextStyle(
                              color: WellarTheme.textMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  WellarCard(
                    child: Column(
                      children: [
                        WellarButton.primary(
                          text: Tr.t(lang, 'create_request'),
                          onPressed: _openCreateDialog,
                        ),
                        const SizedBox(height: 8),
                        WellarButton.secondary(
                          text: Tr.t(lang, 'start_self_readiness_scan'),
                          onPressed: () => Navigator.push(
                            context,
                            fadeSlideRoute(const WellnessCheckScreen()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: WellarMetricCard(
                          label: Tr.t(lang, 'pending'),
                          value: '$pending',
                          icon: Icons.hourglass_bottom_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: WellarMetricCard(
                          label: Tr.t(lang, 'completed'),
                          value: '$completed',
                          icon: Icons.check_circle_outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  WellarMetricCard(
                    label: Tr.t(lang, 'overdue'),
                    value: '$overdue',
                    icon: Icons.warning_amber_rounded,
                  ),
                  const SizedBox(height: 12),
                  _filters(lang),
                  const SizedBox(height: 10),
                  if (items.isEmpty)
                    WellarEmptyState(
                      icon: Icons.assignment_outlined,
                      title: Tr.t(lang, 'no_scan_requests_yet'),
                      body: Tr.t(lang, 'create_readiness_request'),
                    )
                  else
                    ...items.asMap().entries.map((entry) {
                      final item = entry.value;
                      final assessment = data?.assessmentsByScanId[
                        item.scanId?.trim() ?? ''
                      ];
                      return AnimatedWellarCard(
                        delay: Duration(milliseconds: 40 + (entry.key * 25)),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _requestCard(
                            lang,
                            item,
                            assessment: assessment,
                          ),
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _reload() {
    setState(() {
      _future = _loadRequestsData();
    });
  }

  Future<_OwnerRequestsData> _loadRequestsData() async {
    final requests = await AdminRequestService.instance.fetchWorkspaceRequests();
    final scanIds = requests
        .map((item) => item.scanId?.trim() ?? '')
        .where((scanId) => scanId.isNotEmpty)
        .toSet()
        .toList();
    final assessments = await OwnerOpsService.instance
        .fetchAssessmentResultsByScanIds(scanIds: scanIds);
    return _OwnerRequestsData(
      requests: requests,
      assessmentsByScanId: assessments.resultsByScanId,
      assessmentsQueryFailed: assessments.queryFailed,
    );
  }

  Widget _filters(dynamic lang) {
    return Wrap(
      spacing: 8,
      children: [
        _filterChip(lang, 'all', Tr.t(lang, 'all')),
        _filterChip(lang, 'pending', Tr.t(lang, 'pending')),
        _filterChip(lang, 'completed', Tr.t(lang, 'completed')),
        _filterChip(lang, 'overdue', Tr.t(lang, 'overdue')),
      ],
    );
  }

  Widget _filterChip(dynamic lang, String id, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == id,
      onSelected: (_) => setState(() => _filter = id),
    );
  }

  List<RequestItem> _applyFilter(List<RequestItem> items) {
    if (_filter == 'all') return items;
    final now = DateTime.now();
    return items.where((i) {
      final normalized = RequestStatusNormalizer.normalize(i, now: now);
      if (_filter == 'completed') {
        return normalized == NormalizedRequestStatus.completed;
      }
      if (_filter == 'overdue') {
        return normalized == NormalizedRequestStatus.overdue;
      }
      return normalized == NormalizedRequestStatus.pending;
    }).toList();
  }

  Map<NormalizedRequestStatus, int> _statusCounts(List<RequestItem> items) {
    final now = DateTime.now();
    final counts = <NormalizedRequestStatus, int>{
      NormalizedRequestStatus.pending: 0,
      NormalizedRequestStatus.completed: 0,
      NormalizedRequestStatus.overdue: 0,
      NormalizedRequestStatus.cancelled: 0,
    };
    for (final item in items) {
      final normalized = RequestStatusNormalizer.normalize(item, now: now);
      counts[normalized] = (counts[normalized] ?? 0) + 1;
    }
    return counts;
  }

  Widget _requestCard(
    dynamic lang,
    RequestItem item, {
    OwnerAssessmentResult? assessment,
  }) {
    final normalized = RequestStatusNormalizer.normalize(item, log: false);
    final hasCompletedScan = item.scanId?.trim().isNotEmpty == true;
    final completedAt = item.completedAt ?? assessment?.completedAt;
    final hasAssessment = assessment != null;
    return WellarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayTarget,
                      style: const TextStyle(
                        color: WellarTheme.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    if ((item.requestedForEmail ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.requestedForEmail!.trim(),
                        style: const TextStyle(
                          color: WellarTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _requestStatusPill(item),
                  if ((item.requestedForRole ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    RoleChip(item.requestedForRole!.trim()),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (item.displayDepartment != '-')
                _metaPill(
                  icon: Icons.apartment_rounded,
                  label: item.displayDepartment,
                ),
              if (item.requiredMinReadinessLabel != null)
                _metaPill(
                  icon: Icons.verified_user_outlined,
                  label: item.requiredMinReadinessLabel!,
                ),
              if ((item.requestType ?? '').trim().isNotEmpty)
                _metaPill(
                  icon: Icons.layers_outlined,
                  label: _requestTypeLabel(item.requestType!),
                ),
              if (hasAssessment && assessment!.outcome != null)
                _resultBadge(assessment.outcome!),
              if (hasAssessment && assessment!.readinessScore != null)
                _scoreBadge(assessment.readinessScore!),
            ],
          ),
          const SizedBox(height: 10),
          if (normalized == NormalizedRequestStatus.completed &&
              completedAt != null) ...[
            Text(
              'Completed: ${_formatDateTime(completedAt)}',
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
          ],
          if (normalized == NormalizedRequestStatus.completed &&
              (!hasCompletedScan || !hasAssessment)) ...[
            const Text(
              'Assessment processing',
              style: TextStyle(color: WellarTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            '${Tr.t(lang, 'due_date')}: ${_formatDate(item.dueAt)}',
            style: const TextStyle(color: WellarTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            '${Tr.t(lang, 'requested_by')}: ${item.requestedByUserName ?? Tr.t(lang, 'workspace_admin')}',
            style: const TextStyle(color: WellarTheme.textMuted, fontSize: 12),
          ),
          if ((item.requestedByUserEmail ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.requestedByUserEmail!.trim(),
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                fadeSlideRoute(ScanRequestDetailsScreen(item: item)),
              ),
              child: Text(Tr.t(lang, 'view_details')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateDialog() async {
    final lang = ref.read(appLanguageControllerProvider).language;
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _CreateRequestDialog(),
    );
    if (!mounted || created != true) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(Tr.t(lang, 'request_sent_success'))));
    _reload();
  }

  Widget _requestStatusPill(RequestItem item) {
    final normalized = RequestStatusNormalizer.normalize(item);
    final Color color = normalized == NormalizedRequestStatus.completed
        ? const Color(0xFF72E3A6)
        : normalized == NormalizedRequestStatus.overdue
        ? const Color(0xFFFF9E7A)
        : const Color(0xFFF1C16B);
    final String label = normalized.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _resultBadge(String label) {
    final color = _resultColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _scoreBadge(String score) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x661E2C4A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2B3D5A)),
      ),
      child: Text(
        'Score $score',
        style: const TextStyle(
          color: WellarTheme.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Color _resultColor(String label) {
    final normalized = label.trim().toLowerCase();
    switch (normalized) {
      case 'stable':
        return const Color(0xFF72D8A0);
      case 'low focus':
      case 'low_focus':
        return const Color(0xFF6DAFEA);
      case 'elevated fatigue':
      case 'elevated_fatigue':
        return const Color(0xFFF4BE68);
      case 'high risk':
      case 'high_risk':
        return const Color(0xFFE38654);
      default:
        return WellarTheme.textMuted;
    }
  }

  Widget _metaPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x6621314B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2B3D5A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: WellarTheme.textMuted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _requestTypeLabel(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'department' || normalized == 'bulk') return 'Department';
    if (normalized == 'person' || normalized == 'manual') return 'Person';
    if (normalized == 'single') return 'Single';
    return normalized.isEmpty ? 'Request' : _titleCase(normalized);
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    return '$day/$month/$year';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _titleCase(String value) {
    return value
        .split(RegExp(r'[_\s]+'))
        .where((part) => part.trim().isNotEmpty)
        .map((part) {
          final trimmed = part.trim();
          return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
        })
        .join(' ');
  }
}

class _CreateRequestDialog extends ConsumerStatefulWidget {
  const _CreateRequestDialog();

  @override
  ConsumerState<_CreateRequestDialog> createState() =>
      _CreateRequestDialogState();
}

class _CreateRequestDialogState extends ConsumerState<_CreateRequestDialog> {
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _loadError;
  String? _submitError;

  bool _includeMyself = false;
  DateTime? _dueAt;

  List<RequestMemberOption> _allMembers = const [];
  RequestMemberOption? _selectedMember;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _currentUserId => Session.instance.userId?.trim() ?? '';
  String get _currentMemberId =>
      ref.read(activeWorkspaceContextProvider)?.membershipId.trim() ?? '';

  bool get _hasSelfMember {
    if (_currentMemberId.isNotEmpty) {
      return _allMembers.any((member) => member.memberId == _currentMemberId);
    }
    if (_currentUserId.isEmpty) return false;
    return _allMembers.any((member) => member.userId == _currentUserId);
  }

  List<RequestMemberOption> get _visibleMembers {
    final query = _searchController.text.trim().toLowerCase();
    return _allMembers.where((member) {
      if (!_includeMyself) {
        if (_currentMemberId.isNotEmpty &&
            member.memberId == _currentMemberId) {
          return false;
        }
        if (_currentMemberId.isEmpty &&
            _currentUserId.isNotEmpty &&
            member.userId == _currentUserId) {
          return false;
        }
      }
      if (query.isEmpty) return true;
      final haystack = [
        member.name,
        member.email,
        member.role,
        member.departmentName ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  bool get _canSubmit {
    if (_loading || _submitting) return false;
    return _selectedMember != null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _submitError = null;
    });
    try {
      _allMembers = await AdminRequestService.instance.fetchWorkspaceMembers();
      _syncSelections();
    } catch (error) {
      _loadError = _describeError(error);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
      initialDate: _dueAt ?? now,
    );
    if (date == null || !mounted) return;
    setState(() => _dueAt = date);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final member = _selectedMember;
      if (member == null) return;
      await AdminRequestService.instance.createPersonalRequest(
        targetMemberId: member.memberId,
        dueAt: _dueAt,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitError = _describeError(error));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _syncSelections() {
    final visibleMembers = _visibleMembers;
    if (_selectedMember == null ||
        !visibleMembers.any((m) => m.memberId == _selectedMember!.memberId)) {
      _selectedMember = null;
    }
  }

  String _describeError(Object error) {
    if (error is RequestCreateException) return error.message;
    final raw = error.toString().trim();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length).trim();
    }
    if (raw.isNotEmpty) return raw;
    final lang = ref.read(appLanguageControllerProvider).language;
    return Tr.t(lang, 'request_could_not_be_created');
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final media = MediaQuery.of(context);
    final visibleMembers = _visibleMembers;
    return AnimatedPadding(
      duration: WellarTheme.fast,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(16, 24, 16, media.viewInsets.bottom + 24),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: media.size.height * 0.86,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF263858)),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF101B30), Color(0xFF0B1324)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 36,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(child: SizedBox.shrink()),
                      Expanded(
                        flex: 8,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Tr.t(lang, 'create_readiness_request_title'),
                              style: const TextStyle(
                                color: WellarTheme.text,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              Tr.t(lang, 'create_readiness_request_subtitle'),
                              style: const TextStyle(
                                color: WellarTheme.textMuted,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: WellarTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: WellarTheme.primary,
                              strokeWidth: 2.2,
                            ),
                          )
                        : _loadError != null
                        ? WellarErrorState(
                            title: Tr.t(lang, 'access_unavailable'),
                            body: _loadError!,
                            onRetry: _load,
                          )
                        : SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  Tr.t(lang, 'target'),
                                  style: const TextStyle(
                                    color: WellarTheme.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _searchController,
                                  onChanged: (_) => setState(_syncSelections),
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.search),
                                    hintText: Tr.t(
                                      lang,
                                      'search_by_name_email',
                                    ),
                                  ),
                                ),
                                if (_hasSelfMember) ...[
                                  const SizedBox(height: 8),
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    value: _includeMyself,
                                    onChanged: (value) {
                                      setState(() {
                                        _includeMyself = value;
                                        _syncSelections();
                                      });
                                    },
                                    title: Text(
                                      Tr.t(lang, 'include_myself'),
                                      style: const TextStyle(
                                        color: WellarTheme.text,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                _memberList(lang, visibleMembers),
                                const SizedBox(height: 18),
                                Text(
                                  Tr.t(lang, 'request_details'),
                                  style: const TextStyle(
                                    color: WellarTheme.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _dateField(lang),
                                if (_submitError != null) ...[
                                  const SizedBox(height: 14),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0x33FF8A80),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0x66FF8A80),
                                      ),
                                    ),
                                    child: Text(
                                      _submitError!,
                                      style: const TextStyle(
                                        color: Color(0xFFFFD6D2),
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: WellarButton.secondary(
                          text: Tr.t(lang, 'cancel'),
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).maybePop(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: WellarButton.primary(
                          text: _submitting
                              ? Tr.t(lang, 'sending')
                              : Tr.t(lang, 'send_request'),
                          onPressed: _canSubmit ? _submit : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _memberList(dynamic lang, List<RequestMemberOption> members) {
    if (_allMembers.isEmpty) {
      return WellarEmptyState(
        icon: Icons.people_alt_outlined,
        title: Tr.t(lang, 'no_team_members_found'),
        body: Tr.t(lang, 'workforce_subtitle'),
      );
    }
    if (members.isEmpty) {
      return WellarEmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: Tr.t(lang, 'no_matching_members'),
        body: Tr.t(lang, 'search_by_name_email'),
      );
    }
    return SizedBox(
      height: 250,
      child: ListView.separated(
        itemCount: members.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final member = members[index];
          final selected = _selectedMember?.memberId == member.memberId;
          return InkWell(
            onTap: _submitting
                ? null
                : () => setState(() => _selectedMember = member),
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: WellarTheme.fast,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: selected
                    ? const Color(0x331FD1BE)
                    : const Color(0x88131F36),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF38D7C7)
                      : const Color(0xFF253754),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.name,
                          style: const TextStyle(
                            color: WellarTheme.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          member.email.isNotEmpty
                              ? member.email
                              : MemberIdentityService.emailUnavailableLabel,
                          style: const TextStyle(
                            color: WellarTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            RoleChip(member.role),
                            if ((member.departmentName ?? '').trim().isNotEmpty)
                              _smallPill(member.departmentName!.trim()),
                            _smallPill(member.status),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _selectionIndicator(selected),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _dateField(dynamic lang) {
    final label = _dueAt == null
        ? Tr.t(lang, 'due_date')
        : _formatDate(_dueAt!);
    return InkWell(
      onTap: _submitting ? null : _pickDueDate,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0x88131F36),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF253754)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.event_outlined,
              color: WellarTheme.primary,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Tr.t(lang, 'due_date'),
                    style: const TextStyle(
                      color: WellarTheme.textMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      color: WellarTheme.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: WellarTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x6621314B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2B3D5A)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: WellarTheme.textMuted,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _selectionIndicator(bool selected) {
    return AnimatedContainer(
      duration: WellarTheme.fast,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? WellarTheme.primary : Colors.transparent,
        border: Border.all(
          color: selected ? WellarTheme.primary : const Color(0xFF41587D),
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 14, color: Colors.black)
          : null,
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    return '$day/$month/$year';
  }
}
