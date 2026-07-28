import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../services/member_identity_service.dart';
import '../services/manager_ops_service.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_wellar_card.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/readiness_chip.dart';
import '../widgets/wellar_card.dart';
import '../widgets/wellar_empty_state.dart';
import '../widgets/wellar_error_state.dart';
import '../widgets/wellar_header.dart';
import '../widgets/wellar_skeleton_shimmer.dart';

class ManagerTeamScreen extends ConsumerStatefulWidget {
  const ManagerTeamScreen({super.key});

  @override
  ConsumerState<ManagerTeamScreen> createState() => _ManagerTeamScreenState();
}

class _ManagerTeamScreenState extends ConsumerState<ManagerTeamScreen> {
  late Future<List<ManagerMemberView>> _future;
  String _filter = 'All';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = ManagerOpsService.instance.fetchTeam();
  }

  void _reloadTeam() {
    if (!mounted) return;
    setState(() {
      _future = ManagerOpsService.instance.fetchTeam();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final filters = <String>[
      Tr.t(lang, 'all'),
      Tr.t(lang, 'employee'),
      Tr.t(lang, 'active'),
      Tr.t(lang, 'missing_check'),
      Tr.t(lang, 'attention_outcome'),
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        child: FutureBuilder<List<ManagerMemberView>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const WellarCard(
                child: WellarSkeletonShimmer(height: 160),
              );
            }
            if (snap.hasError) {
              final forbidden =
                  snap.error is DioException &&
                  (snap.error as DioException).response?.statusCode == 403;
              return WellarErrorState(
                title: Tr.t(lang, 'unable_load_workforce'),
                body: forbidden
                    ? Tr.t(lang, 'workforce_unavailable')
                    : Tr.t(lang, 'unable_load_workforce'),
                onRetry: _reloadTeam,
              );
            }
            final data = _applyFilter(snap.data ?? const [], filters);
            return RefreshIndicator(
              onRefresh: () async => _reloadTeam(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  WellarHeader(
                    title: Tr.t(lang, 'team'),
                    subtitle: Tr.t(lang, 'workforce_subtitle'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) =>
                        setState(() => _query = v.trim().toLowerCase()),
                    style: const TextStyle(color: WellarTheme.text),
                    decoration: InputDecoration(
                      hintText: Tr.t(lang, 'search_by_name_email'),
                      hintStyle: const TextStyle(color: WellarTheme.textMuted),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: WellarTheme.textMuted,
                      ),
                      filled: true,
                      fillColor: WellarTheme.surfaceSoft.withValues(alpha: 0.4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _filterBar(filters),
                  const SizedBox(height: 12),
                  if (data.isEmpty)
                    WellarEmptyState(
                      icon: Icons.groups_outlined,
                      title: Tr.t(lang, 'no_workforce_members'),
                      body: Tr.t(lang, 'members_appear_here'),
                    )
                  else
                    ...data.asMap().entries.map(
                      (entry) => AnimatedWellarCard(
                        delay: Duration(milliseconds: 40 + (entry.key * 20)),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _memberCard(entry.value, lang),
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

  Widget _filterBar(List<String> items) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, i) {
          final item = items[i];
          return ChoiceChip(
            label: Text(item),
            selected: _filter == item,
            onSelected: (_) => setState(() => _filter = item),
          );
        },
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemCount: items.length,
      ),
    );
  }

  List<ManagerMemberView> _applyFilter(
    List<ManagerMemberView> data,
    List<String> filters,
  ) {
    List<ManagerMemberView> filtered = data;
    if (_filter == filters[1]) {
      filtered = data.where((e) => e.role.toLowerCase() == 'employee').toList();
    }
    if (_filter == filters[2]) {
      filtered = data.where((e) => e.status.toLowerCase() == 'active').toList();
    }
    if (_filter == filters[3]) {
      filtered = data.where((e) => e.missingCheck).toList();
    }
    if (_filter == filters[4]) {
      filtered = data.where((e) => e.needsAttention).toList();
    }
    if (_query.isEmpty) return filtered;
    return filtered
        .where(
          (e) =>
              e.name.toLowerCase().contains(_query) ||
              e.email.toLowerCase().contains(_query),
        )
        .toList();
  }

  Widget _memberCard(ManagerMemberView item, dynamic lang) {
    return WellarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.name.trim().isEmpty
                ? MemberIdentityService.memberProfileUnavailableLabel
                : item.name,
            style: const TextStyle(
              color: WellarTheme.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.email.trim().isEmpty
                ? Tr.t(lang, 'email_not_available')
                : item.email,
            style: const TextStyle(color: WellarTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                '${Tr.t(lang, 'role')}: ${item.role.isEmpty ? Tr.t(lang, 'unknown') : item.role}',
              ),
              _chip(
                '${Tr.t(lang, 'status')}: ${item.status.isEmpty ? Tr.t(lang, 'unknown') : item.status}',
              ),
              _chip(
                '${Tr.t(lang, 'department')}: ${item.departmentName ?? '-'}',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if ((item.latestReadiness ?? '').isNotEmpty)
            ReadinessChip(item.latestReadiness!)
          else
            _chip(
              '${Tr.t(lang, 'latest_readiness')}: ${Tr.t(lang, 'pending')}',
            ),
          const SizedBox(height: 6),
          Text(
            '${Tr.t(lang, 'last_check')}: ${item.lastCheckAt?.toLocal().toString() ?? '-'}',
            style: const TextStyle(color: WellarTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: WellarTheme.surfaceSoft.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(color: WellarTheme.textMuted, fontSize: 11),
      ),
    );
  }
}
