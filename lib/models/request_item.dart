class RequestItem {
  final String id;
  final String? target;
  final String? businessProfileId;
  final String? requestedForId;
  final String? requestedForUserId;
  final String? requestedForEmail;
  final String? requestedForName;
  final String? requestedForPhone;
  final String? requestedForRole;
  final String? requestedByUserId;
  final String? requestedByUserEmail;
  final String? requestedByUserName;
  final String? requiredState;
  final String? requestType;
  final String? requiredMinReadiness;
  final String? responseStatus;
  final String? scanId;
  final DateTime? completedAt;
  final String? departmentId;
  final String? departmentName;
  final DateTime? timestamp;
  final DateTime? dueAt;

  const RequestItem({
    required this.id,
    this.target,
    this.businessProfileId,
    this.requestedForId,
    this.requestedForUserId,
    this.requestedForEmail,
    this.requestedForName,
    this.requestedForPhone,
    this.requestedForRole,
    this.requestedByUserId,
    this.requestedByUserEmail,
    this.requestedByUserName,
    this.requiredState,
    this.requestType,
    this.requiredMinReadiness,
    this.responseStatus,
    this.scanId,
    this.completedAt,
    this.departmentId,
    this.departmentName,
    this.timestamp,
    this.dueAt,
  });

  factory RequestItem.fromJson(Map<String, dynamic> json) {
    final requestedFor = json['target_member'];
    final requestedBy = json['requested_by_user'];
    final department = json['department'];

    final requestedForId = _relationField(requestedFor, 'id');
    final requestedForUserId =
        _nestedUserField(requestedFor, 'id') ??
        json['target_member_user_id']?.toString();
    final requestedForEmail =
        json['target_member_user_email']?.toString() ??
        _nestedUserField(requestedFor, 'email') ??
        _relationField(requestedFor, 'email');
    final requestedForName =
        json['target_member_user_name']?.toString() ??
        _relationName(requestedFor);
    final requestedForRole =
        json['target_member_role']?.toString() ??
        _relationField(requestedFor, 'member_role');

    final requestedByUserId = _relationField(requestedBy, 'id');
    final requestedByUserEmail =
        json['requested_by_user_email']?.toString() ??
        _relationField(requestedBy, 'email');
    final requestedByUserName =
        json['requested_by_user_name']?.toString() ??
        _relationName(requestedBy);
    final requestType = json['request_type']?.toString();
    final requiredMinReadiness = json['required_min_readiness']?.toString();

    return RequestItem(
      id: json['id']?.toString() ?? '',
      target: json['target']?.toString(),
      businessProfileId: _idField(json['business_profile']),
      requestedForId: requestedForId,
      requestedForUserId: requestedForUserId,
      requestedForEmail: requestedForEmail,
      requestedForName: requestedForName,
      requestedForPhone:
          _nestedUserField(requestedFor, 'phone') ??
          _relationField(requestedFor, 'phone'),
      requestedForRole: requestedForRole,
      requestedByUserId: requestedByUserId,
      requestedByUserEmail: requestedByUserEmail,
      requestedByUserName: requestedByUserName,
      requiredState: requiredMinReadiness ?? requestType,
      requestType: requestType,
      requiredMinReadiness: requiredMinReadiness,
      responseStatus: json['status']?.toString(),
      scanId: _idField(json['completed_scan']),
      completedAt: _parseDate(json['completed_at']),
      departmentId: _idField(department),
      departmentName: _relationName(department),
      timestamp: _parseDate(json['requested_at']),
      dueAt: _parseDate(json['due_at'] ?? json['due_date'] ?? json['deadline']),
    );
  }

  static String? _idField(dynamic value) {
    if (value is Map) return value['id']?.toString();
    return value?.toString();
  }

  static String? _relationField(dynamic value, String key) {
    if (value is Map) return value[key]?.toString();
    if (key == 'id') return value?.toString();
    return null;
  }

  static String? _nestedUserField(dynamic value, String key) {
    if (value is! Map) return null;
    final user = value['user'];
    if (user is! Map) return null;
    return user[key]?.toString();
  }

  static String? _relationName(dynamic value) {
    if (value is! Map) {
      return value?.toString().trim().isEmpty == false
          ? value.toString().trim()
          : null;
    }
    if (value['name'] != null &&
        value['name'].toString().trim().isNotEmpty &&
        value['user'] == null) {
      return value['name'].toString().trim();
    }
    final user = value['user'] is Map ? value['user'] as Map : value;
    final first = user['first_name']?.toString().trim();
    final last = user['last_name']?.toString().trim();
    if (first != null && first.isNotEmpty) {
      if (last != null && last.isNotEmpty) return '$first $last';
      return first;
    }
    if (user['email']?.toString().trim().isNotEmpty == true) {
      return user['email']?.toString().trim();
    }
    if (value['name']?.toString().trim().isNotEmpty == true) {
      return value['name']?.toString().trim();
    }
    return null;
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  String get displayStatus {
    final raw = responseStatus?.trim().toLowerCase() ?? '';
    final hasCompletedScan = scanId?.trim().isNotEmpty == true;
    final hasCompletedAt = completedAt != null;
    final isPastDue = dueAt != null && dueAt!.isBefore(DateTime.now());

    if (raw == 'cancelled' || raw == 'canceled') return 'cancelled';
    if (raw == 'completed' || hasCompletedScan || hasCompletedAt) {
      return 'completed';
    }
    if (raw == 'overdue' || isPastDue) return 'overdue';
    if (raw == 'requested' || raw == 'assigned' || raw == 'sent') {
      return raw;
    }
    return raw.isEmpty ? 'pending' : raw;
  }

  bool get hasCompletedScan => scanId?.trim().isNotEmpty == true;

  bool get isCompletedCanonical {
    return displayStatus.toLowerCase() == 'completed';
  }

  bool get isActionableCanonical {
    final status = displayStatus.toLowerCase();
    return status == 'pending' || status == 'requested' || status == 'assigned';
  }

  RequestItem copyWith({
    String? responseStatus,
    String? scanId,
    DateTime? completedAt,
    String? requestedForName,
    String? requestedForEmail,
    String? requestedForUserId,
    String? requestedForRole,
    String? requestedByUserName,
    String? requestedByUserEmail,
    String? departmentName,
  }) {
    return RequestItem(
      id: id,
      target: target,
      businessProfileId: businessProfileId,
      requestedForId: requestedForId,
      requestedForUserId: requestedForUserId ?? this.requestedForUserId,
      requestedForEmail: requestedForEmail ?? this.requestedForEmail,
      requestedForName: requestedForName ?? this.requestedForName,
      requestedForPhone: requestedForPhone,
      requestedForRole: requestedForRole ?? this.requestedForRole,
      requestedByUserId: requestedByUserId,
      requestedByUserEmail: requestedByUserEmail ?? this.requestedByUserEmail,
      requestedByUserName: requestedByUserName ?? this.requestedByUserName,
      requiredState: requiredState,
      requestType: requestType,
      requiredMinReadiness: requiredMinReadiness,
      responseStatus: responseStatus ?? this.responseStatus,
      scanId: scanId ?? this.scanId,
      completedAt: completedAt ?? this.completedAt,
      departmentId: departmentId,
      departmentName: departmentName ?? this.departmentName,
      timestamp: timestamp,
      dueAt: dueAt,
    );
  }

  String get displayUser {
    return displayTarget;
  }

  String get displayTarget {
    if (requestedForName != null && requestedForName!.trim().isNotEmpty) {
      return requestedForName!;
    }
    if (requestedForEmail != null && requestedForEmail!.trim().isNotEmpty) {
      return requestedForEmail!.split('@').first;
    }
    if (departmentName != null && departmentName!.trim().isNotEmpty) {
      return departmentName!;
    }
    if (target != null && target!.trim().isNotEmpty) {
      return target!;
    }
    if (requestedForId != null && requestedForId!.trim().isNotEmpty) {
      return 'Member #${requestedForId!.trim()}';
    }
    return '-';
  }

  String get displayDepartment {
    if (departmentName != null && departmentName!.trim().isNotEmpty) {
      return departmentName!;
    }
    return 'Recipient unavailable';
  }

  bool isAssignedToCurrentUser({
    String? currentUserId,
    String? currentMembershipId,
  }) {
    final normalizedUserId = currentUserId?.trim() ?? '';
    final normalizedMembershipId = currentMembershipId?.trim() ?? '';

    final requestedForUserId = this.requestedForUserId?.trim() ?? '';
    if (normalizedUserId.isNotEmpty &&
        requestedForUserId.isNotEmpty &&
        requestedForUserId == normalizedUserId) {
      return true;
    }

    final requestedForId = this.requestedForId?.trim() ?? '';
    if (normalizedMembershipId.isNotEmpty &&
        requestedForId.isNotEmpty &&
        requestedForId == normalizedMembershipId) {
      return true;
    }

    return false;
  }

  String? get requiredMinReadinessLabel {
    switch (requiredMinReadiness?.trim().toLowerCase()) {
      case 'stable':
        return 'Stable';
      case 'low_focus':
        return 'Low Focus';
      case 'elevated_fatigue':
        return 'Elevated Fatigue';
      default:
        return null;
    }
  }
}
