import '../models/history_entry.dart';
import '../services/readiness_result_service.dart';

class ReadinessDistributionNormalizer {
  static const List<String> canonicalLabels = <String>[
    'Stable',
    'Low Focus',
    'Elevated Fatigue',
    'High Risk',
  ];

  static Map<String, int> emptyCounts() {
    return {for (final label in canonicalLabels) label: 0};
  }

  static String? normalizeLabel(String? value) {
    final normalized = ReadinessResultService.normalizeReadinessLabel(
      value ?? '',
    );
    if (normalized.isEmpty) return null;
    return normalized;
  }

  static Map<String, int> countsFromHistoryEntries(
    Iterable<HistoryEntry> entries,
  ) {
    final counts = emptyCounts();
    for (final entry in entries) {
      if (!entry.hasResult) continue;
      if (entry.status.trim().toLowerCase() != 'completed') continue;
      final label = normalizeLabel(
        entry.result?.riskLevel ?? entry.result?.overallState,
      );
      if (label == null || !counts.containsKey(label)) continue;
      counts[label] = (counts[label] ?? 0) + 1;
    }
    return counts;
  }
}
