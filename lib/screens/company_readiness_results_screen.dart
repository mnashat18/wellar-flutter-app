import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/directus_client.dart';
import '../services/hr_ops_service.dart';
import '../services/organization_service.dart';
import '../services/owner_ops_service.dart';
import '../models/request_item.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../utils/page_transition.dart';
import '../utils/request_status_normalizer.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/owner/owner_design_system.dart';
import '../services/request_service.dart';
import 'scan_details_screen.dart';

/// Owner + HR readiness distribution drilldown.
///
/// Tab 1 (Readiness results) drills into the four buckets that back the
/// Readiness Distribution card. Section counts are read from the same
/// `WorkspaceReadinessSummary.distribution` map that the card renders, and
/// row content is read from the same `WorkspaceReadinessSummary.resultsByScanId`
/// map — so counts and rows are literally the same source of truth.
///
/// Tab 2 (Scan requests) is a request-centric view scoped to the active
/// business_profile: request summary + Pending / Overdue / Completed groups.
class CompanyReadinessResultsScreen extends StatefulWidget {
  final WorkspaceReadinessSummary? initialSummary;
  final DateTime? start;
  final DateTime? end;
  final String? periodLabel;

  const CompanyReadinessResultsScreen({
    super.key,
    this.initialSummary,
    this.start,
    this.end,
    this.periodLabel,
  });

  @override
  State<CompanyReadinessResultsScreen> createState() =>
      _CompanyReadinessResultsScreenState();
}

