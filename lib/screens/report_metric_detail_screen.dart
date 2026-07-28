import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/owner/owner_design_system.dart';

typedef ReportEntryAction = void Function(BuildContext context);

class ReportDetailEntry {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final String? email;
  final String? role;
  final String? department;
  final String? meta;
  final String? statusLabel;
  final String? actionLabel;
  final ReportEntryAction? onAction;

  const ReportDetailEntry({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.email,
    this.role,
    this.department,
    this.meta,
    this.statusLabel,
    this.actionLabel,
    this.onAction,
  });

  bool get hasRichDetails {
    return (email?.trim().isNotEmpty == true) ||
        (role?.trim().isNotEmpty == true) ||
        (department?.trim().isNotEmpty == true) ||
        (meta?.trim().isNotEmpty == true) ||
        (statusLabel?.trim().isNotEmpty == true) ||
        (actionLabel?.trim().isNotEmpty == true);
  }
}

class ReportMetricDetailScreen extends ConsumerWidget {
  final String title;
  final String rangeLabel;
  final String summaryLabel;
  final String summaryValue;
  final List<ReportDetailEntry> entries;
  final String? emptyTitle;
  final String? emptyBody;

  const ReportMetricDetailScreen({
    super.key,
    required this.title,
    required this.rangeLabel,
    required this.summaryLabel,
    required this.summaryValue,
    required this.entries,
    this.emptyTitle,
    this.emptyBody,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: ListView(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: WellarTheme.text,
                  ),
                ),
                Expanded(
                  child: SectionHeader(title: title, subtitle: rangeLabel),
                ),
                TextButton(
                  onPressed: null,
                  child: Text(Tr.t(lang, 'export_coming_soon')),
                ),
              ],
            ),
            const SizedBox(height: 14),
            OwnerSurfaceCard(
              glow: true,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summaryLabel,
                          style: const TextStyle(
                            color: WellarTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          summaryValue,
                          style: const TextStyle(
                            color: WellarTheme.text,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: const Color(0x2449D3C2),
                    ),
                    child: const Icon(
                      Icons.insights_outlined,
                      color: WellarTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (entries.isEmpty)
              SmartEmptyState(
                icon: Icons.inbox_outlined,
                title: emptyTitle ?? Tr.t(lang, 'report_detail_empty_title'),
                subtitle: emptyBody ?? Tr.t(lang, 'report_detail_empty_body'),
              )
            else
              ...entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: entry.hasRichDetails
                      ? _richEntryCard(context, entry)
                      : _simpleEntryCard(entry),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _simpleEntryCard(ReportDetailEntry entry) {
    return OwnerSurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x3349D3C2), Color(0x334A89FF)],
              ),
            ),
            child: Icon(entry.icon, color: WellarTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: const TextStyle(
                    color: WellarTheme.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if (entry.subtitle != null &&
                    entry.subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.subtitle!,
                    style: const TextStyle(
                      color: WellarTheme.textMuted,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (entry.trailing != null && entry.trailing!.trim().isNotEmpty)
            Text(
              entry.trailing!,
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _richEntryCard(BuildContext context, ReportDetailEntry entry) {
    final accent = _statusColor(entry.statusLabel ?? entry.trailing);
    final email = _normalized(entry.email);
    final department = _normalized(entry.department);
    final meta = _normalized(entry.meta);

    return OwnerSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(label: entry.title, size: 42, accent: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: const TextStyle(
                        color: WellarTheme.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (email != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: const TextStyle(
                          color: WellarTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (department != null || meta != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (department != null) department,
                          if (meta != null) meta,
                        ].join('  |  '),
                        style: const TextStyle(
                          color: WellarTheme.textMuted,
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                    if (entry.subtitle != null &&
                        entry.subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        entry.subtitle!,
                        style: const TextStyle(
                          color: WellarTheme.textMuted,
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_normalized(entry.statusLabel ?? entry.trailing) != null)
                TonePill(
                  label: entry.statusLabel ?? entry.trailing!,
                  color: accent,
                ),
            ],
          ),
          if ((_normalized(entry.role) != null) ||
              (_normalized(entry.actionLabel) != null &&
                  entry.onAction != null))
            const SizedBox(height: 12),
          if ((_normalized(entry.role) != null) ||
              (_normalized(entry.actionLabel) != null &&
                  entry.onAction != null))
            Row(
              children: [
                if (_normalized(entry.role) != null) RoleChip(entry.role!),
                const Spacer(),
                if (_normalized(entry.actionLabel) != null &&
                    entry.onAction != null)
                  TextButton(
                    onPressed: () => entry.onAction!(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: WellarTheme.primary,
                    ),
                    child: Text(
                      entry.actionLabel!,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String? _normalized(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  Color _statusColor(String? label) {
    final value = label?.trim().toLowerCase() ?? '';
    if (value.contains('high')) return const Color(0xFFFF7A8F);
    if (value.contains('overdue')) return const Color(0xFFFFC46B);
    if (value.contains('alert')) return const Color(0xFF7DBBFF);
    if (value.contains('missing')) return const Color(0xFFFFC46B);
    return WellarTheme.primary;
  }
}
