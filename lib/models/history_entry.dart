import 'scan_result.dart';

class HistoryEntry {
  final String id;
  final String scanId;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? dateCreated;
  final String status;
  final ScanResult? result;

  const HistoryEntry({
    required this.id,
    required this.scanId,
    required this.startedAt,
    required this.completedAt,
    required this.dateCreated,
    required this.status,
    required this.result,
  });

  bool get hasResult => result != null;

  String get readinessLabel {
    final raw = result?.overallState ?? '';
    final v = raw.trim().toLowerCase();
    if (v == 'stable') return 'Stable';
    if (v == 'low focus' || v == 'low_focus') return 'Low Focus';
    if (v == 'elevated fatigue' || v == 'elevated_fatigue') {
      return 'Elevated Fatigue';
    }
    if (v == 'high risk' || v == 'high_risk') return 'High Risk';
    if (hasResult) return raw;
    final normalizedStatus = status.trim().toLowerCase();
    if (normalizedStatus == 'completed') {
      return 'Processing assessment';
    }
    if (normalizedStatus == 'pending') return 'Pending';
    if (normalizedStatus == 'processing' || normalizedStatus == 'in_progress') {
      return 'Processing assessment';
    }
    return status.trim().isEmpty ? 'Processing assessment' : status;
  }

  DateTime? get displayTime => completedAt ?? startedAt ?? dateCreated;
}