class _CompanyReadinessResultsScreenState
    extends State<CompanyReadinessResultsScreen>
    with SingleTickerProviderStateMixin {
  late Future<_ScreenSnapshot> _future;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _future = _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<_ScreenSnapshot> _load() async {
    // Scope: active business_profile only. HR + Owner share this code path.
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final profileId = workspace?.businessProfileId.trim() ?? '';
    final currentUserId = workspace?.currentUserId.trim().isNotEmpty == true
        ? workspace!.currentUserId.trim()
        : (Session.instance.userId?.trim() ?? 'missing');
    final membershipId = workspace?.membershipId.trim() ?? 'missing';
    final effectiveRole =
        workspace?.finalEffectiveRole ?? workspace?.memberRole ?? 'missing';
    debugPrint(
      '[COMPANY_READINESS_TRACE] user_id=$currentUserId membership_id=$membershipId business_profile=$profileId effective_role=$effectiveRole workspace_revision=${OrganizationService.instance.workspaceRevision} workspace_signature=${OrganizationService.instance.workspaceSignature}',
    );
    if (profileId.isEmpty) {
      debugPrint(
        '[HR_READINESS_TRACE] profile_present=false result_count=0 request_count=0 results_query_failed=false requests_query_failed=false scans_query_failed=false',
      );
      return _ScreenSnapshot.empty();
    }

    WorkspaceReadinessSummary? summary = widget.initialSummary;
    var resultsQueryFailed = summary?.queryFailed ?? false;
    if (summary == null) {
      // Same source as the Readiness Distribution card on Owner Home,
      // Owner Reports, and HR Compliance:
      // OwnerOpsService.fetchWorkspaceReadinessSummary. distribution and
      // resultsByScanId are populated in the same loop, so their counts are
      // guaranteed to match.
      try {
        summary = await OwnerOpsService.instance.fetchWorkspaceReadinessSummary(
          start: widget.start,
          end: widget.end,
        );
        resultsQueryFailed = summary.queryFailed;
      } catch (_) {
        summary = WorkspaceReadinessSummary(
          distribution: const {
            'Stable': 0,
            'Low Focus': 0,
            'Elevated Fatigue': 0,
            'High Risk': 0,
          },
          resultsByScanId: const <String, OwnerAssessmentResult>{},
          queryFailed: true,
        );
        resultsQueryFailed = true;
      }
    }

    // Members (for name/role/department resolution) — scoped to the same
    // profile via OwnerOpsService.fetchWorkforceDirectory.
    final memberDirectory = await _loadCompanyMemberDirectory(
      effectiveRole: effectiveRole,
      profileId: profileId,
      membershipId: membershipId,
    );
    debugPrint(
      '[COMPANY_DIRECTORY_READY] members=${memberDirectory.members.length} user_keys=${memberDirectory.byUserId.length} membership_keys=${memberDirectory.byMembershipId.length}',
    );

    // Scan → user linkage AND scan → status. Required to attribute each
    // scan_result row to a specific member AND to answer Tab 2's
    // "Processing assessment" vs "Retake needed" branches truthfully.
    // Scoped strictly to the active business_profile.
    final scansFetch = await _fetchWellnessScans(profileId);
    final scanMetaById = scansFetch.data;

    // Scan requests for Tab 2. Scoped to the active business_profile.
    final requestsFetch = await _fetchResolvedCompanyRequests(
      effectiveRole: effectiveRole,
    );
    final requestItems = requestsFetch.data;
    final requestMemberIdByScanId = <String, String>{};
    final requestUserIdByScanId = <String, String>{};
    final requestItemByScanId = <String, RequestItem>{};
    for (final item in requestItems) {
      final completedScanId = item.scanId?.trim() ?? '';
      if (completedScanId.isEmpty) continue;
      requestItemByScanId.putIfAbsent(completedScanId, () => item);
      final targetMemberId = _normalizeMembershipKey(item.requestedForId);
      final requestedUserId = _normalizeUserKey(item.requestedForUserId);
      if (targetMemberId.isNotEmpty) {
        requestMemberIdByScanId.putIfAbsent(
          completedScanId,
          () => targetMemberId,
        );
      }
      if (requestedUserId.isNotEmpty) {
        requestUserIdByScanId.putIfAbsent(
          completedScanId,
          () => requestedUserId,
        );
      }
    }

    // Build Tab 1: readiness result rows from the exact same
    // resultsByScanId map that backs the distribution counts.
    final results =
        summary?.resultsByScanId.values.toList() ??
        const <OwnerAssessmentResult>[];
    final resultRows = <_ResultRow>[];
    var resolvedDirectUserCount = 0;
    var resolvedDirectMembershipCount = 0;
    var resolvedViaRequestCount = 0;
    var unresolvedCount = 0;
    for (final assessment in results) {
      final scanId = assessment.scanId.trim();
      if (scanId.isEmpty) continue;
      final outcome = assessment.outcome?.trim() ?? '';
      final bucket = _bucketFromLabel(outcome);
      if (bucket == null) continue;
      final scanMeta = scanMetaById[scanId];
      final userId = _normalizeUserKey(scanMeta?.userId);
      final requestMembershipId = requestMemberIdByScanId[scanId] ?? '';
      final requestUserId = requestUserIdByScanId[scanId] ?? '';
      final requestItem = requestItemByScanId[scanId];
      final resolution = memberDirectory.resolveResultMember(
        scanMembershipId: null,
        scanUserId: userId,
        resultMembershipId: requestMembershipId,
        resultUserId: requestUserId,
      );
      final member = resolution.member;
      final requestName =
          _humanReadableLabel(requestItem?.requestedForName) ?? '';
      final requestEmail =
          _humanReadableLabel(requestItem?.requestedForEmail) ?? '';
      final requestRole =
          _humanReadableLabel(requestItem?.requestedForRole) ?? '';
      final requestDepartment =
          _humanReadableLabel(requestItem?.departmentName) ?? '';
      final memberDepartmentName = (member?.departmentName ?? '').trim();
      final resolvedDepartmentName = memberDepartmentName.isNotEmpty
          ? memberDepartmentName
          : requestDepartment;
      final fallbackName = requestName.isNotEmpty
          ? requestName
          : (requestEmail.isNotEmpty
                ? requestEmail.split('@').first
                : 'Member unavailable');
      final hasRequestFallback =
          requestName.isNotEmpty ||
          requestEmail.isNotEmpty ||
          requestRole.isNotEmpty ||
          requestDepartment.isNotEmpty;
      if (member == null && !hasRequestFallback) {
        unresolvedCount += 1;
        debugPrint(
          '[COMPANY_RESULT_UNRESOLVED] result_id=${assessment.scanId} scan_id=$scanId has_user_id=${userId.isNotEmpty || requestUserId.isNotEmpty} has_membership_id=${requestMembershipId.isNotEmpty} has_matching_request=${requestMembershipId.isNotEmpty || requestUserId.isNotEmpty}',
        );
      } else if (member != null) {
        switch (resolution.source) {
          case _MemberResolutionSource.directUser:
            resolvedDirectUserCount += 1;
            break;
          case _MemberResolutionSource.directMembership:
            resolvedDirectMembershipCount += 1;
            break;
          case _MemberResolutionSource.requestMembership:
          case _MemberResolutionSource.requestUser:
            resolvedViaRequestCount += 1;
            break;
          case _MemberResolutionSource.unresolved:
            unresolvedCount += 1;
            break;
        }
      } else {
        resolvedViaRequestCount += 1;
      }
      resultRows.add(
        _ResultRow(
          scanId: scanId,
          bucket: bucket,
          memberName: member?.displayName ?? fallbackName,
          memberEmail: member?.displayEmail ?? requestEmail,
          roleLabel: member?.roleLabel ?? requestRole,
          departmentLabel: resolvedDepartmentName,
          completedAt: assessment.completedAt,
          readinessScore: assessment.readinessScore,
        ),
      );
    }
    debugPrint(
      '[COMPANY_RESULT_RESOLUTION] results=${resultRows.length} resolved_direct_user=$resolvedDirectUserCount resolved_direct_membership=$resolvedDirectMembershipCount resolved_via_request=$resolvedViaRequestCount unresolved=$unresolvedCount',
    );
    resultRows.sort((a, b) {
      final aTime = a.completedAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.completedAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });

    // Distribution used for section headers — read directly from the
    // service's distribution map, not recomputed. This is the same value
    // rendered by the Readiness Distribution card.
    final distribution = <_ResultBucket, int>{
      for (final bucket in _ResultBucket.values)
        bucket: summary?.distribution[bucket.serviceKey] ?? 0,
    };

    // Build Tab 2: request rows.
    final requestScanIds = <String>{};
    for (final item in requestItems) {
      final scanId = item.scanId?.trim() ?? '';
      if (scanId.isNotEmpty) requestScanIds.add(scanId);
    }
    // Assessment lookup for completed request outcomes. Uses the same
    // Directus deep-relation query Owner already relies on.
    var assessmentsByScanId = const <String, OwnerAssessmentResult>{};
    var assessmentQueryFailed = false;
    if (requestScanIds.isNotEmpty) {
      try {
        final lookup = await OwnerOpsService.instance
            .fetchAssessmentResultsByScanIds(scanIds: requestScanIds.toList());
        assessmentsByScanId = lookup.resultsByScanId;
        assessmentQueryFailed = lookup.queryFailed;
      } catch (_) {
        assessmentQueryFailed = true;
      }
    }

    // For any request whose completed_scan id was not returned by the
    // primary wellness_scans fetch (limit cutoff, older scan, etc.), fill
    // both userId and status from a targeted lookup so no request row is
    // left with a blank status.
    if (requestScanIds.isNotEmpty) {
      final missingScanIds = requestScanIds
          .where((id) => !scanMetaById.containsKey(id))
          .toList();
      if (missingScanIds.isNotEmpty) {
        final extra = await _fetchScansByIds(profileId, missingScanIds);
        for (final entry in extra.entries) {
          scanMetaById[entry.key] = entry.value;
        }
      }
    }

    final now = DateTime.now();
    final requestRowsBuilt = <_RequestRow>[];
    for (final requestItem in requestItems) {
      final targetMemberId = _normalizeMembershipKey(
        requestItem.requestedForId,
      );
      final requestType = _requestKind(
        targetMemberId: targetMemberId,
        departmentId: _normalizeMembershipKey(requestItem.departmentId),
      );
      final member = memberDirectory.resolveRequestMember(
        membershipId: requestItem.requestedForId,
        userId: requestItem.requestedForUserId,
      );
      final memberDepartmentName = (member?.departmentName ?? '').trim();
      final recipientName =
          member?.displayName ??
          _humanReadableLabel(requestItem.requestedForName) ??
          _humanReadableLabel(requestItem.requestedForEmail) ??
          'Recipient unavailable';
      final recipientEmail =
          member?.displayEmail ??
          _humanReadableLabel(requestItem.requestedForEmail) ??
          '';
      final recipientRole =
          member?.roleLabel ??
          _humanReadableLabel(requestItem.requestedForRole) ??
          '';
      final departmentName = memberDepartmentName.isNotEmpty
          ? memberDepartmentName
          : _humanReadableLabel(requestItem.departmentName) ?? '';
      final unresolvedRequest =
          member == null &&
          _humanReadableLabel(requestItem.requestedForName) == null &&
          _humanReadableLabel(requestItem.requestedForEmail) == null;
      if (unresolvedRequest) {
        debugPrint(
          '[COMPANY_REQUEST_MEMBER_UNRESOLVED] request_id=${requestItem.id} has_target_member=${targetMemberId.isNotEmpty} has_recipient_user=${_normalizeUserKey(requestItem.requestedForUserId).isNotEmpty}',
        );
      }
      final normalized = RequestStatusNormalizer.normalizeRaw(
        requestId: requestItem.id,
        rawStatus: requestItem.displayStatus,
        dueAt: requestItem.dueAt,
        completedScanId: requestItem.scanId?.trim() ?? '',
        now: now,
        log: false,
      );
      final completedScanId = requestItem.scanId?.trim() ?? '';
      final assessment = completedScanId.isEmpty
          ? null
          : assessmentsByScanId[completedScanId];
      final scanStatus = completedScanId.isEmpty
          ? ''
          : scanMetaById[completedScanId]?.status ?? '';
      final outcome = _resolveRequestOutcome(
        normalized: normalized,
        completedScanId: completedScanId,
        assessment: assessment,
        scanStatus: scanStatus,
        assessmentQueryFailed: assessmentQueryFailed,
      );
      requestRowsBuilt.add(
        _RequestRow(
          requestId: requestItem.id,
          type: requestType,
          memberName: recipientName,
          memberEmail: recipientEmail,
          roleLabel: recipientRole,
          departmentLabel: departmentName,
          status: normalized,
          requestedAt: requestItem.timestamp,
          dueAt: requestItem.dueAt,
          completedAt: requestItem.completedAt,
          completedScanId: _isCompletedBucket(outcome.bucket)
              ? completedScanId
              : null,
          outcome: outcome,
        ),
      );
    }
    debugPrint(
      "[COMPANY_REQUEST_RESOLUTION] requests=${requestRowsBuilt.length} resolved=${requestRowsBuilt.where((row) => (row.memberName ?? '').trim() != 'Recipient unavailable' || row.memberEmail.trim().isNotEmpty || row.roleLabel.trim().isNotEmpty || row.departmentLabel.trim().isNotEmpty).length} unresolved=${requestRowsBuilt.where((row) => (row.memberName ?? '').trim() == 'Recipient unavailable' && row.memberEmail.trim().isEmpty && row.roleLabel.trim().isEmpty && row.departmentLabel.trim().isEmpty).length}",
    );

    final requestSummary = _RequestSummary.build(requestRowsBuilt);

    debugPrint(
      '[HR_READINESS_TRACE] profile_present=true '
      'result_count=${resultRows.length} '
      'request_count=${requestRowsBuilt.length} '
      'results_query_failed=$resultsQueryFailed '
      'requests_query_failed=${!requestsFetch.ok} '
      'scans_query_failed=${!scansFetch.ok}',
    );

    return _ScreenSnapshot(
      resultRows: resultRows,
      distribution: distribution,
      requestRows: requestRowsBuilt,
      requestSummary: requestSummary,
      resultsQueryFailed: resultsQueryFailed,
      requestsQuery: requestsFetch.outcome,
      scansQuery: scansFetch.outcome,
      assessmentQueryFailed: assessmentQueryFailed,
    );
  }

  Future<_QueryResult<Map<String, _ScanMeta>>> _fetchWellnessScans(
    String profileId,
  ) async {
    try {
      final res = await DirectusClient.instance.client.get(
        '/items/wellness_scans',
        queryParameters: {
          'limit': 1200,
          'sort': '-date_created',
          'fields': 'id,user,status,business_profile,completed_at,date_created',
          'filter[business_profile][_eq]': profileId,
        },
      );
      final data = res.data['data'];
      final rows = data is List
          ? data.whereType<Map<String, dynamic>>().toList()
          : const <Map<String, dynamic>>[];
      final map = <String, _ScanMeta>{};
      for (final row in rows) {
        final id = row['id']?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        map[id] = _ScanMeta(
          userId: _relationId(row['user']),
          status: row['status']?.toString().trim().toLowerCase() ?? '',
        );
      }
      return _QueryResult(map, const _QueryOutcome.ok());
    } on DioException catch (e) {
      debugPrint(
        '[COMPANY_READINESS] wellness_scans query_failed status=${e.response?.statusCode}',
      );
      return _QueryResult(
        <String, _ScanMeta>{},
        _QueryOutcome.failed(e.response?.statusCode),
      );
    } catch (_) {
      debugPrint('[COMPANY_READINESS] wellness_scans query_failed status=null');
      return _QueryResult(
        <String, _ScanMeta>{},
        const _QueryOutcome.failed(null),
      );
    }
  }

  Future<Map<String, _ScanMeta>> _fetchScansByIds(
    String profileId,
    List<String> scanIds,
  ) async {
    if (scanIds.isEmpty) return const {};
    try {
      final res = await DirectusClient.instance.client.get(
        '/items/wellness_scans',
        queryParameters: {
          'limit': scanIds.length,
          'fields': 'id,user,status,business_profile,completed_at,date_created',
          'filter[business_profile][_eq]': profileId,
          'filter[id][_in]': scanIds.join(','),
        },
      );
      final data = res.data['data'];
      final rows = data is List
          ? data.whereType<Map<String, dynamic>>().toList()
          : const <Map<String, dynamic>>[];
      final map = <String, _ScanMeta>{};
      for (final row in rows) {
        final id = row['id']?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        map[id] = _ScanMeta(
          userId: _relationId(row['user']),
          status: row['status']?.toString().trim().toLowerCase() ?? '',
        );
      }
      return map;
    } catch (_) {
      return const {};
    }
  }

  Future<_QueryResult<List<RequestItem>>> _fetchResolvedCompanyRequests({
    required String effectiveRole,
  }) async {
    try {
      final normalizedRole = effectiveRole.trim().toLowerCase();
      final items = normalizedRole == 'owner'
          ? await RequestService.instance.fetchOwnerRequests()
          : await RequestService.instance.fetchHrRequests();
      return _QueryResult(items, const _QueryOutcome.ok());
    } on RequestPermissionException catch (_) {
      debugPrint(
        '[COMPANY_READINESS] request_source_failed permission_error=true',
      );
      return _QueryResult(
        const <RequestItem>[],
        const _QueryOutcome.failed(null),
      );
    } catch (_) {
      debugPrint(
        '[COMPANY_READINESS] request_source_failed permission_error=false',
      );
      return _QueryResult(
        const <RequestItem>[],
        const _QueryOutcome.failed(null),
      );
    }
  }

  _RequestKind _requestKind({
    required String targetMemberId,
    required String departmentId,
  }) {
    if (targetMemberId.isNotEmpty) return _RequestKind.individual;
    if (departmentId.isNotEmpty) return _RequestKind.department;
    return _RequestKind.individual;
  }

  _RequestOutcome _resolveRequestOutcome({
    required NormalizedRequestStatus normalized,
    required String completedScanId,
    required OwnerAssessmentResult? assessment,
    required String scanStatus,
    required bool assessmentQueryFailed,
  }) {
    if (normalized == NormalizedRequestStatus.completed) {
      if (completedScanId.isEmpty) {
        return const _RequestOutcome(bucket: null, label: 'Result unavailable');
      }
      if (assessment != null) {
        final bucket = _bucketFromLabel(assessment.outcome?.trim() ?? '');
        if (bucket != null &&
            _isValidReadinessScore(assessment.readinessScore)) {
          return _RequestOutcome(bucket: bucket, label: bucket.label);
        }
        return const _RequestOutcome(
          bucket: null,
          label: 'Result requires review',
        );
      }
      if (assessmentQueryFailed) {
        return const _RequestOutcome(bucket: null, label: 'Result unavailable');
      }
      return const _RequestOutcome(bucket: null, label: 'Result processing');
    }
    if (normalized == NormalizedRequestStatus.pending) {
      if (scanStatus == 'failed' ||
          scanStatus == 'error' ||
          scanStatus == 'rejected' ||
          scanStatus == 'cancelled') {
        return const _RequestOutcome(bucket: null, label: 'Retake needed');
      }
      if (scanStatus.isNotEmpty && scanStatus != 'completed') {
        return const _RequestOutcome(
          bucket: null,
          label: 'Processing assessment',
        );
      }
      return const _RequestOutcome(bucket: null, label: 'Not started');
    }
    if (normalized == NormalizedRequestStatus.overdue) {
      if (scanStatus == 'failed' ||
          scanStatus == 'error' ||
          scanStatus == 'rejected' ||
          scanStatus == 'cancelled') {
        return const _RequestOutcome(bucket: null, label: 'Retake needed');
      }
      return const _RequestOutcome(bucket: null, label: 'Past due');
    }
    return const _RequestOutcome(bucket: null, label: 'Cancelled');
  }

  bool _isCompletedBucket(_ResultBucket? bucket) => bucket != null;

  bool _isValidReadinessScore(String? scoreText) {
    final value = scoreText?.trim() ?? '';
    if (value.isEmpty) return false;
    final parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) return false;
    return true;
  }

  _ResultBucket? _bucketFromLabel(String outcome) {
    switch (outcome.toLowerCase()) {
      case 'stable':
        return _ResultBucket.stable;
      case 'low focus':
      case 'low_focus':
        return _ResultBucket.lowFocus;
      case 'elevated fatigue':
      case 'elevated_fatigue':
        return _ResultBucket.elevatedFatigue;
      case 'high risk':
      case 'high_risk':
        return _ResultBucket.highRisk;
      default:
        return null;
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _relationId(dynamic value) {
    if (value == null) return '';
    if (value is Map) {
      return value['id']?.toString().trim() ?? '';
    }
    return value.toString().trim();
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    return '$d/$m/$y';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Company readiness'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: WellarTheme.text,
        bottom: TabBar(
          controller: _tabController,
          labelColor: WellarTheme.text,
          unselectedLabelColor: WellarTheme.textMuted,
          indicatorColor: WellarTheme.primary,
          tabs: const [
            Tab(text: 'Readiness results'),
            Tab(text: 'Scan requests'),
          ],
        ),
      ),
      body: AnimatedWellarScreen(
        showBackground: false,
        padding: EdgeInsets.zero,
        child: FutureBuilder<_ScreenSnapshot>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: WellarTheme.primary,
                ),
              );
            }
            if (snapshot.hasError) {
              return SmartEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Unable to load company readiness',
                subtitle: 'Please try again.',
                actionLabel: 'Retry',
                onAction: () => setState(() => _future = _load()),
              );
            }
            final data = snapshot.data ?? _ScreenSnapshot.empty();
            return TabBarView(
              controller: _tabController,
              children: [
                _ReadinessResultsTab(
                  data: data,
                  onRetry: () => setState(() => _future = _load()),
                  onOpenScan: _openScanDetails,
                  formatDateTime: _formatDateTime,
                  periodLabel: widget.periodLabel,
                ),
                _ScanRequestsTab(
                  data: data,
                  onRetry: () => setState(() => _future = _load()),
                  onOpenScan: _openScanDetails,
                  formatDate: _formatDate,
                  formatDateTime: _formatDateTime,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openScanDetails(String scanId) {
    final trimmed = scanId.trim();
    if (trimmed.isEmpty) return;
    Navigator.push(context, fadeSlideRoute(ScanDetailsScreen(scanId: trimmed)));
  }
}

/// Readiness results tab: four grouped sections, one row per valid completed
/// scan_result. Section counts read directly from the same distribution map
/// that backs the Readiness Distribution card.
class _ReadinessResultsTab extends StatelessWidget {
  final _ScreenSnapshot data;
  final VoidCallback onRetry;
  final void Function(String) onOpenScan;
  final String Function(DateTime?) formatDateTime;
  final String? periodLabel;

  const _ReadinessResultsTab({
    required this.data,
    required this.onRetry,
    required this.onOpenScan,
    required this.formatDateTime,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = periodLabel == null
        ? 'Every valid completed scan result grouped into the same four buckets used by the Readiness Distribution card.'
        : 'Completed scan results for $periodLabel.';
    final byBucket = <_ResultBucket, List<_ResultRow>>{
      for (final bucket in _ResultBucket.values) bucket: <_ResultRow>[],
    };
    for (final row in data.resultRows) {
      byBucket[row.bucket]!.add(row);
    }
    final banners = <Widget>[];
    if (data.resultsQueryFailed) {
      banners.add(
        _queryFailureBanner(
          title: 'Assessment data unavailable',
          subtitle: 'scan_results query failed — tap to retry.',
          onRetry: onRetry,
        ),
      );
    }
    if (!data.scansQuery.ok) {
      banners.add(
        _queryFailureBanner(
          title: 'Scan data unavailable',
          subtitle: data.scansQuery.isForbidden
              ? 'Directus refused wellness_scans read for this session.'
              : 'wellness_scans query failed — tap to retry.',
          onRetry: onRetry,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
          SectionHeader(
            title: 'Readiness distribution',
            subtitle: subtitle,
          ),
          const SizedBox(height: 12),
          ...banners,
          for (final bucket in _ResultBucket.values)
            _bucketSection(
              bucket: bucket,
              count: data.distribution[bucket] ?? 0,
              rows: byBucket[bucket] ?? const <_ResultRow>[],
            ),
        ],
      ),
    );
  }

  Widget _bucketSection({
    required _ResultBucket bucket,
    required int count,
    required List<_ResultRow> rows,
  }) {
    final color = _bucketColor(bucket);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text(
                '${bucket.label} ($count)',
                style: const TextStyle(
                  color: WellarTheme.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            _emptyBucket(bucket)
          else
            ...rows.map((row) => _resultCard(row, color)),
        ],
      ),
    );
  }

  Widget _emptyBucket(_ResultBucket bucket) {
    return OwnerSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Text(
        'No ${bucket.label.toLowerCase()} results yet.',
        style: const TextStyle(color: WellarTheme.textMuted, fontSize: 12.5),
      ),
    );
  }

  Widget _resultCard(_ResultRow row, Color color) {
    final subtitle = _joinNonEmpty([row.roleLabel, row.departmentLabel]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OwnerSurfaceCard(
        onTap: () => onOpenScan(row.scanId),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InitialsAvatar(label: row.memberName, size: 40, accent: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.memberName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WellarTheme.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (row.memberEmail.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      row.memberEmail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WellarTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WellarTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      TonePill(
                        label: row.bucket.label,
                        color: color,
                        fontSize: 10.5,
                      ),
                      if (row.readinessScore != null &&
                          row.readinessScore!.isNotEmpty)
                        TonePill(
                          label: 'Score ${row.readinessScore}',
                          color: WellarTheme.primary,
                          fontSize: 10.5,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Assessed ${formatDateTime(row.completedAt)}',
                    style: const TextStyle(
                      color: WellarTheme.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: WellarTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Scan requests tab: summary counts + Pending / Overdue / Completed groups.
class _ScanRequestsTab extends StatelessWidget {
  final _ScreenSnapshot data;
  final VoidCallback onRetry;
  final void Function(String) onOpenScan;
  final String Function(DateTime?) formatDate;
  final String Function(DateTime?) formatDateTime;

  const _ScanRequestsTab({
    required this.data,
    required this.onRetry,
    required this.onOpenScan,
    required this.formatDate,
    required this.formatDateTime,
  });

  @override
  Widget build(BuildContext context) {
    final summary = data.requestSummary;
    final pending = <_RequestRow>[];
    final overdue = <_RequestRow>[];
    final completed = <_RequestRow>[];
    for (final row in data.requestRows) {
      switch (row.status) {
        case NormalizedRequestStatus.pending:
          pending.add(row);
          break;
        case NormalizedRequestStatus.overdue:
          overdue.add(row);
          break;
        case NormalizedRequestStatus.completed:
          completed.add(row);
          break;
        case NormalizedRequestStatus.cancelled:
          break;
      }
    }
    final banners = <Widget>[];
    if (!data.requestsQuery.ok) {
      banners.add(
        _queryFailureBanner(
          title: 'Request data unavailable',
          subtitle: data.requestsQuery.isForbidden
              ? 'Directus refused scan_requests read for this session.'
              : 'scan_requests query failed — tap to retry.',
          onRetry: onRetry,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const SectionHeader(
            title: 'Scan requests',
            subtitle: 'Request-based view of every relevant assignment.',
          ),
          const SizedBox(height: 12),
          ...banners,
          _summaryCard(summary),
          const SizedBox(height: 18),
          _requestGroup(
            title: 'Pending requests',
            rows: pending,
            emptyMessage: 'No pending requests.',
          ),
          _requestGroup(
            title: 'Overdue requests',
            rows: overdue,
            emptyMessage: 'No overdue requests.',
          ),
          _requestGroup(
            title: 'Completed requests',
            rows: completed,
            emptyMessage: 'No completed requests.',
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(_RequestSummary summary) {
    Widget metric(String label, int value, Color color) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_valueForLabel(summary, label)}',
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ],
        ),
      );
    }

    return OwnerSurfaceCard(
      child: Wrap(
        spacing: 18,
        runSpacing: 10,
        children: [
          metric('Required', summary.required, WellarTheme.text),
          metric('Completed', summary.completed, const Color(0xFF6EE7A8)),
          metric('Pending', summary.pending, const Color(0xFF7DBBFF)),
          metric('Overdue', summary.overdue, const Color(0xFFFFC46B)),
        ],
      ),
    );
  }

  int _valueForLabel(_RequestSummary s, String label) {
    switch (label) {
      case 'Required':
        return s.required;
      case 'Completed':
        return s.completed;
      case 'Pending':
        return s.pending;
      case 'Overdue':
        return s.overdue;
    }
    return 0;
  }

  Widget _requestGroup({
    required String title,
    required List<_RequestRow> rows,
    required String emptyMessage,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title (${rows.length})',
            style: const TextStyle(
              color: WellarTheme.text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            OwnerSurfaceCard(
              padding: const EdgeInsets.all(14),
              child: Text(
                emptyMessage,
                style: const TextStyle(
                  color: WellarTheme.textMuted,
                  fontSize: 12.5,
                ),
              ),
            )
          else
            ...rows.map(_requestCard),
        ],
      ),
    );
  }

  Widget _requestCard(_RequestRow row) {
    final statusColor = _requestStatusColor(row.status);
    final outcomeColor = row.outcome.bucket != null
        ? _bucketColor(row.outcome.bucket!)
        : WellarTheme.textMuted;
    final tappable =
        (row.completedScanId ?? '').isNotEmpty && row.outcome.bucket != null;
    final resolvedMemberName = (row.memberName ?? '').trim();
    final displayName = row.type == _RequestKind.department
        ? (row.departmentLabel.isNotEmpty
              ? 'Department request - ${row.departmentLabel}'
              : 'Department request')
        : (resolvedMemberName.isNotEmpty
              ? resolvedMemberName
              : 'Recipient unavailable');
    final displayEmail = row.memberEmail.trim();
    final subtitle = row.type == _RequestKind.department
        ? 'Department request'
        : _joinNonEmpty([row.roleLabel, row.departmentLabel]);
    final typeLabel = row.type == _RequestKind.department
        ? 'Department request'
        : 'Individual request';
    final requestedText = row.requestedAt == null
        ? null
        : 'Requested ${formatDate(row.requestedAt)}';
    final dueText = row.dueAt == null ? null : 'Due ${formatDate(row.dueAt)}';
    final completedText = row.completedAt == null
        ? null
        : 'Completed ${formatDateTime(row.completedAt)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OwnerSurfaceCard(
        onTap: tappable ? () => onOpenScan(row.completedScanId!) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InitialsAvatar(
              label: row.type == _RequestKind.department
                  ? (row.departmentLabel.isNotEmpty
                        ? row.departmentLabel
                        : 'Department')
                  : displayName,
              size: 40,
              accent: statusColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WellarTheme.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (displayEmail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      displayEmail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WellarTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WellarTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      TonePill(
                        label: typeLabel,
                        color: WellarTheme.primary,
                        fontSize: 10.5,
                      ),
                      TonePill(
                        label: 'Request: ${row.status.label}',
                        color: statusColor,
                        fontSize: 10.5,
                      ),
                      TonePill(
                        label: 'Result: ${row.outcome.label}',
                        color: outcomeColor,
                        fontSize: 10.5,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (requestedText != null)
                        Text(
                          requestedText,
                          style: const TextStyle(
                            color: WellarTheme.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      if (dueText != null)
                        Text(
                          dueText,
                          style: const TextStyle(
                            color: WellarTheme.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      if (completedText != null)
                        Text(
                          completedText,
                          style: const TextStyle(
                            color: WellarTheme.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (tappable)
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: WellarTheme.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}

Widget _queryFailureBanner({
  required String title,
  required String subtitle,
  required VoidCallback onRetry,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: OwnerSurfaceCard(
      padding: const EdgeInsets.all(14),
      onTap: onRetry,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFFC46B),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: WellarTheme.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: WellarTheme.textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.refresh_rounded,
            size: 18,
            color: WellarTheme.textMuted,
          ),
        ],
      ),
    ),
  );
}

String _joinNonEmpty(List<String?> parts) {
  final buffer = <String>[];
  for (final part in parts) {
    final trimmed = part?.trim() ?? '';
    if (trimmed.isEmpty) continue;
    buffer.add(trimmed);
  }
  return buffer.join(' | ');
}

Color _bucketColor(_ResultBucket bucket) {
  switch (bucket) {
    case _ResultBucket.stable:
      return const Color(0xFF6EE7A8);
    case _ResultBucket.lowFocus:
      return const Color(0xFF7DBBFF);
    case _ResultBucket.elevatedFatigue:
      return const Color(0xFFFFC46B);
    case _ResultBucket.highRisk:
      return const Color(0xFFFF7A8F);
  }
}

Color _requestStatusColor(NormalizedRequestStatus status) {
  switch (status) {
    case NormalizedRequestStatus.pending:
      return const Color(0xFF7DBBFF);
    case NormalizedRequestStatus.overdue:
      return const Color(0xFFFFC46B);
    case NormalizedRequestStatus.completed:
      return const Color(0xFF6EE7A8);
    case NormalizedRequestStatus.cancelled:
      return const Color(0xFF6B7A99);
  }
}

enum _ResultBucket {
  stable,
  lowFocus,
  elevatedFatigue,
  highRisk;

  String get label {
    switch (this) {
      case _ResultBucket.stable:
        return 'Stable';
      case _ResultBucket.lowFocus:
        return 'Low Focus';
      case _ResultBucket.elevatedFatigue:
        return 'Elevated Fatigue';
      case _ResultBucket.highRisk:
        return 'High Risk';
    }
  }

  /// Keys used by [WorkspaceReadinessSummary.distribution].
  String get serviceKey {
    switch (this) {
      case _ResultBucket.stable:
        return 'Stable';
      case _ResultBucket.lowFocus:
        return 'Low Focus';
      case _ResultBucket.elevatedFatigue:
        return 'Elevated Fatigue';
      case _ResultBucket.highRisk:
        return 'High Risk';
    }
  }
}

enum _RequestKind { individual, department }

class _ResultRow {
  final String scanId;
  final _ResultBucket bucket;
  final String memberName;
  final String memberEmail;
  final String roleLabel;
  final String departmentLabel;
  final DateTime? completedAt;
  final String? readinessScore;

  const _ResultRow({
    required this.scanId,
    required this.bucket,
    required this.memberName,
    required this.memberEmail,
    required this.roleLabel,
    required this.departmentLabel,
    required this.completedAt,
    required this.readinessScore,
  });
}

class _RequestRow {
  final String requestId;
  final _RequestKind type;
  final String? memberName;
  final String memberEmail;
  final String roleLabel;
  final String departmentLabel;
  final NormalizedRequestStatus status;
  final DateTime? requestedAt;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final String? completedScanId;
  final _RequestOutcome outcome;

  const _RequestRow({
    required this.requestId,
    required this.type,
    required this.memberName,
    required this.memberEmail,
    required this.roleLabel,
    required this.departmentLabel,
    required this.status,
    required this.requestedAt,
    required this.dueAt,
    required this.completedAt,
    required this.completedScanId,
    required this.outcome,
  });
}

class _RequestOutcome {
  final _ResultBucket? bucket;
  final String label;

  const _RequestOutcome({required this.bucket, required this.label});
}

class _RequestSummary {
  final int required;
  final int completed;
  final int pending;
  final int overdue;

  const _RequestSummary({
    required this.required,
    required this.completed,
    required this.pending,
    required this.overdue,
  });

  static _RequestSummary build(List<_RequestRow> rows) {
    var completed = 0;
    var pending = 0;
    var overdue = 0;
    var required = 0;
    for (final row in rows) {
      switch (row.status) {
        case NormalizedRequestStatus.pending:
          pending += 1;
          required += 1;
          break;
        case NormalizedRequestStatus.overdue:
          overdue += 1;
          required += 1;
          break;
        case NormalizedRequestStatus.completed:
          completed += 1;
          required += 1;
          break;
        case NormalizedRequestStatus.cancelled:
          break;
      }
    }
    return _RequestSummary(
      required: required,
      completed: completed,
      pending: pending,
      overdue: overdue,
    );
  }
}

class _ScanMeta {
  final String userId;
  final String status;

  const _ScanMeta({required this.userId, required this.status});

  String get displayName {
    return 'Member unavailable';
  }
}

class WorkspaceMember {
  final String memberId;
  final String userId;
  final String name;
  final String email;
  final String role;
  final String status;
  final String departmentId;
  final String departmentName;
  final String businessProfileId;

  const WorkspaceMember({
    required this.memberId,
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    required this.departmentId,
    required this.departmentName,
    required this.businessProfileId,
  });

  String get displayName {
    final value = name.trim();
    return value.isNotEmpty ? value : 'Member unavailable';
  }

  String get displayEmail {
    return email.trim();
  }

  String get roleLabel => role.trim();

  String get departmentLabel {
    final value = departmentName.trim();
    return value;
  }
}

class WorkspaceMemberDirectory {
  final List<WorkspaceMember> members;
  final Map<String, WorkspaceMember> byUserId;
  final Map<String, WorkspaceMember> byMembershipId;

  const WorkspaceMemberDirectory({
    required this.members,
    required this.byUserId,
    required this.byMembershipId,
  });

  factory WorkspaceMemberDirectory.fromOwner({
    required String businessProfileId,
    required OwnerWorkforceDirectoryData data,
  }) {
    final members = data.members
        .map(
          (member) => WorkspaceMember(
            memberId: member.memberId,
            userId: member.userId,
            name: member.displayName,
            email: member.displayEmail,
            role: member.roleLabel,
            status: member.status,
            departmentId: member.departmentId ?? '',
            departmentName: member.departmentName ?? '',
            businessProfileId: businessProfileId,
          ),
        )
        .toList();
    return _fromMembers(members);
  }

  factory WorkspaceMemberDirectory.fromHr({
    required String businessProfileId,
    required HrWorkforceDirectoryData data,
  }) {
    final members = data.members
        .map(
          (member) => WorkspaceMember(
            memberId: member.memberId,
            userId: member.userId,
            name: member.displayName,
            email: member.displayEmail,
            role: member.roleLabel,
            status: member.status,
            departmentId: member.departmentId ?? '',
            departmentName: member.departmentName ?? '',
            businessProfileId: businessProfileId,
          ),
        )
        .toList();
    return _fromMembers(members);
  }

  static WorkspaceMemberDirectory _fromMembers(List<WorkspaceMember> members) {
    final byUserId = <String, WorkspaceMember>{};
    final byMembershipId = <String, WorkspaceMember>{};
    for (final member in members) {
      final userKey = normalizeUserId(member.userId);
      if (userKey.isNotEmpty) byUserId[userKey] = member;
      final membershipKey = normalizeMembershipId(member.memberId);
      if (membershipKey.isNotEmpty) byMembershipId[membershipKey] = member;
    }
    return WorkspaceMemberDirectory(
      members: members,
      byUserId: byUserId,
      byMembershipId: byMembershipId,
    );
  }

  WorkspaceMember? resolveRequestMember({
    String? membershipId,
    String? userId,
  }) {
    final normalizedMembershipId = normalizeMembershipId(membershipId);
    if (normalizedMembershipId.isNotEmpty) {
      final member = byMembershipId[normalizedMembershipId];
      if (member != null) return member;
    }
    final normalizedUserId = normalizeUserId(userId);
    if (normalizedUserId.isNotEmpty) {
      final member = byUserId[normalizedUserId];
      if (member != null) return member;
    }
    return null;
  }

  _MemberResolution resolveResultMember({
    String? scanMembershipId,
    String? scanUserId,
    String? resultMembershipId,
    String? resultUserId,
  }) {
    final scanMembershipKey = normalizeMembershipId(scanMembershipId);
    if (scanMembershipKey.isNotEmpty) {
      final member = byMembershipId[scanMembershipKey];
      if (member != null) {
        return _MemberResolution(
          member: member,
          source: _MemberResolutionSource.directMembership,
        );
      }
    }

    final scanUserKey = normalizeUserId(scanUserId);
    if (scanUserKey.isNotEmpty) {
      final member = byUserId[scanUserKey];
      if (member != null) {
        return _MemberResolution(
          member: member,
          source: _MemberResolutionSource.directUser,
        );
      }
    }

    final resultMembershipKey = normalizeMembershipId(resultMembershipId);
    if (resultMembershipKey.isNotEmpty) {
      final member = byMembershipId[resultMembershipKey];
      if (member != null) {
        return _MemberResolution(
          member: member,
          source: _MemberResolutionSource.requestMembership,
        );
      }
    }

    final resultUserKey = normalizeUserId(resultUserId);
    if (resultUserKey.isNotEmpty) {
      final member = byUserId[resultUserKey];
      if (member != null) {
        return _MemberResolution(
          member: member,
          source: _MemberResolutionSource.requestUser,
        );
      }
    }
    return const _MemberResolution(
      member: null,
      source: _MemberResolutionSource.unresolved,
    );
  }
}

class _MemberResolution {
  final WorkspaceMember? member;
  final _MemberResolutionSource source;

  const _MemberResolution({required this.member, required this.source});
}

enum _MemberResolutionSource {
  directMembership,
  directUser,
  requestMembership,
  requestUser,
  unresolved,
}

String normalizeUserId(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.toLowerCase();
}

String normalizeMembershipId(String? value) {
  return value?.trim() ?? '';
}

String _normalizeUserKey(String? value) => normalizeUserId(value);

String _normalizeMembershipKey(String? value) => normalizeMembershipId(value);

String? _humanReadableLabel(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  if (_looksLikeRawIdentifier(trimmed)) return null;
  return trimmed;
}

bool _looksLikeRawIdentifier(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return true;
  if (RegExp(r'^\d+$').hasMatch(trimmed)) return true;
  if (RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(trimmed)) {
    return true;
  }
  if (trimmed.startsWith('Member #') ||
      trimmed.startsWith('Membership #') ||
      trimmed.startsWith('Result #') ||
      trimmed.startsWith('Scan #')) {
    return true;
  }
  return false;
}

Future<WorkspaceMemberDirectory> _loadCompanyMemberDirectory({
  required String effectiveRole,
  required String profileId,
  required String membershipId,
}) async {
  final normalizedRole = effectiveRole.trim().toLowerCase();
  if (normalizedRole == 'hr') {
    final data = await HrOpsService.instance.fetchWorkforceDirectory();
    return WorkspaceMemberDirectory.fromHr(
      businessProfileId: profileId,
      data: data,
    );
  }
  final data = await OwnerOpsService.instance.fetchWorkforceDirectory();
  return WorkspaceMemberDirectory.fromOwner(
    businessProfileId: profileId,
    data: data,
  );
}

class _QueryOutcome {
  final bool ok;
  final int? statusCode;

  const _QueryOutcome.ok() : ok = true, statusCode = null;
  const _QueryOutcome.failed(this.statusCode) : ok = false;

  bool get isForbidden => !ok && statusCode == 403;
}

class _QueryResult<T> {
  final T data;
  final _QueryOutcome outcome;

  const _QueryResult(this.data, this.outcome);

  bool get ok => outcome.ok;
}

class _ScreenSnapshot {
  final List<_ResultRow> resultRows;
  final Map<_ResultBucket, int> distribution;
  final List<_RequestRow> requestRows;
  final _RequestSummary requestSummary;
  final bool resultsQueryFailed;
  final _QueryOutcome requestsQuery;
  final _QueryOutcome scansQuery;
  final bool assessmentQueryFailed;

  const _ScreenSnapshot({
    required this.resultRows,
    required this.distribution,
    required this.requestRows,
    required this.requestSummary,
    required this.resultsQueryFailed,
    required this.requestsQuery,
    required this.scansQuery,
    required this.assessmentQueryFailed,
  });

  factory _ScreenSnapshot.empty() {
    return const _ScreenSnapshot(
      resultRows: [],
      distribution: {
        _ResultBucket.stable: 0,
        _ResultBucket.lowFocus: 0,
        _ResultBucket.elevatedFatigue: 0,
        _ResultBucket.highRisk: 0,
      },
      requestRows: [],
      requestSummary: _RequestSummary(
        required: 0,
        completed: 0,
        pending: 0,
        overdue: 0,
      ),
      resultsQueryFailed: false,
      requestsQuery: _QueryOutcome.ok(),
      scansQuery: _QueryOutcome.ok(),
      assessmentQueryFailed: false,
    );
  }
}
