class UserSummary {
  final String id;
  final String email;
  final String? name;

  const UserSummary({
    required this.id,
    required this.email,
    this.name,
  });

  factory UserSummary.fromJson(Map<String, dynamic> json) {
    return UserSummary(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      name: json['first_name']?.toString(),
    );
  }
}
