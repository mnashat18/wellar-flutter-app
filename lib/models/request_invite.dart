class RequestInvite {
  final String token;
  final String link;
  final String message;
  final String? email;
  final String? phone;
  final DateTime? expiresAt;

  const RequestInvite({
    required this.token,
    required this.link,
    required this.message,
    this.email,
    this.phone,
    this.expiresAt,
  });
}
