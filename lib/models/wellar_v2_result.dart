import 'dart:convert';

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
  final Map<String, dynamic> drowsinessIndicator;
  final Map<String, dynamic> internalAnalysis;
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
    required this.drowsinessIndicator,
    required this.internalAnalysis,
    required this.message,
  });

  factory WellarV2Result.fromJson(Map<String, dynamic> json) {
    final internal = _decodeMap(json['internal_analysis']);
    final evidence = _stringMap(json['evidence']);
    final evidenceIndicator = _stringMap(evidence['drowsiness_indicator']);
    final indicator = _stringMap(json['drowsiness_indicator']);
    final internalIndicator = _stringMap(internal['drowsiness_indicator']);
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
      quality: _stringMap(json['quality']).isNotEmpty
          ? _stringMap(json['quality'])
          : _stringMap(internal['quality']),
      features: _stringMap(json['features']).isNotEmpty
          ? _stringMap(json['features'])
          : _stringMap(internal['features']),
      drowsinessIndicator: indicator.isNotEmpty
          ? indicator
          : evidenceIndicator.isNotEmpty
          ? evidenceIndicator
          : internalIndicator,
      internalAnalysis: Map.unmodifiable(internal),
      message: json['message']?.toString() ?? '',
    );
  }

  static Map<String, dynamic> _stringMap(dynamic value) {
    if (value is! Map) return const {};
    return Map.unmodifiable(
      value.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  static Map<String, dynamic> _decodeMap(dynamic value) {
    if (value is Map) return _stringMap(value);
    if (value is! String || value.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(value);
      return _stringMap(decoded);
    } on FormatException {
      return const {};
    }
  }

  double? get eyeClosureFraction => _finiteNumber(
    _measurements['short_clip_eye_closure_fraction'],
  );

  double? get blinkRatePerMinute =>
      _finiteNumber(_measurements['blink_rate_per_minute']);

  Map<String, dynamic> get _measurements => _stringMap(
    drowsinessIndicator['raw_measurements'],
  );

  static double? _finiteNumber(dynamic value) {
    if (value is! num || !value.isFinite) return null;
    return value.toDouble();
  }
}
