class InviteDetails {
  final String inviteId;
  final String token;
  final String status;
  final String? requestId;
  final String? orgName;
  final String? requesterName;
  final String? requiredState;
  final String? target;
  final String? email;
  final String? phone;
  final DateTime? sentAt;
  final DateTime? expiresAt;

  const InviteDetails({
    required this.inviteId,
    required this.token,
    required this.status,
    this.requestId,
    this.orgName,
    this.requesterName,
    this.requiredState,
    this.target,
    this.email,
    this.phone,
    this.sentAt,
    this.expiresAt,
  });

  bool get isExpired => status.toLowerCase() == 'expired';
  bool get isClaimed => status.toLowerCase() == 'claimed';
  bool get isActionable => !isExpired && !isClaimed;

  String get senderLabel {
    final org = orgName?.trim();
    final requester = requesterName?.trim();
    if (org != null && org.isNotEmpty && requester != null && requester.isNotEmpty) {
      return '$org - $requester';
    }
    if (org != null && org.isNotEmpty) return org;
    if (requester != null && requester.isNotEmpty) return requester;
    return 'Your team';
  }
}
