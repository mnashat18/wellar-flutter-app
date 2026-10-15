import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waller_app/models/wellar_v2_result.dart';
import 'package:waller_app/services/wellar_v2_client.dart';

void main() {
  final enabled = Platform.environment['WELLAR_V2_LIVE_TEST'] == '1';

  test(
    'real local V2 accepts synthetic media and returns insufficient evidence',
    () async {
      final baseUrl = Platform.environment['WELLAR_V2_LIVE_BASE_URL'];
      final token = Platform.environment['WELLAR_V2_LIVE_TOKEN'];
      final videoPath = Platform.environment['WELLAR_V2_LIVE_VIDEO'];
      final audioPath = Platform.environment['WELLAR_V2_LIVE_AUDIO'];
      expect(baseUrl, isNotNull);
      expect(token, isNotNull);
      expect(videoPath, isNotNull);
      expect(audioPath, isNotNull);

      final dio = Dio();
      final client = WellarV2Client(
        dio: dio,
        baseUrl: baseUrl!,
        bearerToken: token!,
      );
      final video = await File(videoPath!).readAsBytes();
      final audio = await File(audioPath!).readAsBytes();
      final refs = <String>[];
      final uploadWatch = Stopwatch()..start();
      String? scanId;
      var terminal = false;
      try {
        refs.add(await client.uploadVideo(video));
        refs.add(await client.uploadAudio(audio));
        uploadWatch.stop();

        final submitWatch = Stopwatch()..start();
        final idempotencyKey = WellarV2Client.newIdempotencyKey();
        scanId = await client.submitScan(
          mediaRefs: List.unmodifiable(refs),
          mediaProcessingConsent: true,
          researchUseConsent: true,
          idempotencyKey: idempotencyKey,
        );
        submitWatch.stop();
        final replayedScanId = await client.submitScan(
          mediaRefs: List.unmodifiable(refs),
          mediaProcessingConsent: true,
          researchUseConsent: true,
          idempotencyKey: idempotencyKey,
        );
        expect(replayedScanId, scanId);

        await expectLater(
          client.fetchResult(scanId),
          throwsA(
            isA<WellarV2ApiException>()
                .having((error) => error.code, 'code', 'result_unavailable')
                .having((error) => error.retryable, 'retryable', isTrue),
          ),
        );

        final processingWatch = Stopwatch()..start();
        var status = 'queued';
        for (
          var i = 0;
          i < 120 && status != 'completed' && status != 'failed';
          i++
        ) {
          status = await client.fetchStatus(scanId);
          if (status != 'completed' && status != 'failed') {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }
        processingWatch.stop();
        terminal = status == 'completed' || status == 'failed';
        expect(status, 'completed');

        final resultWatch = Stopwatch()..start();
        final WellarV2Result result = await client.fetchResult(scanId);
        resultWatch.stop();
        expect(result.status, 'insufficient_evidence');
        expect(result.modelVersion, isNull);
        expect(result.targets.values, isNotEmpty);
        expect(
          result.targets.values.every((target) => target.value == null),
          isTrue,
        );

        // Report only durations and outcome; never log the credential, refs, or media.
        // ignore: avoid_print
        print(
          'LOCAL_V2_TIMINGS upload_ms=${uploadWatch.elapsedMilliseconds} '
          'submit_ms=${submitWatch.elapsedMilliseconds} '
          'processing_ms=${processingWatch.elapsedMilliseconds} '
          'result_ms=${resultWatch.elapsedMilliseconds} outcome=${result.status}',
        );
      } finally {
        if (scanId == null || terminal) {
          for (final ref in refs.reversed) {
            await client.deleteMedia(ref);
          }
        }
        dio.close(force: true);
      }
    },
    skip: enabled
        ? false
        : 'Set WELLAR_V2_LIVE_TEST=1 for disposable local V2 only.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
