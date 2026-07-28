import 'package:flutter_test/flutter_test.dart';
import 'package:waller_app/utils/scan_result_polling_policy.dart';

void main() {
  group('ScanResultPollingPolicy', () {
    const policy = ScanResultPollingPolicy();

    test('maximum processing window is 90 seconds', () {
      expect(
        ScanResultPollingPolicy.maxProcessingWindow,
        const Duration(seconds: 90),
      );
    });

    test('progressive polling intervals are correct', () {
      expect(
        policy.nextDelay(const Duration(seconds: 0)),
        ScanResultPollingPolicy.earlyPollInterval,
      );
      expect(
        policy.nextDelay(const Duration(seconds: 7)),
        ScanResultPollingPolicy.earlyPollInterval,
      );
      expect(
        policy.nextDelay(const Duration(seconds: 8)),
        ScanResultPollingPolicy.midPollInterval,
      );
      expect(
        policy.nextDelay(const Duration(seconds: 29)),
        ScanResultPollingPolicy.midPollInterval,
      );
      expect(
        policy.nextDelay(const Duration(seconds: 30)),
        ScanResultPollingPolicy.latePollInterval,
      );
      expect(
        policy.nextDelay(const Duration(seconds: 60)),
        ScanResultPollingPolicy.latePollInterval,
      );
    });

    test('policy stops after the bounded window', () {
      expect(
        policy.shouldContinue(const Duration(seconds: 89)),
        isTrue,
      );
      expect(
        policy.shouldContinue(const Duration(seconds: 90)),
        isFalse,
      );
      expect(
        policy.shouldContinue(const Duration(seconds: 91)),
        isFalse,
      );
    });
  });
}
