import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../models/alert_item.dart';
import '../models/notification_item.dart';
import '../models/organization_invitation.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_wellar_card.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/status_chip.dart';
import '../widgets/wellar_card.dart';
import '../widgets/wellar_empty_state.dart';
import '../widgets/wellar_error_state.dart';
import '../widgets/wellar_header.dart';
import '../widgets/wellar_skeleton_shimmer.dart';
import 'admin_scan_requests_screen.dart';
import 'employee_requests_screen.dart';
import 'manager_scan_requests_screen.dart';
import 'organization_invitation_screen.dart';
import 'profile_screen.dart';
import 'request_details_screen.dart';
import 'alert_detail_screen.dart';
import 'scan_details_screen.dart';
import 'scan_request_open_screen.dart';

enum NotificationCenterTab { notifications, alerts }

class NotificationsScreen extends ConsumerStatefulWidget {
  final bool? showAlertsTab;
  final NotificationCenterTab initialTab;
  final String initialAlertsFilter;
  final bool highlightOpenAlerts;

  const NotificationsScreen({
    super.key,
    this.showAlertsTab,
    this.initialTab = NotificationCenterTab.notifications,
    this.initialAlertsFilter = 'all',
    this.highlightOpenAlerts = false,
  });

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  static const Set<String> _filters = {
    'all',
    'open',
    'closed',
    'action_required',
  };

