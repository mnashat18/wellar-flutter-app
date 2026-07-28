import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../state/session.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';
import '../utils/page_transition.dart';
import '../widgets/readiness_chip.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/animated_wellar_card.dart';
import '../widgets/page_header_actions.dart';
import '../widgets/wellar_button.dart';
import '../widgets/wellar_card.dart';
import '../widgets/wellar_empty_state.dart';
import '../widgets/wellar_header.dart';
import '../widgets/wellar_metric_card.dart';
import '../widgets/wellar_skeleton_shimmer.dart';
import '../widgets/responsive_card_grid.dart';
import '../widgets/readiness_distribution_card.dart';
import '../utils/readiness_distribution.dart';
import 'notifications_screen.dart';
import 'requests_screen.dart';
import 'scan_details_screen.dart';
import 'wellness_check_screen.dart';

class EmployeeHomeScreen extends ConsumerStatefulWidget {
  const EmployeeHomeScreen({super.key});

  @override
  ConsumerState<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends ConsumerState<EmployeeHomeScreen> {
  @override
  Widget build(BuildContext context) {
    debugPrint('[HOME] load start');
    final lang = ref.watch(appLanguageControllerProvider).language;
    final homeAsync = ref.watch(homeDataProvider);
    final profileAsync = ref.watch(profileProvider);
    final workspace = ref.watch(activeWorkspaceContextProvider);
    final requestsAsync = ref.watch(incomingRequestsProvider);
    final unreadNotifications = ref.watch(unreadNotificationsProvider);
    final personalHistoryAsync = ref.watch(ownerHistoryTimelineProvider);
    final workspaceName = workspace?.businessProfileName.isNotEmpty == true
        ? workspace!.businessProfileName
        : Tr.t(lang, 'workspace_default');
    final displayName = _displayIdentity(profileAsync, lang);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.read(refreshTickProvider.notifier).state++;
            ref.invalidate(homeDataProvider);
            ref.invalidate(incomingRequestsProvider);
            ref.invalidate(ownerHistoryTimelineProvider);
            ref.invalidate(profileProvider);
            ref.invalidate(notificationsProvider);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              WellarHeader(
                title: 'Employee Home',
                subtitle: 'Readiness status and assigned work',
                trailing: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PageHeaderActions(
                        unreadCount: unreadNotifications,
                        showAlertsTab: false,
                      ),
                      const SizedBox(width: 8),
                      _roleChip(Tr.t(lang, 'employee')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: WellarTheme.sectionGap),
              AnimatedWellarCard(
                delay: const Duration(milliseconds: 30),
                child: WellarCard(
                  child: profileAsync.when(
                    loading: () => const WellarSkeletonShimmer(height: 78),
                    error: (_, __) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${Tr.t(lang, 'hello')} $displayName',
                          style: const TextStyle(
                            color: WellarTheme.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _displayEmail(profileAsync, lang),
                          style: const TextStyle(color: WellarTheme.textMuted),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _metaChip(Tr.t(lang, 'employee')),
                            _metaChip(workspaceName),
                            if (workspace?.departmentName?.isNotEmpty == true)
                              _metaChip(workspace!.departmentName!),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Some profile information is unavailable right now.',
                          style: const TextStyle(
                            color: WellarTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    data: (p) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${Tr.t(lang, 'hello')} ${p.name.isEmpty ? Tr.t(lang, 'employee') : p.name}',
                          style: const TextStyle(
                            color: WellarTheme.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.email,
                          style: const TextStyle(color: WellarTheme.textMuted),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _metaChip(Tr.t(lang, 'employee')),
                            _metaChip(workspaceName),
                            if (workspace?.departmentName?.isNotEmpty == true)
                              _metaChip(workspace!.departmentName!),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: WellarTheme.sectionGap),
              AnimatedWellarCard(
                delay: const Duration(milliseconds: 90),
                child: WellarCard(
                  highlighted: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Tr.t(lang, 'start_preshift_check'),
                        style: const TextStyle(
                          color: WellarTheme.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        Tr.t(lang, 'quick_readiness_check'),
                        style: const TextStyle(color: WellarTheme.textMuted),
                      ),
                      const SizedBox(height: 12),
                      WellarButton.primary(
                        text: Tr.t(lang, 'start_preshift_scan'),
                        onPressed: () => Navigator.push(
                          context,
                          fadeSlideRoute(const WellnessCheckScreen()),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Tr.t(lang, 'consent_required_every_time'),
                        style: const TextStyle(
                          color: WellarTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: WellarTheme.sectionGap),
              AnimatedWellarCard(
                delay: const Duration(milliseconds: 150),
                child: personalHistoryAsync.when(
                  loading: () => const WellarCard(
                    child: WellarSkeletonShimmer(height: 72),
                  ),
                  error: (_, __) => ReadinessDistributionCard(
                    title: 'My readiness distribution',
                    counts: null,
                    emptyMessage: Tr.t(lang, 'no_readiness_checks'),
                    unavailableMessage: Tr.t(lang, 'readiness_unavailable'),
                  ),
                  data: (entries) {
                    final counts =
                        ReadinessDistributionNormalizer.countsFromHistoryEntries(
                          entries,
                        );
                    return ReadinessDistributionCard(
                      title: 'My readiness distribution',
                      counts: counts,
                      emptyMessage: Tr.t(lang, 'no_readiness_checks'),
                      unavailableMessage: Tr.t(lang, 'readiness_unavailable'),
                    );
                  },
                ),
              ),
              const SizedBox(height: WellarTheme.sectionGap),
              homeAsync.maybeWhen(
                data: (data) => AnimatedWellarCard(
                  delay: const Duration(milliseconds: 200),
                  child: Column(
                    children: [
                      ResponsiveCardGrid(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ResponsiveCardGridItem(
                            child: WellarMetricCard(
                              label: Tr.t(lang, 'checks_completed'),
                              value: '${data.results.length}',
                              icon: Icons.check_circle_outline_rounded,
                            ),
                          ),
                          ResponsiveCardGridItem(
                            child: WellarMetricCard(
                              label: Tr.t(lang, 'pending_result'),
                              value: data.latest == null
                                  ? Tr.t(lang, 'yes')
                                  : Tr.t(lang, 'no'),
                              icon: Icons.hourglass_bottom_rounded,
                            ),
                          ),
                          ResponsiveCardGridItem(
                            child: WellarMetricCard(
                              label: Tr.t(lang, 'assigned_requests'),
                              value: requestsAsync.maybeWhen(
                                data: (r) => '${r.length}',
                                orElse: () => '--',
                              ),
                              icon: Icons.assignment_outlined,
                            ),
                          ),
                          ResponsiveCardGridItem(
                            child: WellarMetricCard(
                              label: Tr.t(lang, 'notifications'),
                              value: '$unreadNotifications',
                              icon: Icons.notifications_outlined,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: WellarTheme.sectionGap),
              AnimatedWellarCard(
                delay: const Duration(milliseconds: 240),
                child: WellarCard(
                  child: requestsAsync.when(
                    loading: () => const WellarSkeletonShimmer(height: 62),
                    error: (error, stackTrace) => Text(
                      Tr.t(lang, 'assigned_requests_unavailable'),
                      style: const TextStyle(color: WellarTheme.textMuted),
                    ),
                    data: (items) {
                      if (items.isEmpty) {
                        return Text(
                          Tr.t(lang, 'no_assigned_requests_yet'),
                          style: const TextStyle(color: WellarTheme.textMuted),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${items.length} ${Tr.t(lang, 'assigned_requests')}',
                            style: const TextStyle(color: WellarTheme.text),
                          ),
                          const SizedBox(height: 10),
                          WellarButton.secondary(
                            text: Tr.t(lang, 'open_requests'),
                            onPressed: () => Navigator.push(
                              context,
                              fadeSlideRoute(const RequestsScreen()),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _displayIdentity(AsyncValue profileAsync, dynamic lang) {
    return profileAsync.maybeWhen(
      data: (profile) {
        final name = profile.name?.toString().trim() ?? '';
        if (name.isNotEmpty) return name;
        final email = profile.email?.toString().trim() ?? '';
        if (email.isNotEmpty) return email;
        return _sessionIdentityFallback(lang);
      },
      orElse: () => _sessionIdentityFallback(lang),
    );
  }

  String _displayEmail(AsyncValue profileAsync, dynamic lang) {
    return profileAsync.maybeWhen(
      data: (profile) {
        final email = profile.email?.toString().trim() ?? '';
        if (email.isNotEmpty) return email;
        return _sessionEmailFallback();
      },
      orElse: () => _sessionEmailFallback(),
    );
  }

  String _sessionIdentityFallback(dynamic lang) {
    final sessionName = Session.instance.userName?.trim() ?? '';
    if (sessionName.isNotEmpty) return sessionName;
    final sessionEmail = Session.instance.userEmail?.trim() ?? '';
    if (sessionEmail.isNotEmpty) return sessionEmail;
    return Tr.t(lang, 'employee');
  }

  String _sessionEmailFallback() {
    final sessionEmail = Session.instance.userEmail?.trim() ?? '';
    if (sessionEmail.isNotEmpty) return sessionEmail;
    return 'Identity unavailable right now';
  }

  Widget _roleChip(String role) {
    return _metaChip(role);
  }

  Widget _metaChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: WellarTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WellarTheme.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: WellarTheme.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
