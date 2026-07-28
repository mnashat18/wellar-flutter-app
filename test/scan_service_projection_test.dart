import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waller_app/services/directus_client.dart';
import 'package:waller_app/services/organization_service.dart';
import 'package:waller_app/services/scan_service.dart';
import 'package:waller_app/state/session.dart';

void main() {
  group('ScanService projection', () {
    final client = DirectusClient.instance.client;

    setUp(() {
      Session.instance
        ..accessToken = 'test-token'
        ..userId = 'user-1'
        ..userEmail = 'user@example.com'
        ..roleName = 'owner';
      OrganizationService.instance.clearProfileCache();
    });

    tearDown(() {
      Session.instance
        ..accessToken = null
        ..refreshToken = null
        ..userId = null
        ..userEmail = null
        ..userName = null
        ..roleName = null
        ..pendingInviteToken = null;
      OrganizationService.instance.clearProfileCache();
    });

    test('scan result projection includes assessment and metrics fields', () async {
      String? requestedFields;
      late InterceptorsWrapper interceptor;
      interceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/users/me') {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  'data': <String, dynamic>{
                    'id': 'user-1',
                    'email': 'user@example.com',
                    'role': <String, dynamic>{'id': 'role-1', 'name': 'owner'},
                  },
                },
              ),
            );
            return;
          }

          if (options.path == '/items/business_profile_members') {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: const <String, dynamic>{'data': <dynamic>[]},
              ),
            );
            return;
          }

          if (options.path == '/fields/scan_results') {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  'data': <Map<String, dynamic>>[
                    <String, dynamic>{'field': 'id'},
                    <String, dynamic>{'field': 'scan_id'},
                    <String, dynamic>{'field': 'date_created'},
                    <String, dynamic>{'field': 'risk_level'},
                    <String, dynamic>{'field': 'readiness_score'},
                    <String, dynamic>{'field': 'confidence'},
                    <String, dynamic>{'field': 'camera_confidence'},
                    <String, dynamic>{'field': 'voice_confidence'},
                    <String, dynamic>{'field': 'task_performance_score'},
                    <String, dynamic>{'field': 'confidence_drift'},
                    <String, dynamic>{'field': 'explanation'},
                    <String, dynamic>{'field': 'suggested_action'},
                    <String, dynamic>{'field': 'ai_model_version'},
                    <String, dynamic>{'field': 'baseline_used'},
                    <String, dynamic>{'field': 'face_metrics'},
                    <String, dynamic>{'field': 'voice_metrics'},
                    <String, dynamic>{'field': 'reaction_metrics'},
                  ],
                },
              ),
            );
            return;
          }

          if (options.path == '/items/scan_results') {
            requestedFields = options.queryParameters['fields']?.toString();
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  'data': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'id': 'result-1',
                      'scan_id': 'scan-1',
                      'risk_level': 'stable',
                      'ai_model_version': 'v2.4.1',
                      'baseline_used': true,
                      'face_metrics': <String, dynamic>{'blink_rate': 0.2},
                      'voice_metrics': <String, dynamic>{'clarity': 0.7},
                      'reaction_metrics': <String, dynamic>{'score': 0.82},
                    },
                  ],
                },
              ),
            );
            return;
          }

          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 500,
                data: const <String, dynamic>{'error': 'unexpected request'},
              ),
            ),
          );
        },
      );

      client.interceptors.add(interceptor);
      addTearDown(() => client.interceptors.remove(interceptor));

      final lookup = await ScanService.instance.fetchScanResultLookupForScan(
        'scan-1',
      );

      expect(requestedFields, isNotNull);
      expect(requestedFields, contains('ai_model_version'));
      expect(requestedFields, contains('baseline_used'));
      expect(requestedFields, contains('face_metrics'));
      expect(requestedFields, contains('voice_metrics'));
      expect(requestedFields, contains('reaction_metrics'));

      final result = lookup.result;
      expect(result, isNotNull);
      expect(result!.aiModelVersion, 'v2.4.1');
      expect(result.baselineUsed, isTrue);
      expect(result.faceMetrics?['blink_rate'], 0.2);
      expect(result.voiceMetrics?['clarity'], 0.7);
      expect(result.reactionMetrics?['score'], 0.82);
    });
  });
}
