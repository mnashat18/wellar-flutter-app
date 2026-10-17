import '../models/history_entry.dart';
import '../services/readiness_result_service.dart';

class ReadinessDistributionNormalizer {
  static const List<String> canonicalLabels = <String>[
    'Stable',
    'Low Focus',
    'Elevated Fatigue',
    'High Risk',
    'Unavailable - please retake the scan',
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
      final scanStatus = entry.status.trim().toLowerCase();
      if (!entry.hasResult &&
          !{'failed', 'error', 'rejected', 'cancelled', 'retake_required'}
              .contains(scanStatus)) {
        continue;
      }
      final label = normalizeLabel(
        entry.result?.riskLevel ?? entry.result?.overallState,
      );
      final bucket = label != null && counts.containsKey(label)
          ? label
          : 'Unavailable - please retake the scan';
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }
    return counts;
  }
}
