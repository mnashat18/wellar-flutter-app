import 'package:flutter_test/flutter_test.dart';
import 'package:waller_app/models/scan_result.dart';

void main() {
  group('ScanResult.fromJson', () {
    test('ai_model_version remains nullable', () {
      final result = ScanResult.fromJson(<String, dynamic>{
        'id': 'result-1',
        'scan_id': 'scan-1',
      });

      expect(result.aiModelVersion, isNull);
    });

    test('baseline_used remains nullable when missing', () {
      final result = ScanResult.fromJson(<String, dynamic>{
        'id': 'result-1',
        'scan_id': 'scan-1',
      });

      expect(result.baselineUsed, isNull);
    });

    test('missing values are never coerced to false', () {
      final result = ScanResult.fromJson(<String, dynamic>{
        'id': 'result-1',
        'scan_id': 'scan-1',
        'baseline_used': null,
      });

      expect(result.baselineUsed, isNull);
    });

    test('projection fields parse when present', () {
      final result = ScanResult.fromJson(<String, dynamic>{
        'id': 'result-1',
        'scan_id': 'scan-1',
        'ai_model_version': 'v2.4.1',
        'baseline_used': true,
        'face_metrics': <String, dynamic>{'blink_rate': 0.2},
        'voice_metrics': <String, dynamic>{'clarity': 0.7},
        'reaction_metrics': <String, dynamic>{'score': 0.82},
      });

      expect(result.aiModelVersion, 'v2.4.1');
      expect(result.baselineUsed, isTrue);
      expect(result.faceMetrics?['blink_rate'], 0.2);
      expect(result.voiceMetrics?['clarity'], 0.7);
      expect(result.reactionMetrics?['score'], 0.82);
    });
  });
}
