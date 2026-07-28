class NotificationItem {
  final String id;
  final String title;
  final String body;
  final String type;
  final String status;
  final String? linkType;
  final String? linkId;
  final Map<String, dynamic>? meta;
  final DateTime? createdAt;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.status,
    this.linkType,
    this.linkId,
    this.meta,
    this.createdAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final createdValue = json['created_at'] ?? json['date_created'];
    DateTime? createdAt;
    if (createdValue is String && createdValue.isNotEmpty) {
      createdAt = DateTime.tryParse(createdValue);
    }
    final rawMeta = json['meta'];
    Map<String, dynamic>? meta;
    if (rawMeta is Map<String, dynamic>) {
      meta = rawMeta;
    } else if (rawMeta is Map) {
      meta = rawMeta.map((key, value) => MapEntry(key.toString(), value));
    }

    return NotificationItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      type: json['type']?.toString() ?? 'system',
      status: json['status']?.toString() ?? 'unread',
      linkType: json['link_type']?.toString(),
      linkId: json['link_id']?.toString(),
      meta: meta,
      createdAt: createdAt,
    );
  }

  bool get isUnread {
    final value = status.trim().toLowerCase();
    if (value.isEmpty) return true;
    return value != 'read';
  }

  NotificationItem copyAsRead() {
    return NotificationItem(
      id: id,
      title: title,
      body: body,
      type: type,
      status: 'read',
      linkType: linkType,
      linkId: linkId,
      meta: meta,
      createdAt: createdAt,
    );
  }
}
