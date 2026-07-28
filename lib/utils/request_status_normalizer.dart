import 'package:flutter/foundation.dart';

import '../models/request_item.dart';

enum NormalizedRequestStatus { pending, completed, overdue, cancelled }

class RequestStatusNormalizer {
  const RequestStatusNormalizer._();

  static NormalizedRequestStatus normalize(
    RequestItem item, {
    DateTime? now,
    bool log = true,
  }) {
    return normalizeRaw(
      requestId: item.id,
      rawStatus: item.responseStatus,
      dueAt: item.dueAt,
      completedScanId: item.scanId,
      now: now,
      log: log,
    );
  }

  static NormalizedRequestStatus normalizeRaw({
    required String requestId,
    required String? rawStatus,
    required DateTime? dueAt,
    required String? completedScanId,
    DateTime? now,
    bool log = true,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final status = rawStatus?.trim().toLowerCase() ?? '';
    final scanId = completedScanId?.trim() ?? '';
    final hasRealDueDate = dueAt != null;
    final isPastDue =
        hasRealDueDate && dueAt.toLocal().isBefore(effectiveNow.toLocal());

    late final NormalizedRequestStatus normalized;
    late final String source;
    switch (status) {
      case 'pending':
      case 'requested':
      case 'assigned':
        if (scanId.isNotEmpty) {
          normalized = NormalizedRequestStatus.completed;
          source = 'completed_scan';
          break;
        }
        if (isPastDue) {
          normalized = NormalizedRequestStatus.overdue;
          source = 'derived_due_date';
          break;
        }
        normalized = NormalizedRequestStatus.pending;
        source = 'backend_status';
        break;
      case 'completed':
        normalized = NormalizedRequestStatus.completed;
        source = 'backend_status';
        break;
      case 'overdue':
        normalized = NormalizedRequestStatus.overdue;
        source = 'backend_status';
        break;
      case 'cancelled':
      case 'canceled':
        normalized = NormalizedRequestStatus.cancelled;
        source = 'backend_status';
        break;
      default:
        if (scanId.isNotEmpty) {
          normalized = NormalizedRequestStatus.completed;
          source = 'completed_scan';
        } else if (isPastDue) {
          normalized = NormalizedRequestStatus.overdue;
          source = 'derived_due_date';
        } else {
          normalized = NormalizedRequestStatus.pending;
          source = status.isEmpty ? 'missing_status' : 'unknown_status';
        }
    }

    if (log) {
      debugPrint(
        '[REQUEST_STATUS_NORMALIZE] has_request_id=${requestId.trim().isNotEmpty} raw_status=${status.isEmpty ? "-" : status} has_due_date=$hasRealDueDate normalized_status=${normalized.label} source=$source',
      );
    }
    return normalized;
  }
}

extension NormalizedRequestStatusLabel on NormalizedRequestStatus {
  String get label {
    switch (this) {
      case NormalizedRequestStatus.pending:
        return 'Pending';
      case NormalizedRequestStatus.completed:
        return 'Completed';
      case NormalizedRequestStatus.overdue:
        return 'Overdue';
      case NormalizedRequestStatus.cancelled:
        return 'Cancelled';
    }
  }
}
