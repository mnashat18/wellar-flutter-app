import '../models/scan_result.dart';

class ScanResultMetricDisplay {
  final String label;
  final String value;

  const ScanResultMetricDisplay({required this.label, required this.value});
}

class ScanAssessmentDetail {
  final String label;
  final String value;

  const ScanAssessmentDetail({required this.label, required this.value});
}

String displayRiskLevelLabel(String? riskLevel) {
  final normalized = riskLevel?.trim().toLowerCase() ?? '';
  switch (normalized) {
    case 'stable':
      return 'Stable';
    case 'low_focus':
    case 'low focus':
      return 'Low focus';
    case 'elevated_fatigue':
    case 'elevated fatigue':
      return 'Elevated fatigue';
    case 'high_risk':
    case 'high risk':
      return 'High risk';
    case 'moderate':
      return 'Moderate';
    case 'high':
      return 'High risk';
    case 'critical':
      return 'Critical';
    case '':
      return 'Review required';
    default:
      return 'Review required';
  }
}

String? formatPercentValue(double? value) {
  if (value == null) return null;
  final percent = _normalizePercent(value);
  return '$percent%';
}

String? confidenceQualityNote(double? confidence) {
  final percent = _normalizePercentOrNull(confidence);
  if (percent == null) return null;
  if (percent < 45) {
    return 'Confidence is low, so treat this result as guidance rather than certainty.';
  }
  if (percent < 70) {
    return 'Confidence is moderate, so use this result with normal judgment.';
  }
  return null;
}

String? recommendedNextStepText(ScanResult result) {
  final action = result.suggestedAction?.trim() ?? '';
  if (action.isEmpty) return null;
  return action;
}

List<String> influenceBullets(ScanResult result) {
  final bullets = <String>[];
  final explanation = result.explanation?.trim();
  if (explanation != null && explanation.isNotEmpty) {
    bullets.add(explanation);
  }

  final camera = formatPercentValue(result.cameraConfidence);
  if (camera != null) {
    bullets.add('Camera confidence: $camera');
  }

  final voice = formatPercentValue(result.voiceConfidence);
  if (voice != null) {
    bullets.add('Voice confidence: $voice');
  }

  final taskPerformance = _taskPerformancePercent(result);
  if (taskPerformance != null) {
    bullets.add('Reaction task: ${formatPercentValue(taskPerformance)}');
  }

  final drift = formatPercentValue(result.confidenceDrift);
  if (drift != null) {
    bullets.add('Confidence drift: $drift');
  }

  return bullets;
}

List<ScanResultMetricDisplay> visibleSignalMetrics(ScanResult result) {
  final metrics = <ScanResultMetricDisplay>[];
  final camera = formatPercentValue(result.cameraConfidence);
  if (camera != null) {
    metrics.add(
      ScanResultMetricDisplay(label: 'Camera confidence', value: camera),
    );
  }
  final voice = formatPercentValue(result.voiceConfidence);
  if (voice != null) {
    metrics.add(
      ScanResultMetricDisplay(label: 'Voice confidence', value: voice),
    );
  }
  final taskPerformance = _taskPerformancePercent(result);
  if (taskPerformance != null) {
    metrics.add(
      ScanResultMetricDisplay(
        label: _taskMetricLabel(result),
        value: formatPercentValue(taskPerformance)!,
      ),
    );
  }
  final drift = formatPercentValue(result.confidenceDrift);
  if (drift != null) {
    metrics.add(
      ScanResultMetricDisplay(label: 'Confidence drift', value: drift),
    );
  }
  return metrics;
}

bool hasValidatedTaskSignal(ScanResult result) {
  return _taskPerformancePercent(result) != null;
}

List<ScanAssessmentDetail> assessmentDetailsForDisplay(ScanResult result) {
  final details = <ScanAssessmentDetail>[];
  final model = result.aiModelVersion?.trim();
  if (model != null && model.isNotEmpty) {
    details.add(ScanAssessmentDetail(label: 'Assessment model', value: model));
  }

  if (result.baselineUsed != null) {
    details.add(
      ScanAssessmentDetail(
        label: 'Baseline comparison',
        value: result.baselineUsed == true
            ? 'Used'
            : 'Not used for this assessment',
      ),
    );
  }

  return details;
}

bool hasAssessmentDetails(ScanResult result) {
  return assessmentDetailsForDisplay(result).isNotEmpty;
}

String _taskMetricLabel(ScanResult result) {
  if (result.taskPerformanceScore != null) {
    return 'Task performance';
  }
  return 'Reaction task';
}

double? _taskPerformancePercent(ScanResult result) {
  final task = result.taskPerformanceScore;
  if (task != null) return task;
  final reactionScore = result.reactionMetrics?['score'];
  if (reactionScore is num) return reactionScore.toDouble();
  return double.tryParse(reactionScore?.toString() ?? '');
}

int _normalizePercent(double value) {
  if (value <= 1) return (value * 100).round();
  return value.round();
}

int? _normalizePercentOrNull(double? value) {
  if (value == null) return null;
  return _normalizePercent(value);
}
