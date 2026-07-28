import 'package:flutter/foundation.dart';

class ScanResult {
  final String id;
  final String scanId;
  final DateTime? dateCreated;
  final String? riskLevel;
  final String overallState;
  final double? readinessScore;
  final double? confidence;
  final double? cameraConfidence;
  final double? voiceConfidence;
  final double? taskPerformanceScore;
  final double? confidenceDrift;
  final DateTime? completedAt;
  final String? explanation;
  final String? suggestedAction;
  final String? readinessSummary;
  final String? operationalSummary;
  final String? recommendedAction;
  final String? aiModelVersion;
  final bool? baselineUsed;
  final Map<String, dynamic>? faceMetrics;
  final Map<String, dynamic>? voiceMetrics;
  final Map<String, dynamic>? reactionMetrics;
  String? get medicalReport => readinessSummary ?? operationalSummary;

  const ScanResult({
    required this.id,
    required this.scanId,
    required this.dateCreated,
    this.riskLevel,
    required this.overallState,
    this.readinessScore,
    this.confidence,
    this.cameraConfidence,
    this.voiceConfidence,
    this.taskPerformanceScore,
    this.confidenceDrift,
    this.completedAt,
    this.explanation,
    this.suggestedAction,
    this.readinessSummary,
    this.operationalSummary,
    this.recommendedAction,
    this.aiModelVersion,
    this.baselineUsed,
    this.faceMetrics,
    this.voiceMetrics,
    this.reactionMetrics,
  });

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    try {
      if (kDebugMode) {
        debugPrint(
          '[SCAN_PARSE] start id=${json['id']?.toString() ?? '-'} scan_id=${json['scan_id']?.toString() ?? '-'}',
        );
      }
      final scanValue = json['scan_id'];
      final scanId = scanValue is Map && scanValue['id'] != null
          ? scanValue['id'].toString()
          : scanValue?.toString() ?? '';
      final riskLevel =
          json['risk_level']?.toString() ??
          json['riskLevel']?.toString() ??
          json['state']?.toString() ??
          json['readiness_state']?.toString() ??
          json['overall_state']?.toString();
      final result = ScanResult(
        id: json['id'].toString(),
        scanId: scanId,
        dateCreated: json['date_created'] != null
            ? DateTime.tryParse(json['date_created'].toString())
            : null,
        riskLevel: riskLevel,
        overallState:
            riskLevel ??
            json['readiness_label']?.toString() ??
            json['readinessLabel']?.toString() ??
            'Review needed',
        readinessScore: _toDouble(
          json['readiness_score'] ?? json['readinessScore'],
        ),
        confidence: _toDouble(json['confidence']),
        cameraConfidence: _toDouble(
          json['camera_confidence'] ?? json['cameraConfidence'],
        ),
        voiceConfidence: _toDouble(
          json['voice_confidence'] ?? json['voiceConfidence'],
        ),
        taskPerformanceScore: _toDouble(
          json['task_performance_score'] ?? json['taskPerformanceScore'],
        ),
        confidenceDrift: _toDouble(
          json['confidence_drift'] ?? json['confidenceDrift'],
        ),
        completedAt: json['completed_at'] != null
            ? DateTime.tryParse(json['completed_at'].toString())
            : null,
        explanation: json['explanation']?.toString(),
        suggestedAction:
            json['suggested_action']?.toString() ??
            json['suggestedAction']?.toString(),
        readinessSummary: json['readiness_summary']?.toString(),
        operationalSummary: json['operational_summary']?.toString(),
        recommendedAction:
            json['recommended_action']?.toString() ??
            json['recommendedAction']?.toString(),
        aiModelVersion: json['ai_model_version']?.toString(),
        baselineUsed: _toBool(json['baseline_used'] ?? json['baselineUsed']),
        faceMetrics: _toMap(json['face_metrics'] ?? json['faceMetrics']),
        voiceMetrics: _toMap(json['voice_metrics'] ?? json['voiceMetrics']),
        reactionMetrics: _toMap(
          json['reaction_metrics'] ?? json['reactionMetrics'],
        ),
      );
      if (kDebugMode) {
        debugPrint(
          '[SCAN_PARSE] success id=${result.id} scan_id=${result.scanId} risk_level=${result.riskLevel ?? '-'} readiness_score=${result.readinessScore?.toString() ?? '-'}',
        );
      }
      return result;
    } catch (e, s) {
      if (kDebugMode) {
        debugPrint(
          '[SCAN_PARSE] error id=${json['id']?.toString() ?? '-'} scan_id=${json['scan_id']?.toString() ?? '-'} error=$e',
        );
        debugPrint('[SCAN_PARSE] stack $s');
      }
      rethrow;
    }
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static Map<String, dynamic>? _toMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, dynamic mapValue) => MapEntry(key.toString(), mapValue),
      );
    }
    return null;
  }

  static bool? _toBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
    return null;
  }
}
