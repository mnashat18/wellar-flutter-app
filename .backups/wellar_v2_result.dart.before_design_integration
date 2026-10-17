class WellarV2Target {
  final String status;
  final dynamic value;
  final String? reason;

  const WellarV2Target({required this.status, this.value, this.reason});

  factory WellarV2Target.fromJson(dynamic value) {
    if (value is! Map) return const WellarV2Target(status: 'unavailable');
    return WellarV2Target(
      status: value['status']?.toString() ?? 'unavailable',
      value: value['value'],
      reason: value['reason']?.toString(),
    );
  }
}

/// V2's descriptive output is deliberately separate from legacy readiness
/// scores and categories.
class WellarV2Result {
  final String schemaVersion;
  final String scanId;
  final String status;
  final String? modelVersion;
  final String modelInvocationStatus;
  final Map<String, WellarV2Target> targets;
  final Map<String, dynamic> quality;
  final Map<String, dynamic> features;
  final String message;

  const WellarV2Result({
    required this.schemaVersion,
    required this.scanId,
    required this.status,
    required this.modelVersion,
    required this.modelInvocationStatus,
    required this.targets,
    required this.quality,
    required this.features,
    required this.message,
  });

  factory WellarV2Result.fromJson(Map<String, dynamic> json) {
    final rawTargets = json['targets'];
    final targets = <String, WellarV2Target>{};
    if (rawTargets is Map) {
      for (final entry in rawTargets.entries) {
        targets[entry.key.toString()] = WellarV2Target.fromJson(entry.value);
      }
    }
    return WellarV2Result(
      schemaVersion: json['schema_version']?.toString() ?? '',
      scanId: json['scan_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      modelVersion: json['model_version']?.toString(),
      modelInvocationStatus:
          json['model_invocation_status']?.toString() ?? 'unknown',
      targets: Map.unmodifiable(targets),
      quality: _stringMap(json['quality']),
      features: _stringMap(json['features']),
      message: json['message']?.toString() ?? '',
    );
  }

  static Map<String, dynamic> _stringMap(dynamic value) {
    if (value is! Map) return const {};
    return Map.unmodifiable(
      value.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}
