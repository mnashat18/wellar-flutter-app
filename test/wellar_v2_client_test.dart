import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waller_app/models/wellar_v2_result.dart';
import 'package:waller_app/services/wellar_v2_client.dart';

class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  FutureOr<ResponseBody> Function(RequestOptions request)? respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return await respond?.call(options) ??
        ResponseBody.fromString(
          '{}',
          500,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
  }

  @override
  void close({bool force = false}) {}
}

Uint8List _mp4() => Uint8List.fromList([
  0,
  0,
  0,
  16,
  102,
  116,
  121,
  112,
  105,
  115,
  111,
  109,
  0,
  0,
  0,
  0,
]);

Uint8List _jpeg() => Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2]);

Uint8List _wav() {
  final bytes = Uint8List(46);
  final data = ByteData.sublistView(bytes);
  void text(int offset, String value) {
    bytes.setRange(offset, offset + value.length, value.codeUnits);
  }

  text(0, 'RIFF');
  data.setUint32(4, 38, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 44100, Endian.little);
  data.setUint32(28, 88200, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, 2, Endian.little);
  return bytes;
}

WellarV2Client _client(_FakeAdapter adapter, {String token = 'synthetic'}) =>
    WellarV2Client(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'http://127.0.0.1:8000',
      bearerToken: token,
    );

