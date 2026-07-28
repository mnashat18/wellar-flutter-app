class BusinessLocation {
  final String id;
  final String orgId;
  final String locationName;
  final String code;
  final String? city;
  final String? country;
  final String? address;
  final String? manager;
  final bool isActive;
  final DateTime? dateCreated;

  const BusinessLocation({
    required this.id,
    required this.orgId,
    required this.locationName,
    required this.code,
    required this.city,
    required this.country,
    required this.address,
    required this.manager,
    required this.isActive,
    required this.dateCreated,
  });

  factory BusinessLocation.fromJson(Map<String, dynamic> json) {
    return BusinessLocation(
      id: json['id']?.toString() ?? '',
      orgId: _extractId(json['org_id']) ?? '',
      locationName: json['location_name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      city: json['city']?.toString(),
      country: json['country']?.toString(),
      address: json['address']?.toString(),
      manager: json['manager']?.toString(),
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
