class Organization {
  final String id;
  final String name;
  final String industry;

  const Organization({
    required this.id,
    required this.name,
    required this.industry,
  });

  factory Organization.fromJson(Map<String, dynamic> json) {
    return Organization(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      industry: json['industry']?.toString() ?? '',
    );
  }
}
