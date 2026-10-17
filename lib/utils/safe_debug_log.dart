import 'package:flutter/foundation.dart';

/// Emits pre-sanitized readiness diagnostics only in debug builds.
/// Callers must restrict values to counts, booleans, role names, dates,
/// field names, and an eight-character profile_prefix.
void readinessDebugLog(String message) {
  if (!kDebugMode || !message.startsWith('[READINESS_DEBUG]')) return;
  debugPrint(message);
}

/// Keeps useful diagnostic event/status data while omitting identity and
/// payload values from console output.
void safeDebugLog(String message) {
  final tag = RegExp(r'^\[([^\]]+)\]').firstMatch(message)?.group(1);
  final allowedFields = <String>{
    'status',
    'http_status',
    'duration_ms',
    'error_type',
    'dio_type',
    'step',
    'reason',
    'failure_code',
    'method',
    'operation',
    'source',
    'destination',
    'feature',
    'started',
    'success',
    'visible',
    'context_unchanged',
    'target_verified',
    'context_applied',
    'revision_incremented',
    'signature_changed',
    'diagnostic_only',
    'stack_present',
    'result_count',
    'member_count',
    'body_count',
    'raw_count',
    'count',
    'profile_present',
    'has_query',
    'has_user',
    'has_current_user',
    'has_incoming_user',
    'has_active_member',
    'has_membership_id',
    'has_target_member',
    'has_business_profile',
    'has_recipient_user',
    'membership_id_present',
    'business_profile_present',
    'scoped_profile',
    'scoped_department',
    'scoped_member',
    'empty_result',
    'resolved',
    'unresolved',
    'fallback_used',
    'auth_header_present',
    'query_profile_matches_active',
    'profile_source',
    'profile_source_cached',
    'cached_profile_is_current',
    'outgoing_profile_present',
    'active_profile_present',
    'row_workspace_matches_active',
    'condition',
    'rejected',
    'raw_rows_workspace_mismatch',
    'raw_rows_workspace_id_missing',
    'period_start',
    'period_end',
    'failed',
  };
  final fields = RegExp(r'\b([A-Za-z][A-Za-z0-9_]*)=([^\s,]+)')
      .allMatches(message)
      .where((match) {
        final key = match.group(1)!.toLowerCase();
        if (allowedFields.contains(key)) return true;
        if (key.startsWith('has_') || key.endsWith('_present')) {
          final value = match.group(2)!.toLowerCase();
          return value == 'true' || value == 'false';
        }
        if (key.endsWith('_count')) return true;
        return false;
      })
      .map((match) => '${match.group(1)}=${match.group(2)}')
      .toList();
  final safeTag = tag == null ? '[DIAGNOSTIC]' : '[$tag]';
  debugPrint(fields.isEmpty ? safeTag : '$safeTag ${fields.join(' ')}');
}
