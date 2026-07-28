class BusinessProfile {
  final String id;
  final String? ownerUserId;
  final String? sourceRequestId;
  final String companyName;
  final String businessName;
  final String contactName;
  final String? workEmail;
  final String? phone;
  final String? industry;
  final String? teamSize;
  final String? country;
  final String? city;
  final String? address;
  final String? website;
  final String? planCode;
  final String? billingStatus;
  final DateTime? trialStartedAt;
  final DateTime? trialExpiresAt;
  final String? trialExpiresRaw;
  final bool isActive;

  const BusinessProfile({
    required this.id,
    required this.ownerUserId,
    required this.sourceRequestId,
    required this.companyName,
    required this.businessName,
    required this.contactName,
    required this.workEmail,
    required this.phone,
    required this.industry,
    required this.teamSize,
    required this.country,
    required this.city,
    required this.address,
    required this.website,
    required this.planCode,
    required this.billingStatus,
    required this.trialStartedAt,
    required this.trialExpiresAt,
    required this.trialExpiresRaw,
    required this.isActive,
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    return BusinessProfile(
      id: json['id']?.toString() ?? '',
      ownerUserId: _extractId(json['owner_user']),
      sourceRequestId: _extractId(json['source_request']),
      companyName: json['company_name']?.toString() ?? '',
      businessName: json['business_name']?.toString() ?? '',
      contactName: _firstNonEmptyString([
        json['contact_name'],
        json['owner_name'],
        json['ownerName'],
      ]),
      workEmail: json['work_email']?.toString(),
      phone: json['phone']?.toString(),
      industry: json['industry']?.toString(),
      teamSize: json['team_size']?.toString(),
      country: json['country']?.toString(),
      city: json['city']?.toString(),
      address: json['address']?.toString(),
      website: json['website']?.toString(),
      planCode: json['plan_code']?.toString(),
      billingStatus: json['billing_status']?.toString(),
      trialStartedAt: _toDate(json['trial_started_at']),
      trialExpiresAt: _toDate(json['trial_expires_at']),
      trialExpiresRaw: json['trial_expires_at']?.toString(),
      isActive: _toBool(json['is_active'], fallback: true),
    );
  }

  String get displayName {
    final name = businessName.trim();
    if (name.isNotEmpty) return name;
    final company = companyName.trim();
    if (company.isNotEmpty) return company;
    final email = (workEmail ?? '').trim();
    if (email.isNotEmpty) return email;
    return 'Business';
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

  static String _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString() ?? '';
      if (text.trim().isNotEmpty) return text;
    }
    return '';
  }
}
