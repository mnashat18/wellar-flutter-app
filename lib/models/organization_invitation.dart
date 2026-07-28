class OrganizationInvitation {
  final String id;
  final String email;
  final String status;
  final String inviteType;
  final String memberRole;
  final String businessProfileId;
  final String organizationName;
  final String? departmentId;
  final String? departmentName;
  final String? senderUserId;
  final String? senderName;
  final String? senderEmail;
  final DateTime? createdAt;
  final DateTime? sentAt;

  const OrganizationInvitation({
    required this.id,
    required this.email,
    required this.status,
    required this.inviteType,
    required this.memberRole,
    required this.businessProfileId,
    required this.organizationName,
    required this.departmentId,
    required this.departmentName,
    required this.senderUserId,
    required this.senderName,
    required this.senderEmail,
    required this.createdAt,
    required this.sentAt,
  });

  String get normalizedStatus => status.trim().toLowerCase();

  bool get isPendingState {
    final normalized = normalizedStatus;
    return normalized == 'pending' ||
        normalized == 'sent' ||
        normalized == 'invited';
  }

  String get roleLabel {
    final normalized = memberRole.trim().toLowerCase();
    switch (normalized) {
      case 'owner':
        return 'Owner';
      case 'hr':
        return 'HR';
      case 'manager':
      case 'manger':
        return 'Manager';
      case 'employee':
        return 'Employee';
      default:
        return memberRole.trim().isEmpty ? 'Member' : memberRole.trim();
    }
  }

  String get senderLabel {
    final name = senderName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final emailValue = senderEmail?.trim();
    if (emailValue != null && emailValue.isNotEmpty) return emailValue;
    return 'Organization admin';
  }

  factory OrganizationInvitation.fromJson(Map<String, dynamic> json) {
    final businessProfile = _asMap(json['business_profile']);
    final department = _asMap(json['department']);
    final sender = _asMap(json['requested_by_user']);
    return OrganizationInvitation(
      id: json['id']?.toString().trim() ?? '',
      email: json['email']?.toString().trim() ?? '',
      status: json['status']?.toString().trim() ?? 'pending',
      inviteType: json['invite_type']?.toString().trim() ?? '',
      memberRole: json['member_role']?.toString().trim() ?? 'employee',
      businessProfileId:
          businessProfile?['id']?.toString().trim() ??
          json['business_profile']?.toString().trim() ??
          '',
      organizationName: _organizationName(
        businessProfile?['company_name'],
        businessProfile?['business_name'],
      ),
      departmentId: department?['id']?.toString().trim(),
      departmentName: department?['name']?.toString().trim(),
      senderUserId: sender?['id']?.toString().trim(),
      senderName: _senderName(
        sender?['first_name'],
        sender?['last_name'],
        sender?['email'],
      ),
      senderEmail: sender?['email']?.toString().trim(),
      createdAt: _parseDate(json['date_created']),
      sentAt: _parseDate(json['sent_at']),
    );
  }

  static String _organizationName(dynamic companyName, dynamic businessName) {
    final company = companyName?.toString().trim();
    if (company != null && company.isNotEmpty) return company;
    final business = businessName?.toString().trim();
    if (business != null && business.isNotEmpty) return business;
    return 'Organization';
  }

  static String? _senderName(dynamic firstName, dynamic lastName, dynamic email) {
    final first = firstName?.toString().trim() ?? '';
    final last = lastName?.toString().trim() ?? '';
    final fullName = [first, last].where((part) => part.isNotEmpty).join(' ');
    if (fullName.isNotEmpty) return fullName;
    final senderEmail = email?.toString().trim();
    if (senderEmail != null && senderEmail.isNotEmpty) return senderEmail;
    return null;
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    final value = raw.toString().trim();
    if (value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }
}
