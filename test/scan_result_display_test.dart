import 'package:flutter_test/flutter_test.dart';
import 'package:waller_app/models/scan_result.dart';
import 'package:waller_app/utils/scan_result_display.dart';

void main() {
  ScanResult buildResult({
    String? riskLevel,
    String? aiModelVersion,
    bool? baselineUsed,
    double? cameraConfidence,
    double? voiceConfidence,
    double? taskPerformanceScore,
    double? confidenceDrift,
    Map<String, dynamic>? reactionMetrics,
  }) {
    return ScanResult(
      id: 'result-1',
      scanId: 'scan-1',
      dateCreated: DateTime.utc(2026, 7, 1),
      riskLevel: riskLevel,
      overallState: riskLevel ?? 'Review needed',
      aiModelVersion: aiModelVersion,
      baselineUsed: baselineUsed,
      cameraConfidence: cameraConfidence,
      voiceConfidence: voiceConfidence,
      taskPerformanceScore: taskPerformanceScore,
      confidenceDrift: confidenceDrift,
      reactionMetrics: reactionMetrics,
    );
  }

  group('displayRiskLevelLabel', () {
    test('maps safe labels', () {
      expect(displayRiskLevelLabel('stable'), 'Stable');
      expect(displayRiskLevelLabel('low_focus'), 'Low focus');
      expect(displayRiskLevelLabel('elevated_fatigue'), 'Elevated fatigue');
      expect(displayRiskLevelLabel('high_risk'), 'High risk');
      expect(displayRiskLevelLabel('high'), 'High risk');
    });
  });

  group('assessmentDetailsForDisplay', () {
    test('missing optional fields do not create fake values', () {
      final details = assessmentDetailsForDisplay(buildResult());
      expect(details, isEmpty);
    });

    test('baseline true shows Used', () {
      final details = assessmentDetailsForDisplay(
        buildResult(baselineUsed: true),
      );
      expect(details.length, 1);
      expect(details.single.label, 'Baseline comparison');
      expect(details.single.value, 'Used');
    });

    test('baseline false shows Not used for this assessment', () {
      final details = assessmentDetailsForDisplay(
        buildResult(baselineUsed: false),
      );
      expect(details.length, 1);
      expect(details.single.value, 'Not used for this assessment');
    });

    test('missing baseline hides that row', () {
      final details = assessmentDetailsForDisplay(
        buildResult(aiModelVersion: 'v2.3.0'),
      );
      expect(details.length, 1);
      expect(details.single.label, 'Assessment model');
    });
  });

  group('visibleSignalMetrics', () {
    test('optional metrics appear only when backend values exist', () {
      final metrics = visibleSignalMetrics(
        buildResult(
          cameraConfidence: 0.81,
          reactionMetrics: <String, dynamic>{'score': 0.67},
        ),
      );

      expect(metrics.map((metric) => metric.label), <String>[
        'Camera confidence',
        'Reaction task',
      ]);
      expect(metrics.map((metric) => metric.value), <String>[
        '81%',
        '67%',
      ]);
    });

    test('missing optional metrics stay hidden', () {
      final metrics = visibleSignalMetrics(buildResult());
      expect(metrics, isEmpty);
    });
  });
}
