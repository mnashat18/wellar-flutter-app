import 'plan.dart';

class UserSubscription {
  final String id;
  final Plan? plan;
  final String? businessProfileId;
  final String? userId;
  final String status;
  final String billingCycle;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final int? currentMembersCount;

  const UserSubscription({
    required this.id,
    required this.plan,
    required this.businessProfileId,
    required this.userId,
    required this.status,
    required this.billingCycle,
    required this.startedAt,
    required this.expiresAt,
    required this.createdAt,
    required this.currentMembersCount,
  });

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    final planData = json['plan'];
    return UserSubscription(
      id: json['id']?.toString() ?? '',
      plan: planData is Map<String, dynamic> ? Plan.fromJson(planData) : null,
      businessProfileId: _extractId(json['business_profile']),
      userId: _extractId(json['user']),
      status: json['status']?.toString() ?? '',
      billingCycle: json['billing_cycle']?.toString() ?? 'monthly',
      startedAt: _parseDate(json['started_at']),
      expiresAt: _parseDate(json['expires_at']),
      createdAt: _parseDate(json['date_created']),
      currentMembersCount: _toInt(json['current_members_count']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static String? _extractId(dynamic value) {
    if (value == null) return null;
    if (value is String || value is num) {
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }
    if (value is Map) {
      final id = value['id']?.toString().trim();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}
