class BusinessUpgradeRequest {
  final String id;
  final String? requestedByUser;
  final DateTime? requestedAt;
  final String status;
  final String? requestedPlan;
  final String? currentPlan;
  final String? billingCycle;
  final String? notes;
  final double? basePriceUsd;
  final double? discountUsd;
  final double? finalPriceUsd;
  final bool? isNewUserOffer;
  final String? companyName;
  final String? businessName;
  final String? ownerName;
  final String? workEmail;
  final String? phone;
  final String? industry;
  final String? teamSize;
  final String? country;
  final String? city;
  final String? address;
  final String? website;

  const BusinessUpgradeRequest({
    required this.id,
    required this.requestedByUser,
    required this.requestedAt,
    required this.status,
    required this.requestedPlan,
    required this.currentPlan,
    required this.billingCycle,
    required this.notes,
    required this.basePriceUsd,
    required this.discountUsd,
    required this.finalPriceUsd,
    required this.isNewUserOffer,
    required this.companyName,
    required this.businessName,
    required this.ownerName,
    required this.workEmail,
    required this.phone,
    required this.industry,
    required this.teamSize,
    required this.country,
    required this.city,
    required this.address,
    required this.website,
  });

  factory BusinessUpgradeRequest.fromJson(Map<String, dynamic> json) {
    return BusinessUpgradeRequest(
      id: json['id']?.toString() ?? '',
      requestedByUser: _extractId(json['requested_by_user']),
      requestedAt:
          _toDate(json['requested_at']) ?? _toDate(json['date_created']),
      status: json['status']?.toString() ?? '',
      requestedPlan: json['requested_plan']?.toString(),
      currentPlan: json['current_plan']?.toString(),
      billingCycle: json['billing_cycle']?.toString(),
      notes: json['notes']?.toString(),
      basePriceUsd: _toDouble(json['base_price_usd']),
      discountUsd: _toDouble(json['discount_usd']),
      finalPriceUsd: _toDouble(json['final_price_usd']),
      isNewUserOffer: _toBoolOrNull(json['is_new_user_offer']),
      companyName: json['company_name']?.toString(),
      businessName: json['business_name']?.toString(),
      ownerName: json['owner_name']?.toString(),
      workEmail: json['work_email']?.toString(),
      phone: json['phone']?.toString(),
      industry: json['industry']?.toString(),
      teamSize: json['team_size']?.toString(),
      country: json['country']?.toString(),
      city: json['city']?.toString(),
      address: json['address']?.toString(),
      website: json['website']?.toString(),
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

  static bool? _toBoolOrNull(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return null;
  }
}
