class Plan {
  final String id;
  final String name;
  final String code;
  final String description;
  final double? monthlyPrice;
  final double? yearlyPrice;
  final int trialDays;
  final int? maxMembers;
  final bool isBusiness;
  final List<String> features;
  final bool isPopular;
  final bool isActive;
  final int sortOrder;

  const Plan({
    required this.id,
    required this.name,
    required this.code,
    required this.description,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.trialDays,
    required this.maxMembers,
    required this.isBusiness,
    required this.features,
    required this.isPopular,
    required this.isActive,
    required this.sortOrder,
  });

  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      monthlyPrice: _toNumber(json['monthly_price']),
      yearlyPrice: _toNumber(json['yearly_price']),
      trialDays: _toInt(json['trial_days'], fallback: 14),
      maxMembers: _toNullableInt(json['max_members']),
      isBusiness:
          json['is_business'] == true ||
          (json['code']?.toString().trim().toLowerCase() == 'business'),
      features: _toFeatureList(json['features']),
      isPopular: json['is_popular'] == true,
      isActive: json['is_active'] != false,
      sortOrder: _toInt(json['sort_order']),
    );
  }

  Plan copyWith({
    String? id,
    String? name,
    String? code,
    String? description,
    double? monthlyPrice,
    double? yearlyPrice,
    int? trialDays,
    int? maxMembers,
    bool? isBusiness,
    List<String>? features,
    bool? isPopular,
    bool? isActive,
    int? sortOrder,
  }) {
    return Plan(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      description: description ?? this.description,
      monthlyPrice: monthlyPrice ?? this.monthlyPrice,
      yearlyPrice: yearlyPrice ?? this.yearlyPrice,
      trialDays: trialDays ?? this.trialDays,
      maxMembers: maxMembers ?? this.maxMembers,
      isBusiness: isBusiness ?? this.isBusiness,
      features: features ?? this.features,
      isPopular: isPopular ?? this.isPopular,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  static double? _toNumber(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      final parsed = double.tryParse(value.trim());
      return parsed;
    }
    return null;
  }

  static int _toInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      final parsed = int.tryParse(value.trim());
      return parsed ?? fallback;
    }
    return fallback;
  }

  static int? _toNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static List<String> _toFeatureList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      if (value.trim().startsWith('[')) {
        return value
            .replaceAll('[', '')
            .replaceAll(']', '')
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }
}
