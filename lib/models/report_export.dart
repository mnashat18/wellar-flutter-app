class ReportExport {
  final String id;
  final String? userId;
  final String? businessProfileId;
  final String format;
  final String status;
  final String? fileId;
  final Map<String, dynamic>? filters;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final String? errorMessage;

  const ReportExport({
    required this.id,
    this.userId,
    this.businessProfileId,
    required this.format,
    required this.status,
    this.fileId,
    this.filters,
    this.createdAt,
    this.completedAt,
    this.errorMessage,
  });

  factory ReportExport.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    String? userId;
    if (user is Map) {
      userId = user['id']?.toString();
    } else if (user != null) {
      userId = user.toString();
    }

    final file = json['file'];
    String? fileId;
    if (file is Map) {
      fileId = file['id']?.toString();
    } else if (file != null) {
      fileId = file.toString();
    }

    final business = json['business_profile'];
    String? businessProfileId;
    if (business is Map) {
      businessProfileId = business['id']?.toString();
    } else if (business != null) {
      businessProfileId = business.toString();
    }

    final createdValue = json['created_at'] ?? json['date_created'];
    final completedValue = json['completed_at'];
    final rawFilters = json['filters'];
    Map<String, dynamic>? filters;
    if (rawFilters is Map<String, dynamic>) {
      filters = rawFilters;
    } else if (rawFilters is Map) {
      filters = rawFilters.map((key, value) => MapEntry(key.toString(), value));
    }

    return ReportExport(
      id: json['id']?.toString() ?? '',
      userId: userId,
      businessProfileId: businessProfileId,
      format: json['format']?.toString() ?? 'csv',
      status: json['status']?.toString() ?? 'pending',
      fileId: fileId,
      filters: filters,
      createdAt: createdValue is String
          ? DateTime.tryParse(createdValue)
          : null,
      completedAt: completedValue is String
          ? DateTime.tryParse(completedValue)
          : null,
      errorMessage: json['error_message']?.toString(),
    );
  }
}
