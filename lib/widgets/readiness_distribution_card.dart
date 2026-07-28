import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'owner/owner_design_system.dart';

class ReadinessDistributionCard extends StatelessWidget {
  final String title;
  final Map<String, int>? counts;
  final VoidCallback? onTap;
  final String? subtitle;
  final String emptyMessage;
  final String unavailableMessage;
  final bool showChevron;

  const ReadinessDistributionCard({
    super.key,
    required this.title,
    required this.counts,
    this.onTap,
    this.subtitle,
    required this.emptyMessage,
    required this.unavailableMessage,
    this.showChevron = false,
  });

  static const List<_DistributionRow> _rows = <_DistributionRow>[
    _DistributionRow(
      label: 'Stable',
      keyName: 'Stable',
      accent: Color(0xFF6EE7A8),
    ),
    _DistributionRow(
      label: 'Low Focus',
      keyName: 'Low Focus',
      accent: Color(0xFF7DBBFF),
    ),
    _DistributionRow(
      label: 'Elevated Fatigue',
      keyName: 'Elevated Fatigue',
      accent: Color(0xFFFFC46B),
    ),
    _DistributionRow(
      label: 'High Risk',
      keyName: 'High Risk',
      accent: Color(0xFFFF7A8F),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final resolved = counts;
    final hasData = resolved != null;
    final total = hasData
        ? _rows.fold<int>(
            0,
            (sum, row) => sum + _countForKey(resolved, row.keyName),
          )
        : 0;

    return OwnerSurfaceCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: WellarTheme.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              if (showChevron && onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: WellarTheme.textMuted,
                  size: 22,
                ),
            ],
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!.trim(),
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (!hasData)
            Text(
              unavailableMessage,
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (total == 0)
            Text(
              emptyMessage,
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ..._rows.map((row) {
              final value = _countForKey(resolved, row.keyName);
              final progress = total == 0 ? 0.0 : value / total;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _DistributionDot(row.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            row.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: WellarTheme.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '$value',
                          style: const TextStyle(
                            color: WellarTheme.text,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 7,
                        value: progress,
                        backgroundColor: row.accent.withValues(alpha: 0.10),
                        color: row.accent,
                      ),
                    ),
                  ],
                ),
              );
            }),
          if (showChevron && onTap != null) ...[
            const SizedBox(height: 8),
            const Text(
              'Tap to view every member',
              style: TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _countForKey(Map<String, int>? counts, String keyName) {
    if (counts == null) return 0;
    final direct = counts[keyName];
    if (direct != null) return direct;
    final normalized = keyName.trim().toLowerCase();
    for (final entry in counts.entries) {
      if (entry.key.trim().toLowerCase() == normalized) {
        return entry.value;
      }
    }
    return 0;
  }
}

class _DistributionRow {
  final String label;
  final String keyName;
  final Color accent;

  const _DistributionRow({
    required this.label,
    required this.keyName,
    required this.accent,
  });
}

class _DistributionDot extends StatelessWidget {
  final Color color;

  const _DistributionDot(this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
