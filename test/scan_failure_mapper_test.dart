import 'package:flutter_test/flutter_test.dart';
import 'package:waller_app/utils/scan_failure_mapper.dart';

void main() {
  test('video_blurry maps to clear retry guidance', () {
    expect(scanFailureTitle('video_blurry'), 'Video is too blurry');
    expect(
      scanFailureMessage('video_blurry'),
      'Your video was not clear enough to analyze. Please retake the scan in better lighting and keep your phone steady.',
    );
    expect(scanFailureActionLabel('video_blurry'), 'Retake scan');
  });

  test('unknown failure reason falls back to default copy', () {
    expect(scanFailureTitle('unexpected_backend_code'), 'Scan failed');
    expect(
      scanFailureMessage('unexpected_backend_code'),
      'Something went wrong while processing your scan. Please try again.',
    );
    expect(scanFailureActionLabel('unexpected_backend_code'), 'Try again');
  });

  test('writeback_failed maps to save error copy', () {
    expect(scanFailureTitle('writeback_failed'), 'Result could not be saved');
    expect(
      scanFailureMessage('writeback_failed'),
      'Your scan was analyzed, but the result could not be saved. Please try again.',
    );
    expect(scanFailureActionLabel('writeback_failed'), 'Try again');
  });
}
