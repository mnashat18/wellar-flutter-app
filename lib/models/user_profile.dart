class UserProfile {
  final String id;
  final String email;
  final String name;
  final String roleName;

  const UserProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.roleName,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final role = json['role'];
    String roleName = '';
    if (role is Map && role['name'] != null) {
      roleName = role['name'].toString();
    }
    return UserProfile(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      name: json['first_name']?.toString() ?? '',
      roleName: roleName,
    );
  }
}
