class ActivityEvent {
  final String id;
  final String action;
  final String entityType;
  final String? entityId;
  final String? businessProfileId;
  final String? actorId;
  final String? actorName;
  final String? actorEmail;
  final String? targetUserId;
  final String? targetUserName;
  final String? targetUserEmail;
  final DateTime? createdAt;
  final Map<String, dynamic> payload;

  const ActivityEvent({
    required this.id,
    required this.action,
    required this.entityType,
    this.entityId,
    this.businessProfileId,
    this.actorId,
    this.actorName,
    this.actorEmail,
    this.targetUserId,
    this.targetUserName,
    this.targetUserEmail,
    this.createdAt,
    this.payload = const {},
  });

  factory ActivityEvent.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'];
    final target = json['target_user'];
    final business = json['business_profile'];
    String? businessProfileId;
    String? actorId;
    String? targetId;
    String? actorName;
    String? actorEmail;
    String? targetName;
    String? targetEmail;
    if (actor is Map) {
      actorId = actor['id']?.toString();
      actorEmail = actor['email']?.toString();
      actorName = _formatName(actor['first_name'], actor['last_name']);
      actorName ??= actorEmail;
    } else if (actor != null) {
      actorId = actor.toString();
    }
    if (target is Map) {
      targetId = target['id']?.toString();
      targetEmail = target['email']?.toString();
      targetName = _formatName(target['first_name'], target['last_name']);
      targetName ??= targetEmail;
    } else if (target != null) {
      targetId = target.toString();
    }
    if (business is Map) {
      businessProfileId = business['id']?.toString();
    } else if (business != null) {
      businessProfileId = business.toString();
    }

    final createdValue = json['created_at'] ?? json['date_created'];
    DateTime? createdAt;
    if (createdValue is String && createdValue.isNotEmpty) {
      createdAt = DateTime.tryParse(createdValue);
    }

    final payloadValue = json['payload'];
    Map<String, dynamic> payload = const {};
    if (payloadValue is Map<String, dynamic>) {
      payload = payloadValue;
    }

    return ActivityEvent(
      id: json['id']?.toString() ?? '',
      action: json['action']?.toString() ?? 'activity',
      entityType: json['entity_type']?.toString() ?? '',
      entityId: json['entity_id']?.toString(),
      businessProfileId: businessProfileId,
      actorId: actorId,
      actorName: actorName,
      actorEmail: actorEmail,
      targetUserId: targetId,
      targetUserName: targetName,
      targetUserEmail: targetEmail,
      createdAt: createdAt,
      payload: payload,
    );
  }

  static String? _formatName(dynamic first, dynamic last) {
    final firstName = first?.toString().trim();
    final lastName = last?.toString().trim();
    final parts = <String>[];
    if (firstName != null && firstName.isNotEmpty) parts.add(firstName);
    if (lastName != null && lastName.isNotEmpty) parts.add(lastName);
    if (parts.isEmpty) return null;
    return parts.join(' ');
  }
}