  bool _showAlerts = false;
  String _alertsFilter = 'all';
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _showAlerts = widget.initialTab == NotificationCenterTab.alerts;
    _alertsFilter = _normalizeFilter(widget.initialAlertsFilter);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final canViewAlerts = widget.showAlertsTab ?? _roleCanViewAlerts();
    final showAlerts = canViewAlerts && _showAlerts;
    final notificationsAsync = ref.watch(notificationsProvider);
    final invitationsAsync = ref.watch(organizationInvitationsProvider);
    final alertsAsync = canViewAlerts
        ? ref.watch(alertsProvider)
        : const AsyncData<List<AlertItem>>(<AlertItem>[]);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.read(refreshTickProvider.notifier).state++,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _header(
                lang: lang,
                notificationsAsync: notificationsAsync,
                showAlerts: showAlerts,
              ),
              const SizedBox(height: 10),
              if (canViewAlerts) _scopeToggle(lang: lang),
              if (showAlerts) ...[
                const SizedBox(height: 10),
                _alertFilters(lang: lang),
              ],
              const SizedBox(height: WellarTheme.sectionGap),
              if (showAlerts)
                alertsAsync.when(
                  loading: _loading,
                  error: (e, _) => WellarErrorState(
                    title: Tr.t(lang, 'failed_load_alerts'),
                    body: _errorText(e, showAlerts: true),
                    onRetry: () =>
                        ref.read(refreshTickProvider.notifier).state++,
                  ),
                  data: (items) => _alertsContent(items),
                )
              else
                _notificationsTab(
                  invitationsAsync: invitationsAsync,
                  notificationsAsync: notificationsAsync,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header({
    required dynamic lang,
    required AsyncValue<List<NotificationItem>> notificationsAsync,
    required bool showAlerts,
  }) {
    final unread = notificationsAsync.maybeWhen(
      data: (items) => items.where((item) => item.isUnread).length,
      orElse: () => 0,
    );
    return WellarHeader(
      title: Tr.t(lang, 'notification_center'),
      subtitle: showAlerts
          ? Tr.t(lang, 'alerts_section_subtitle')
          : unread == 0
          ? Tr.t(lang, 'notifications_section_subtitle')
          : Tr.withCount(lang, 'unread_notifications', count: unread),
      trailing: (!showAlerts && unread > 0)
          ? TextButton(
              onPressed: _markingAll ? null : _markAllRead,
              child: Text(
                _markingAll
                    ? Tr.t(lang, 'marking')
                    : Tr.t(lang, 'mark_all_read'),
                style: const TextStyle(color: WellarTheme.primary),
              ),
            )
          : null,
    );
  }

  Widget _scopeToggle({required dynamic lang}) {
    return Row(
      children: [
        Expanded(
          child: ChoiceChip(
            label: Text(Tr.t(lang, 'notifications')),
            selected: !_showAlerts,
            onSelected: (_) => setState(() => _showAlerts = false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ChoiceChip(
            label: Text(Tr.t(lang, 'alerts')),
            selected: _showAlerts,
            onSelected: (_) => setState(() => _showAlerts = true),
          ),
        ),
      ],
    );
  }

  Widget _alertFilters({required dynamic lang}) {
    final items = <MapEntry<String, String>>[
      MapEntry('all', Tr.t(lang, 'alerts_filters_all')),
      MapEntry('open', Tr.t(lang, 'alerts_filters_open')),
      MapEntry('closed', Tr.t(lang, 'alerts_filters_closed')),
      MapEntry('action_required', Tr.t(lang, 'alerts_filters_action')),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, index) {
          final item = items[index];
          return ChoiceChip(
            label: Text(item.value),
            selected: _alertsFilter == item.key,
            onSelected: (_) => setState(() => _alertsFilter = item.key),
          );
        },
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemCount: items.length,
      ),
    );
  }

  Widget _loading() => Column(
    children: List.generate(
      4,
      (index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AnimatedWellarCard(
          delay: Duration(milliseconds: 70 * index),
          child: const WellarCard(child: WellarSkeletonShimmer(height: 88)),
        ),
      ),
    ),
  );

  Widget _notificationsTab({
    required AsyncValue<List<OrganizationInvitation>> invitationsAsync,
    required AsyncValue<List<NotificationItem>> notificationsAsync,
  }) {
    return Column(
      children: [
        _organizationInvitationsSection(
          invitationsAsync: invitationsAsync,
          invitations:
              invitationsAsync.valueOrNull ?? const <OrganizationInvitation>[],
        ),
        _ordinaryNotificationsSection(notificationsAsync),
      ],
    );
  }

  Widget _organizationInvitationsSection({
    required AsyncValue<List<OrganizationInvitation>> invitationsAsync,
    required List<OrganizationInvitation> invitations,
  }) {
    final header = _sectionHeader(
      title: 'Organization invitations',
      subtitle:
          'Personal invitations stay visible here even when their organization is not active.',
    );

    if (invitationsAsync.isLoading) {
      return Column(
        children: [
          header,
          ...List.generate(
            2,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AnimatedWellarCard(
                delay: Duration(milliseconds: 45 * index),
                child: const WellarCard(
                  child: WellarSkeletonShimmer(height: 112),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (invitationsAsync.hasError) {
      return Column(
        children: [
          header,
          WellarCard(
            child: Text(
              'We could not load organization invitations right now.',
              style: const TextStyle(color: WellarTheme.textMuted),
            ),
          ),
        ],
      );
    }

    if (invitations.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        header,
        ...invitations.asMap().entries.map(
          (entry) => AnimatedWellarCard(
            delay: Duration(milliseconds: 45 * entry.key),
            child: _organizationInvitationCard(entry.value),
          ),
        ),
      ],
    );
  }

  Widget _ordinaryNotificationsSection(
    AsyncValue<List<NotificationItem>> notificationsAsync,
  ) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final header = _sectionHeader(
      title: 'Notifications',
      subtitle: 'Updates scoped to your active organization.',
    );

    return notificationsAsync.when(
      loading: () => Column(children: [header, _loading()]),
      error: (error, _) => Column(
        children: [
          header,
          WellarErrorState(
            title: Tr.t(lang, 'failed_load_notifications'),
            body: _errorText(error, showAlerts: false),
            onRetry: () => ref.read(refreshTickProvider.notifier).state++,
          ),
        ],
      ),
      data: (items) {
        if (items.isEmpty) {
          return Column(
            children: [
              header,
              WellarEmptyState(
                icon: Icons.notifications_none_rounded,
                title: Tr.t(lang, 'notifications_empty_title'),
                body: Tr.t(lang, 'notifications_empty_body'),
              ),
            ],
          );
        }

        return Column(
          children: [
            header,
            ...items.asMap().entries.map(
              (entry) => AnimatedWellarCard(
                delay: Duration(milliseconds: 55 * entry.key),
                child: _notificationCard(entry.value),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionHeader({required String title, required String subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: WellarTheme.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _organizationInvitationCard(OrganizationInvitation invitation) {
    final date = invitation.sentAt ?? invitation.createdAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(WellarTheme.cardRadius),
        onTap: () => _openOrganizationInvitation(invitation),
        child: WellarCard(
          highlighted: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: WellarTheme.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.business_rounded,
                      color: WellarTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invitation.organizationName,
                          style: const TextStyle(
                            color: WellarTheme.text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Organization invitation',
                          style: const TextStyle(
                            color: WellarTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const StatusChip('Pending'),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusChip(invitation.roleLabel),
                  if (invitation.departmentName?.trim().isNotEmpty == true)
                    StatusChip(invitation.departmentName!.trim()),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Sent by ${invitation.senderLabel}',
                style: const TextStyle(color: WellarTheme.textMuted),
              ),
              if (date != null) ...[
                const SizedBox(height: 6),
                Text(
                  _formatDate(date.toLocal()),
                  style: const TextStyle(
                    color: WellarTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _alertsContent(List<AlertItem> items) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final filtered = items.where((item) {
      switch (_alertsFilter) {
        case 'open':
          return item.isOpen;
        case 'closed':
          return !item.isOpen;
        case 'action_required':
          return item.actionRequired;
        default:
          return true;
      }
    }).toList();

    if (filtered.isEmpty) {
      final isOpenOnly = _alertsFilter == 'open';
      final title = isOpenOnly
          ? Tr.t(lang, 'no_open_alerts')
          : items.isEmpty
          ? Tr.t(lang, 'no_alerts_yet')
          : Tr.t(lang, 'no_filtered_alerts');
      final body = isOpenOnly
          ? Tr.t(lang, 'no_open_alerts_body')
          : items.isEmpty
          ? Tr.t(lang, 'alerts_appear_here')
          : Tr.t(lang, 'no_filtered_alerts_body');
      return WellarEmptyState(
        icon: Icons.notifications_none_rounded,
        title: title,
        body: body,
      );
    }

    var highlightedCount = 0;
    return Column(
      children: filtered.asMap().entries.map((entry) {
        final item = entry.value;
        final emphasize =
            widget.highlightOpenAlerts &&
            _alertsFilter == 'open' &&
            item.isOpen &&
            highlightedCount < 2;
        if (emphasize) highlightedCount++;
        return AnimatedWellarCard(
          delay: Duration(milliseconds: 55 * entry.key),
          child: _alertCard(item, emphasize: emphasize),
        );
      }).toList(),
    );
  }

  Widget _notificationCard(NotificationItem item) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final date = item.createdAt?.toLocal();
    final title = item.title.trim().isNotEmpty
        ? item.title
        : Tr.t(lang, 'alert');
    final body = item.body.trim().isNotEmpty
        ? item.body
        : Tr.t(lang, 'operational_update');
    final unread = item.isUnread;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(WellarTheme.cardRadius),
        onTap: () => _handleNotificationTap(item),
        child: WellarCard(
          highlighted: unread,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 7),
                decoration: BoxDecoration(
                  color: unread ? WellarTheme.primary : WellarTheme.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: WellarTheme.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        StatusChip(
                          unread ? Tr.t(lang, 'unread') : Tr.t(lang, 'read'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WellarTheme.textMuted,
                        height: 1.3,
                      ),
                    ),
                    if (date != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _formatDate(date),
                              style: const TextStyle(
                                color: WellarTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _handleNotificationTap(item),
                            child: Text(_notificationActionLabel(item, lang)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _alertCard(AlertItem item, {required bool emphasize}) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final date = item.createdAt?.toLocal();
    final isOpen = item.isOpen;

    final card = WellarCard(
      highlighted: isOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WellarTheme.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              StatusChip(
                isOpen
                    ? Tr.t(lang, 'alerts_filters_open')
                    : Tr.t(lang, 'alerts_filters_closed'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: WellarTheme.textMuted, height: 1.3),
          ),
          if (date != null) ...[
            const SizedBox(height: 8),
            Text(
              _formatDate(date),
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(
                onPressed: () => _openAlertTarget(item),
                child: Text(
                  Tr.t(lang, 'view_alert'),
                ),
              ),
              const SizedBox(width: 8),
              if (isOpen)
                TextButton(
                  onPressed: () => _markAlertSeen(item),
                  child: Text(Tr.t(lang, 'mark_seen')),
                ),
            ],
          ),
        ],
      ),
    );

    if (!emphasize) {
      return Padding(padding: const EdgeInsets.only(bottom: 12), child: card);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(WellarTheme.cardRadius),
          border: Border.all(color: const Color(0x88E6B85C)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WellarTheme.cardRadius),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 4, color: const Color(0xCCEEBC67)),
              ),
              card,
            ],
          ),
        ),
      ),
    );
  }

  void _markReadOptimistically(NotificationItem item) {
    if (!item.isUnread) return;
    final previous = {...ref.read(notificationReadOverrideProvider)};
    final overrides = {...previous};
    overrides.add(item.id);
    final linkKey = item.linkId?.trim();
    if (linkKey != null && linkKey.isNotEmpty) {
      overrides.add('link:$linkKey');
    }
    ref.read(notificationReadOverrideProvider.notifier).state = overrides;
    unawaited(_persistRead(item, previous));
  }

  Future<void> _persistRead(
    NotificationItem item,
    Set<String> previousOverrides,
  ) async {
    try {
      await ref.read(notificationServiceProvider).markRead(item.id);
      ref.read(refreshTickProvider.notifier).state++;
    } catch (_) {
      final current = {...ref.read(notificationReadOverrideProvider)};
      if (!previousOverrides.contains(item.id)) {
        current.remove(item.id);
      }
      final linkKey = item.linkId?.trim();
      if (linkKey != null &&
          linkKey.isNotEmpty &&
          !previousOverrides.contains('link:$linkKey')) {
        current.remove('link:$linkKey');
      }
      ref.read(notificationReadOverrideProvider.notifier).state = current;
      if (!mounted) return;
      final lang = ref.read(appLanguageControllerProvider).language;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(Tr.t(lang, 'mark_read_failed'))));
    }
  }

  Future<void> _handleNotificationTap(NotificationItem item) async {
    _markReadOptimistically(item);
    if (!mounted) return;

    final normalizedType = item.type.trim().toLowerCase();
    final linkType = (item.linkType ?? item.type).trim().toLowerCase();
    final linkId = item.linkId?.trim().isNotEmpty == true
        ? item.linkId!.trim()
        : (item.meta?['scan_id']?.toString().trim() ??
              item.meta?['scan_request_id']?.toString().trim() ??
              item.meta?['request_id']?.toString().trim() ??
              '');

    if (linkType == 'scan_request') {
      if (linkId.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ScanRequestOpenScreen(scanRequestId: linkId),
          ),
        );
        return;
      }
      _openRequestFallback();
      return;
    }

    if (linkType.contains('request')) {
      if (linkId.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RequestDetailsScreen(requestId: linkId),
          ),
        );
        return;
      }
      _openRequestFallback();
      return;
    }

    final isResultNotification =
        normalizedType == 'result' ||
        linkType == 'result' ||
        linkType == 'scan_result';
    if (isResultNotification) {
      final scanId = await _resolveResultNotificationScanId(linkId);
      if (!mounted) return;
      if (scanId.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ScanDetailsScreen(scanId: scanId)),
        );
        return;
      }
      _showFallbackSnack();
      return;
    }

    if (linkType.contains('alert')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const NotificationsScreen(
            showAlertsTab: true,
            initialTab: NotificationCenterTab.alerts,
            initialAlertsFilter: 'open',
            highlightOpenAlerts: true,
          ),
        ),
      );
      return;
    }

    if (linkType.contains('invite') ||
        linkType.contains('workspace') ||
        linkType.contains('profile')) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
      return;
    }

    if (linkType.contains('alert') &&
        (widget.showAlertsTab ?? _roleCanViewAlerts())) {
      setState(() {
        _showAlerts = true;
        _alertsFilter = 'open';
      });
      return;
    }

    _showFallbackSnack();
  }

  Future<String> _resolveResultNotificationScanId(String linkId) async {
    final normalizedLinkId = linkId.trim();
    if (normalizedLinkId.isEmpty) return '';

    try {
      final directResult = await ref
          .read(scanServiceProvider)
          .fetchScanResultForScan(normalizedLinkId);
      if (directResult != null) {
        return normalizedLinkId;
      }
    } catch (_) {}

    try {
      final result = await ref.read(scanServiceProvider).fetchScanResultById(
        normalizedLinkId,
      );
      final scanId = result?.scanId.trim() ?? '';
      return scanId;
    } catch (_) {
      return '';
    }
  }

  Future<void> _openOrganizationInvitation(
    OrganizationInvitation invitation,
  ) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => OrganizationInvitationScreen(invitation: invitation),
      ),
    );
    if (!mounted || result == null || result.trim().isEmpty) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.trim())));
  }

  Future<void> _openAlertTarget(AlertItem item) async {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AlertDetailScreen(item: item)),
    );
  }

  Future<void> _markAlertSeen(AlertItem item) async {
    final lang = ref.read(appLanguageControllerProvider).language;
    final ok = await ref.read(alertServiceProvider).markAlertClosed(item.id);
    if (ok) {
      ref.read(refreshTickProvider.notifier).state++;
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(Tr.t(lang, 'alert_update_failed'))));
  }

  Future<void> _markAllRead() async {
    setState(() => _markingAll = true);
    final previous = {...ref.read(notificationReadOverrideProvider)};
    try {
      final items = ref
          .read(notificationsProvider)
          .maybeWhen(
            data: (rows) => rows,
            orElse: () => const <NotificationItem>[],
          );
      if (items.isNotEmpty) {
        final overrides = {...previous};
        for (final item in items) {
          overrides.add(item.id);
          final link = item.linkId?.trim();
          if (link != null && link.isNotEmpty) {
            overrides.add('link:$link');
          }
        }
        ref.read(notificationReadOverrideProvider.notifier).state = overrides;
      }
      await ref.read(notificationServiceProvider).markAllRead();
      ref.read(refreshTickProvider.notifier).state++;
    } catch (_) {
      final items = ref
          .read(notificationsProvider)
          .maybeWhen(
            data: (rows) => rows,
            orElse: () => const <NotificationItem>[],
          );
      final current = {...ref.read(notificationReadOverrideProvider)};
      for (final item in items) {
        if (!previous.contains(item.id)) {
          current.remove(item.id);
        }
        final link = item.linkId?.trim();
        if (link != null &&
            link.isNotEmpty &&
            !previous.contains('link:$link')) {
          current.remove('link:$link');
        }
      }
      ref.read(notificationReadOverrideProvider.notifier).state = current;
      final lang = ref.read(appLanguageControllerProvider).language;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(Tr.t(lang, 'mark_read_failed'))));
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  bool _roleCanViewAlerts() {
    final role = ref.read(activeWorkspaceContextProvider)?.finalEffectiveRole;
    final normalized = role?.trim().toLowerCase() ?? '';
    return normalized == 'owner' || normalized == 'hr';
  }

  String _notificationActionLabel(NotificationItem item, dynamic lang) {
    final linkType = (item.linkType ?? item.type).trim().toLowerCase();
    if (linkType == 'scan_request' || linkType.contains('request')) {
      return Tr.t(lang, 'view_request');
    }
    if (linkType.contains('result') || linkType.contains('scan')) {
      return Tr.t(lang, 'view_result');
    }
    if (linkType.contains('alert')) {
      return Tr.t(lang, 'view_alert');
    }
    return Tr.t(lang, 'open');
  }

  void _openRequestFallback() {
    final role =
        ref
            .read(activeWorkspaceContextProvider)
            ?.finalEffectiveRole
            .trim()
            .toLowerCase() ??
        '';
    final Widget target;
    if (role == 'owner' || role == 'hr') {
      target = const AdminScanRequestsScreen();
    } else if (role == 'manager' || role == 'manger') {
      target = const ManagerScanRequestsScreen();
    } else {
      target = const EmployeeRequestsScreen();
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => target));
  }

  String _normalizeFilter(String value) {
    final normalized = value.trim().toLowerCase();
    if (_filters.contains(normalized)) return normalized;
    return 'all';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _errorText(Object error, {required bool showAlerts}) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final raw = error.toString().toLowerCase();
    if (raw.contains('permission') || raw.contains('403')) {
      return showAlerts
          ? Tr.t(lang, 'alerts_unavailable')
          : Tr.t(lang, 'notifications_unavailable');
    }
    return showAlerts
        ? Tr.t(lang, 'unable_load_alerts')
        : Tr.t(lang, 'unable_load_notifications');
  }

  void _showFallbackSnack() {
    final lang = ref.read(appLanguageControllerProvider).language;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      const SnackBar(content: Text('No linked detail was provided.')),
    );
  }
}
