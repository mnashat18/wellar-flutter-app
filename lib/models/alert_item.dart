class AlertItem {
  final String id;
  final String title;
  final String summary;
  final String type;
  final String status;
  final String? severity;
  final String? actionType;
  final String? relatedScanId;
  final String? relatedRequestId;
  final DateTime? createdAt;
  final Map<String, dynamic>? scan;
  final Map<String, dynamic>? targetUser;
  final Map<String, dynamic>? targetMember;
  final Map<String, dynamic>? businessProfile;
  final Map<String, dynamic>? department;

  const AlertItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.type,
    required this.status,
    required this.severity,
    required this.actionType,
    required this.relatedScanId,
    required this.relatedRequestId,
    required this.createdAt,
    required this.scan,
    required this.targetUser,
    required this.targetMember,
    required this.businessProfile,
    required this.department,
  });

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    final createdValue = json['created_at'] ?? json['date_created'];
    DateTime? createdAt;
    if (createdValue is String && createdValue.isNotEmpty) {
      createdAt = DateTime.tryParse(createdValue);
    }
    final type =
        _nonEmpty(json['type']) ?? _nonEmpty(json['alert_type']) ?? 'general';
    final title = _nonEmpty(json['title']) ?? _typeToTitle(type);
    final body =
        _nonEmpty(json['body']) ??
        _nonEmpty(json['message']) ??
        _nonEmpty(json['summary']) ??
        'Operational alert';
    final scan = _map(json['scan']);
    final targetUser = _map(json['target_user']);
    final targetMember = _map(json['target_member']);
    final businessProfile = _map(json['business_profile']);
    final department = _map(json['department']);
    final scanId = _relationId(scan ?? json['scan_id'] ?? json['scan_result']);

    return AlertItem(
      id: json['id']?.toString() ?? '',
      title: title,
      summary: body,
      type: type,
      status: _nonEmpty(json['status']) ?? 'open',
      severity: _nonEmpty(json['severity']),
      actionType: _nonEmpty(json['action_type']),
      relatedScanId: scanId,
      relatedRequestId: _relationId(json['scan_request']),
      createdAt: createdAt,
      scan: scan,
      targetUser: targetUser,
      targetMember: targetMember,
      businessProfile: businessProfile,
      department: department,
    );
  }

  bool get isOpen {
    final s = status.trim().toLowerCase();
    return s.isEmpty || (s != 'closed' && s != 'resolved');
  }

  bool get actionRequired {
    final s = status.trim().toLowerCase();
    final sev = (severity ?? '').trim().toLowerCase();
    return isOpen &&
        (s == 'action_required' || s == 'pending' || sev == 'high');
  }

  static String? _nonEmpty(dynamic value) {
    final v = value?.toString().trim() ?? '';
    return v.isEmpty ? null : v;
  }

  static String? _relationId(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) {
      return value['id']?.toString();
    }
    if (value is Map) {
      return value['id']?.toString();
    }
    final v = value.toString().trim();
    return v.isEmpty ? null : v;
  }

  static Map<String, dynamic>? _map(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, dynamic mapValue) => MapEntry(key.toString(), mapValue),
      );
    }
    return null;
  }

  static String _typeToTitle(String type) {
    switch (type.trim().toLowerCase()) {
      case 'scan_result_ready':
        return 'Your readiness result is ready';
      case 'scan_result_pending':
        return 'Result is still being prepared';
      case 'scan_request_created':
      case 'scan_request_assigned':
        return 'New readiness request';
      case 'missed_scan':
        return 'Missed readiness check';
      default:
        return 'Action required';
    }
  }

  String? get employeeName {
    final memberUser = _map(targetMember)?['user'];
    final fromMemberUser = _personName(memberUser);
    if (fromMemberUser != null) return fromMemberUser;
    final fromTargetUser = _personName(targetUser);
    if (fromTargetUser != null) return fromTargetUser;
    final memberName = _nonEmpty(_map(targetMember)?['name']);
    if (memberName != null) return memberName;
    return _nonEmpty(_map(scan)?['user_name_snapshot']);
  }

  String? get employeeEmail {
    final memberUser = _map(targetMember)?['user'];
    final fromMemberUser = _personEmail(memberUser);
    if (fromMemberUser != null) return fromMemberUser;
    final fromTargetUser = _personEmail(targetUser);
    if (fromTargetUser != null) return fromTargetUser;
    return null;
  }

  String? get employeeRole {
    final memberRole = _nonEmpty(_map(targetMember)?['member_role']);
    if (memberRole != null) return memberRole;
    return _nonEmpty(_map(targetUser)?['role']);
  }

  DateTime? get scanCompletedAt {
    final scanMap = scan;
    final completedValue = scanMap?['completed_at'] ?? scanMap?['date_created'];
    if (completedValue is String && completedValue.isNotEmpty) {
      return DateTime.tryParse(completedValue);
    }
    return null;
  }

  String? get scanState {
    final scanMap = scan;
    return _nonEmpty(scanMap?['status']);
  }

  String? get recommendedAction {
    return _nonEmpty(_map(scan)?['recommended_action']) ?? actionType;
  }

  static String? _personName(dynamic value) {
    final map = _map(value);
    if (map == null) return null;
    final first = _nonEmpty(map['first_name']);
    final last = _nonEmpty(map['last_name']);
    if (first != null) {
      if (last != null) return '$first $last';
      return first;
    }
    return _nonEmpty(map['name']);
  }

  static String? _personEmail(dynamic value) {
    final map = _map(value);
    if (map == null) return null;
    return _nonEmpty(map['email']);
  }
}