ResponseBody _json(Map<String, dynamic> value, int status) =>
    ResponseBody.fromString(
      jsonEncode(value),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

void main() {
  group('WellarV2Client', () {
    test('V2 feature flag is disabled by default', () {
      expect(WellarV2Feature.enabledFor(null), isFalse);
    });

    test(
      'uploads raw JPEG, MP4, and PCM WAV bytes with matching content types',
      () async {
        final adapter = _FakeAdapter()
          ..respond = (_) =>
              _json({'media_ref': 'media://tenant/0123456789abcdef'}, 201);
        final client = _client(adapter);
        await client.uploadVideo(_mp4());
        await client.uploadAudio(_wav());
        await client.uploadImage(_jpeg());

        expect(adapter.requests, hasLength(3));
        expect(adapter.requests[0].data, isA<Uint8List>());
        expect(adapter.requests[0].headers['Content-Type'], 'video/mp4');
        expect(adapter.requests[1].headers['Content-Type'], 'audio/wav');
        expect(adapter.requests[2].data, isA<Uint8List>());
        expect(adapter.requests[2].headers['Content-Type'], 'image/jpeg');
        expect(
          adapter.requests.every((r) => r.path.contains('/api/v1/media/')),
          isTrue,
        );
      },
    );

    test(
      'rejects unsupported or mislabeled media before network access',
      () async {
        final adapter = _FakeAdapter();
        final client = _client(adapter);
        await expectLater(
          client.uploadAudio(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<WellarV2ApiException>()),
        );
        await expectLater(
          client.uploadVideo(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<WellarV2ApiException>()),
        );
        expect(adapter.requests, isEmpty);
      },
    );

    test('missing V2 credential fails before sending any request', () async {
      final adapter = _FakeAdapter();
      await expectLater(
        _client(adapter, token: '').uploadVideo(_mp4()),
        throwsA(
          isA<WellarV2ApiException>().having(
            (e) => e.code,
            'error code',
            'v2_auth_missing',
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
    });

    test('submission uses V2 schema and required idempotency key', () async {
      final adapter = _FakeAdapter()
        ..respond = (_) =>
            _json({'scan_id': 'scan-1', 'status': 'queued'}, 202);
      await _client(adapter).submitScan(
        mediaRefs: const ['media://synthetic/0123456789abcdef'],
        mediaProcessingConsent: true,
        researchUseConsent: false,
        idempotencyKey: 'stable-key-for-safe-retry',
      );
      final request = adapter.requests.single;
      final body = request.data as Map<String, dynamic>;
      expect(request.headers['Idempotency-Key'], 'stable-key-for-safe-retry');
      expect(body['schema_version'], '1.0');
      expect(body['reaction_task'], isNull);
      expect(body['consent'], {
        'media_processing': true,
        'research_use': false,
      });
      expect(
        body.keys,
        containsAll([
          'schema_version',
          'media_refs',
          'reaction_task',
          'consent',
        ]),
      );
      expect(body.keys, isNot(contains('tenant_id')));
      expect(body.keys, isNot(contains('subject_id')));
    });

    test(
      'retries ambiguous server failure with the same idempotency key',
      () async {
        final adapter = _FakeAdapter();
        adapter.respond = (request) => adapter.requests.length == 1
            ? _json({
                'error': {'code': 'temporarily_unavailable'},
              }, 503)
            : _json({'scan_id': 'scan-replayed', 'status': 'queued'}, 202);
        final scanId = await _client(adapter).submitScan(
          mediaRefs: const [],
          mediaProcessingConsent: true,
          researchUseConsent: false,
          idempotencyKey: 'same-key-on-both-attempts',
        );
        expect(scanId, 'scan-replayed');
        expect(adapter.requests, hasLength(2));
        expect(
          adapter.requests.map((r) => r.headers['Idempotency-Key']).toSet(),
          {'same-key-on-both-attempts'},
        );
      },
    );

    test(
      'retries a transport timeout with the same idempotency key only',
      () async {
        final adapter = _FakeAdapter()
          ..respond = (request) {
            throw DioException(
              requestOptions: request,
              type: DioExceptionType.connectionTimeout,
            );
          };
        await expectLater(
          _client(adapter).submitScan(
            mediaRefs: const [],
            mediaProcessingConsent: true,
            researchUseConsent: false,
            idempotencyKey: 'timeout-safe-replay',
          ),
          throwsA(
            isA<WellarV2ApiException>().having(
              (error) => error.retryable,
              'retryable',
              isTrue,
            ),
          ),
        );
        expect(adapter.requests, hasLength(2));
        expect(
          adapter.requests
              .map((request) => request.headers['Idempotency-Key'])
              .toSet(),
          {'timeout-safe-replay'},
        );
      },
    );

    test('cancelled requests do not reach the adapter or retry', () async {
      final adapter = _FakeAdapter();
      final cancel = CancelToken()..cancel('test cancellation');
      await expectLater(
        _client(adapter).uploadVideo(_mp4(), cancelToken: cancel),
        throwsA(isA<WellarV2ApiException>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test(
      'does not retry an auth rejection and sanitizes response details',
      () async {
        final adapter = _FakeAdapter()
          ..respond = (_) => _json({'detail': 'secret backend detail'}, 401);
        await expectLater(
          _client(adapter).submitScan(
            mediaRefs: const [],
            mediaProcessingConsent: true,
            researchUseConsent: false,
            idempotencyKey: 'auth-failure',
          ),
          throwsA(
            isA<WellarV2ApiException>()
                .having((e) => e.code, 'code', 'v2_auth_rejected')
                .having(
                  (e) => e.message.contains('secret'),
                  'redacted',
                  isFalse,
                ),
          ),
        );
        expect(adapter.requests, hasLength(1));
      },
    );

    test('refreshes the Directus token once after V2 returns 401', () async {
      final adapter = _FakeAdapter();
      adapter.respond = (request) =>
          request.headers['Authorization'] == 'Bearer expired-token'
          ? _json({
              'detail': {'code': 'unauthorized'},
            }, 401)
          : _json({'media_ref': 'media://tenant/0123456789abcdef'}, 201);
      var token = 'expired-token';
      var refreshCalls = 0;
      final client = WellarV2Client(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrl: 'https://v2.example.test',
        tokenProvider: () async => token,
        refreshToken: () async {
          refreshCalls++;
          token = 'refreshed-token';
          return true;
        },
      );

      await client.uploadVideo(_mp4());

      expect(refreshCalls, 1);
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.map((request) => request.headers['Authorization']),
        ['Bearer expired-token', 'Bearer refreshed-token'],
      );
    });

    test(
      'handles non-object HTTP error bodies without leaking details',
      () async {
        final adapter = _FakeAdapter()
          ..respond = (_) => ResponseBody.fromString(
            jsonEncode('private backend detail'),
            415,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        await expectLater(
          _client(adapter).submitScan(
            mediaRefs: const [],
            mediaProcessingConsent: true,
            researchUseConsent: false,
            idempotencyKey: 'media-rejection',
          ),
          throwsA(
            isA<WellarV2ApiException>().having(
              (error) => error.code,
              'safe fallback code',
              'v2_request_failed',
            ),
          ),
        );
        expect(adapter.requests, hasLength(1));
      },
    );

    test('deletes uploaded V2 media by opaque reference', () async {
      final adapter = _FakeAdapter()
        ..respond = (_) => ResponseBody.fromBytes(
          const [],
          204,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      await _client(adapter).deleteMedia('media://tenant/0123456789abcdef');
      expect(adapter.requests.single.method, 'DELETE');
      expect(adapter.requests.single.path, endsWith('/api/v1/media'));
      expect(
        adapter.requests.single.queryParameters['media_ref'],
        'media://tenant/0123456789abcdef',
      );
    });

    test(
      'returns V2 status and preserves insufficient evidence nullable targets',
      () async {
        final adapter = _FakeAdapter()
          ..respond = (request) {
            if (request.path.endsWith('/result')) {
              return _json({
                'schema_version': '2.0',
                'scan_id': 'scan-2',
                'status': 'insufficient_evidence',
                'model_version': null,
                'model_invocation_status': 'not_invoked_no_validated_model',
                'targets': {
                  'reference_sleepiness': {
                    'status': 'unavailable',
                    'value': null,
                    'reason': 'model_unavailable',
                  },
                },
                'quality': {},
                'features': {},
                'message': 'No validated model is configured.',
              }, 200);
            }
            return _json({'scan_id': 'scan-2', 'status': 'completed'}, 200);
          };
        final client = _client(adapter);
        expect(await client.fetchStatus('scan-2'), 'completed');
        final result = await client.fetchResult('scan-2');
        expect(result, isA<WellarV2Result>());
        expect(result.status, 'insufficient_evidence');
        expect(result.targets['reference_sleepiness']?.value, isNull);
        expect(adapter.requests, hasLength(2));
      },
    );

    test('stable idempotency key factory yields non-empty opaque values', () {
      final first = WellarV2Client.newIdempotencyKey();
      expect(first, hasLength(64));
      expect(first, matches(RegExp(r'^[a-f0-9]{64}$')));
    });
  });
}
