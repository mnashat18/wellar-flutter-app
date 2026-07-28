class AuditLog {
  final String id;
  final String? userId;
  final String? userEmail;
  final String type;
  final String description;
  final Map<String, dynamic>? metadata;
  final DateTime? timestamp;

  const AuditLog({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.type,
    required this.description,
    required this.metadata,
    required this.timestamp,
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) {
    return AuditLog(
      id: json['id'].toString(),
      userId: _parseUserId(json['user']),
      userEmail: _parseUserEmail(json['user'], json['user_email']),
      type: json['type']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      metadata: _parseMetadata(json['metadata'] ?? json['meta']),
      timestamp: _parseDate(json['timestamp'] ?? json['date_created']),
    );
  }

  static String? _parseUserId(dynamic value) {
    if (value == null) return null;
    if (value is String || value is num) return value.toString();
    if (value is Map && value['id'] != null) return value['id'].toString();
    return null;
  }

  static Map<String, dynamic>? _parseMetadata(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  static String? _parseUserEmail(dynamic value, dynamic fallbackEmail) {
    if (value is Map && value['email'] != null) {
      return value['email'].toString();
    }
    if (fallbackEmail != null) {
      final email = fallbackEmail.toString().trim();
      if (email.isNotEmpty) return email;
    }
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }
}
