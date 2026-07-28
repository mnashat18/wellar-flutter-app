class BusinessProfileMember {
  final String id;
  final String businessProfileId;
  final String userId;
  final String? userEmail;
  final String? userFirstName;
  final String? userLastName;
  final String memberRole;
  final String status;

  const BusinessProfileMember({
    required this.id,
    required this.businessProfileId,
    required this.userId,
    required this.userEmail,
    required this.userFirstName,
    required this.userLastName,
    required this.memberRole,
    required this.status,
  });

  factory BusinessProfileMember.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    String userId = '';
    String? userEmail;
    String? firstName;
    String? lastName;
    if (user is Map) {
      userId = user['id']?.toString() ?? '';
      userEmail = user['email']?.toString();
      firstName = user['first_name']?.toString();
      lastName = user['last_name']?.toString();
    } else if (user != null) {
      userId = user.toString();
    }

    final business = json['business_profile'];
    String businessProfileId = '';
    if (business is Map) {
      businessProfileId = business['id']?.toString() ?? '';
    } else if (business != null) {
      businessProfileId = business.toString();
    }

    return BusinessProfileMember(
      id: json['id']?.toString() ?? '',
      businessProfileId: businessProfileId,
      userId: userId,
      userEmail: userEmail,
      userFirstName: firstName,
      userLastName: lastName,
      memberRole: json['member_role']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }

  String get displayName {
    final parts = <String>[];
    final first = userFirstName?.trim();
    final last = userLastName?.trim();
    if (first != null && first.isNotEmpty) parts.add(first);
    if (last != null && last.isNotEmpty) parts.add(last);
    if (parts.isNotEmpty) return parts.join(' ');
    final email = userEmail?.trim();
    if (email != null && email.isNotEmpty) return email;
    return 'Member profile unavailable';
  }
}
