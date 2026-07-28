class BusinessAutomationRule {
  final String id;
  final String orgId;
  final String ruleName;
  final String trigger;
  final String action;
  final double? threshold;
  final int? cooldownMinutes;
  final bool isActive;
  final DateTime? dateCreated;

  const BusinessAutomationRule({
    required this.id,
    required this.orgId,
    required this.ruleName,
    required this.trigger,
    required this.action,
    required this.threshold,
    required this.cooldownMinutes,
    required this.isActive,
    required this.dateCreated,
  });

  factory BusinessAutomationRule.fromJson(Map<String, dynamic> json) {
    return BusinessAutomationRule(
      id: json['id']?.toString() ?? '',
      orgId: _extractId(json['org_id']) ?? '',
      ruleName: json['rule_name']?.toString() ?? '',
      trigger: json['trigger']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      threshold: _toDouble(json['threshold']),
      cooldownMinutes: _toInt(json['cooldown_minutes']),
      isActive: _toBool(json['is_active'], fallback: true),
      dateCreated: _toDate(json['date_created']),
    );
  }

  static String? _extractId(dynamic value) {
    if (value == null) return null;
    if (value is String || value is num) return value.toString();
    if (value is Map && value['id'] != null) {
      return value['id'].toString();
    }
    return null;
  }

  static DateTime? _toDate(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value);
    }
    return null;
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      return int.tryParse(value);
    }
    return null;
  }

  static bool _toBool(dynamic value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return fallback;
  }
}
