import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:waller_app/models/plan.dart';
import 'package:waller_app/services/auth_service.dart';
import 'package:waller_app/screens/business_profile_wizard_screen.dart';
import 'package:waller_app/screens/profile_screen.dart';
import 'package:waller_app/screens/role_based_shells.dart';
import 'package:waller_app/screens/workspace_access_screen.dart';
import 'package:waller_app/services/directus_client.dart';
import 'package:waller_app/services/organization_service.dart';
import 'package:waller_app/state/app_language_state.dart';
import 'package:waller_app/state/app_providers.dart';
import 'package:waller_app/state/session.dart';

Future<void> _prepareSession() async {
  FlutterSecureStorage.setMockInitialValues({});
  if (Firebase.apps.isEmpty) {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  }
  await Session.instance.clear();
  OrganizationService.instance.clearProfileCache();
  OrganizationService.instance.clearActiveWorkspaceContext();
}

Map<String, dynamic> _userMeResponse({
  required String userId,
  required String email,
  required String roleName,
  String firstName = 'Ada',
  String lastName = 'Lovelace',
}) {
  return <String, dynamic>{
    'data': <String, dynamic>{
      'id': userId,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'role': <String, dynamic>{
        'id': 'role-$roleName',
        'name': roleName,
      },
    },
  };
}

Map<String, dynamic> _workspaceContextResponse({
  required String activeMembershipId,
  required List<Map<String, dynamic>> memberships,
  List<Map<String, dynamic>> invitations = const [],
}) {
  Map<String, dynamic>? active;
  for (final membership in memberships) {
    if (membership['id']?.toString() == activeMembershipId) {
      active = <String, dynamic>{
        'workspace': membership['workspace'],
        'membership': <String, dynamic>{
          'id': membership['id'],
          'status': membership['status'],
          'memberRole': membership['memberRole'],
        },
        if (membership['department'] != null)
          'department': membership['department'],
      };
      break;
    }
  }
  return <String, dynamic>{
    'data': <String, dynamic>{
      'active': active,
      'memberships': memberships,
      'invitations': invitations,
    },
  };
}

Map<String, dynamic> _membership({
  required String id,
  required String memberRole,
  required String companyId,
  required String companyName,
  String status = 'active',
  String? departmentId,
  String? departmentName,
  bool isCurrent = false,
}) {
  return <String, dynamic>{
    'id': id,
    'memberRole': memberRole,
    'status': status,
    'workspace': <String, dynamic>{
      'id': companyId,
      'companyName': companyName,
      'isActive': true,
      'planCode': 'business',
      'billingStatus': 'active',
    },
    if (departmentId != null || departmentName != null)
      'department': <String, dynamic>{
        if (departmentId != null) 'id': departmentId,
        if (departmentName != null) 'name': departmentName,
      },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Organization switching and workspace bootstrap', () {
    final client = DirectusClient.instance.client;

    late InterceptorsWrapper interceptor;

    tearDown(() async {
      client.interceptors.remove(interceptor);
      await Session.instance.clear();
      OrganizationService.instance.clearProfileCache();
      OrganizationService.instance.clearActiveWorkspaceContext();
    });

    test('successful organization switch refreshes token and replaces context', () async {
      await _prepareSession();
      await Session.instance.setAuth(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        userId: 'user-1',
        userEmail: 'owner@example.com',
        roleName: 'owner',
      );

      final requests = <String>[];
      interceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add('${options.method} ${options.path}');
          switch (options.path) {
            case '/wellar/workspaces/switch':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{'data': <String, dynamic>{}},
                ),
              );
              return;
            case '/auth/refresh':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{
                    'data': <String, dynamic>{
                      'access_token': 'refreshed-access',
                      'refresh_token': 'refreshed-refresh',
                    },
                  },
                ),
              );
              return;
            case '/users/me':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _userMeResponse(
                    userId: 'user-1',
                    email: 'owner@example.com',
                    roleName: 'owner',
                  ),
                ),
              );
              return;
            case '/wellar/workspaces/context':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _workspaceContextResponse(
                    activeMembershipId: 'membership-2',
                    memberships: [
                      _membership(
                        id: 'membership-1',
                        memberRole: 'employee',
                        companyId: 'company-1',
                        companyName: 'Company One',
                      ),
                      _membership(
                        id: 'membership-2',
                        memberRole: 'owner',
                        companyId: 'company-2',
                        companyName: 'Company Two',
                        isCurrent: true,
                      ),
                    ],
                  ),
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

      final context = await OrganizationService.instance.syncWorkspaceSession(
        membershipId: 'membership-2',
        trigger: 'test_switch',
      );

      expect(
        requests,
        equals(const [
          'POST /wellar/workspaces/switch',
          'POST /auth/refresh',
          'GET /users/me',
          'GET /wellar/workspaces/context',
        ]),
      );
      expect(context.membershipId, 'membership-2');
      expect(context.businessProfileId, 'company-2');
      expect(context.businessProfileName, 'Company Two');
      expect(Session.instance.accessToken, 'refreshed-access');
      expect(Session.instance.refreshToken, 'refreshed-refresh');
      expect(
        await OrganizationService.instance.fetchActiveWorkspaceContext(),
        isNotNull,
      );
    });

    test('stale switch result cannot overwrite a newer selected organization', () async {
      await _prepareSession();
      await Session.instance.setAuth(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        userId: 'user-1',
        userEmail: 'owner@example.com',
        roleName: 'owner',
      );

      final requests = <String>[];
      final firstContextGate = Completer<void>();
      var contextRequestCount = 0;

      interceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add('${options.method} ${options.path}');
          switch (options.path) {
            case '/wellar/workspaces/switch':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{'data': <String, dynamic>{}},
                ),
              );
              return;
            case '/auth/refresh':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{
                    'data': <String, dynamic>{
                      'access_token': 'refreshed-access',
                      'refresh_token': 'refreshed-refresh',
                    },
                  },
                ),
              );
              return;
            case '/users/me':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _userMeResponse(
                    userId: 'user-1',
                    email: 'owner@example.com',
                    roleName: 'owner',
                  ),
                ),
              );
              return;
            case '/wellar/workspaces/context':
              contextRequestCount++;
              final requestIndex = contextRequestCount;
              if (requestIndex == 1) {
                await firstContextGate.future;
              }
              final membershipId =
                  requestIndex == 1 ? 'membership-1' : 'membership-2';
              final companyName =
                  requestIndex == 1 ? 'Company One' : 'Company Two';
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _workspaceContextResponse(
                    activeMembershipId: membershipId,
                    memberships: [
                      _membership(
                        id: 'membership-1',
                        memberRole: 'employee',
                        companyId: 'company-1',
                        companyName: 'Company One',
                        isCurrent: membershipId == 'membership-1',
                      ),
                      _membership(
                        id: 'membership-2',
                        memberRole: 'owner',
                        companyId: 'company-2',
                        companyName: companyName,
                        isCurrent: membershipId == 'membership-2',
                      ),
                    ],
                  ),
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

      final first = OrganizationService.instance.syncWorkspaceSession(
        membershipId: 'membership-1',
        trigger: 'bootstrap',
      );
      await Future<void>.delayed(Duration.zero);
      final second = OrganizationService.instance.syncWorkspaceSession(
        membershipId: 'membership-2',
        trigger: 'user_switch',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      firstContextGate.complete();

      final secondContext = await second;
      final firstContext = await first;
      final cached = await OrganizationService.instance
          .fetchActiveWorkspaceContext();

      expect(secondContext.membershipId, 'membership-2');
      expect(firstContext.membershipId, 'membership-1');
      expect(cached?.membershipId, 'membership-2');
    });

    test('failed switch leaves prior context intact', () async {
      await _prepareSession();
      await Session.instance.setAuth(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        userId: 'user-1',
        userEmail: 'owner@example.com',
        roleName: 'owner',
      );

      final existing = ActiveWorkspaceContext(
        currentUserId: 'user-1',
        currentUserEmail: 'owner@example.com',
        currentUserFirstName: 'Ada',
        currentUserLastName: 'Lovelace',
        directusRoleId: 'role-owner',
        directusRoleName: 'owner',
        membershipUserId: 'user-1',
        businessProfileId: 'company-old',
        businessProfileName: 'Existing Company',
        businessProfileStatus: 'true',
        businessPlanCode: 'business',
        businessBillingStatus: 'active',
        membershipId: 'membership-old',
        memberRole: 'owner',
        membershipRole: 'owner',
        finalEffectiveRole: 'owner',
        membershipStatus: 'active',
        departmentId: null,
        departmentName: null,
        scopeLabel: 'OWNER',
      );
      OrganizationService.instance.applyActiveWorkspaceContext(existing);

      interceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.path == '/wellar/workspaces/switch') {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 403,
                  data: const <String, dynamic>{
                    'message': 'Forbidden',
                  },
                ),
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

      expect(
        () => OrganizationService.instance.syncWorkspaceSession(
          membershipId: 'membership-new',
          trigger: 'user_switch',
        ),
        throwsA(isA<OrganizationServiceException>()),
      );
      final cached = await OrganizationService.instance
          .fetchActiveWorkspaceContext();
      expect(cached?.membershipId, 'membership-old');
      expect(cached?.businessProfileId, 'company-old');
    });

    test('identical sync requests coalesce within one authenticated session', () async {
      await _prepareSession();
      await Session.instance.setAuth(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        userId: 'user-1',
        userEmail: 'owner@example.com',
        roleName: 'owner',
      );

      final switchGate = Completer<void>();
      var switchCount = 0;

      interceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          switch (options.path) {
            case '/wellar/workspaces/switch':
              switchCount++;
              if (switchCount == 1) {
                await switchGate.future;
              }
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{'data': <String, dynamic>{}},
                ),
              );
              return;
            case '/auth/refresh':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{
                    'data': <String, dynamic>{
                      'access_token': 'refreshed-access',
                      'refresh_token': 'refreshed-refresh',
                    },
                  },
                ),
              );
              return;
            case '/users/me':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _userMeResponse(
                    userId: 'user-1',
                    email: 'owner@example.com',
                    roleName: 'owner',
                  ),
                ),
              );
              return;
            case '/wellar/workspaces/context':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _workspaceContextResponse(
                    activeMembershipId: 'membership-1',
                    memberships: [
                      _membership(
                        id: 'membership-1',
                        memberRole: 'owner',
                        companyId: 'company-1',
                        companyName: 'Company One',
                        isCurrent: true,
                      ),
                    ],
                  ),
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

      final first = OrganizationService.instance.syncWorkspaceSession(
        membershipId: 'membership-1',
        trigger: 'bootstrap',
      );
      final second = OrganizationService.instance.syncWorkspaceSession(
        membershipId: 'membership-1',
        trigger: 'bootstrap',
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      switchGate.complete();

      final firstContext = await first;
      final secondContext = await second;

      expect(switchCount, 1);
      expect(firstContext.membershipId, 'membership-1');
      expect(secondContext.membershipId, 'membership-1');
    });

    test('session restore uses canonical active membership instead of first membership row', () async {
      await _prepareSession();
      await Session.instance.setAuth(
        accessToken: 'restore-access',
        refreshToken: 'restore-refresh',
        userId: 'user-1',
        userEmail: 'owner@example.com',
        roleName: 'owner',
      );

      final requests = <String>[];
      interceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add('${options.method} ${options.path}');
          switch (options.path) {
            case '/users/me':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _userMeResponse(
                    userId: 'user-1',
                    email: 'owner@example.com',
                    roleName: 'owner',
                  ),
                ),
              );
              return;
            case '/wellar/workspaces/context':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _workspaceContextResponse(
                    activeMembershipId: 'membership-2',
                    memberships: [
                      _membership(
                        id: 'membership-1',
                        memberRole: 'employee',
                        companyId: 'company-1',
                        companyName: 'Company One',
                      ),
                      _membership(
                        id: 'membership-2',
                        memberRole: 'owner',
                        companyId: 'company-2',
                        companyName: 'Company Two',
                        isCurrent: true,
                      ),
                    ],
                  ),
                ),
              );
              return;
            case '/wellar/workspaces/switch':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{'data': <String, dynamic>{}},
                ),
              );
              return;
            case '/auth/refresh':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{
                    'data': <String, dynamic>{
                      'access_token': 'refreshed-access',
                      'refresh_token': 'refreshed-refresh',
                    },
                  },
                ),
              );
              return;
            case '/wellar/push-subscriptions/sync':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{'data': <String, dynamic>{}},
                ),
              );
              return;
            case '/items/business_profile_members':
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 500,
                    data: const <String, dynamic>{
                      'error': 'membership fallback should not be used',
                    },
                  ),
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

      final result = await resolveVerifiedRouteResult();

      expect(result.kind, VerifiedRouteKind.roleShell);
      expect(result.context, isNotNull);
      expect(result.context?.membershipId, 'membership-2');
      expect(result.context?.businessProfileId, 'company-2');
      expect(
        requests.where((entry) => entry == 'GET /items/business_profile_members'),
        isEmpty,
      );
      expect(
        requests.where((entry) => entry == 'POST /wellar/workspaces/switch'),
        isEmpty,
      );
      expect(
        requests,
        equals(const [
          'GET /users/me',
          'GET /users/me',
          'GET /wellar/workspaces/context',
        ]),
      );
      expect(
        await OrganizationService.instance.fetchActiveWorkspaceContext(),
        isNotNull,
      );
      expect(
        (await OrganizationService.instance.fetchActiveWorkspaceContext())
            ?.membershipId,
        'membership-2',
      );
    });

    test('google post-auth uses canonical active membership without fallback or switch', () async {
      await _prepareSession();

      final requests = <String>[];
      var contextCalls = 0;
      interceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add('${options.method} ${options.path}');
          if (options.path.contains('/auth/google/mobile-exchange')) {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: const <String, dynamic>{
                  'data': <String, dynamic>{
                    'access_token': 'google-access-token',
                    'refresh_token': 'google-refresh-token',
                  },
                },
              ),
            );
            return;
          }
          switch (options.path) {
            case '/users/me':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _userMeResponse(
                    userId: 'user-1',
                    email: 'owner@example.com',
                    roleName: 'owner',
                  ),
                ),
              );
              return;
            case '/wellar/workspaces/context':
              contextCalls++;
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _workspaceContextResponse(
                    activeMembershipId: 'membership-2',
                    memberships: [
                      _membership(
                        id: 'membership-1',
                        memberRole: 'employee',
                        companyId: 'company-1',
                        companyName: 'Company One',
                      ),
                      _membership(
                        id: 'membership-2',
                        memberRole: 'owner',
                        companyId: 'company-2',
                        companyName: 'Company Two',
                        isCurrent: true,
                      ),
                    ],
                  ),
                ),
              );
              return;
            case '/wellar/push-subscriptions/sync':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{'data': <String, dynamic>{}},
                ),
              );
              return;
            case '/items/business_profile_members':
              fail('GET /items/business_profile_members should not be called');
            case '/wellar/workspaces/switch':
              fail('POST /wellar/workspaces/switch should not be called');
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

      await AuthService.instance.loginWithGoogle(
        googleAuthOverride: () async => (
          idToken: 'google-id-token',
          accessToken: 'google-access-token',
        ),
      );

      final cached = await OrganizationService.instance.fetchActiveWorkspaceContext();
      expect(cached, isNotNull);
      expect(cached?.membershipId, 'membership-2');
      expect(cached?.businessProfileId, 'company-2');
      expect(
        requests.where((entry) => entry == 'GET /items/business_profile_members'),
        isEmpty,
      );
      expect(
        requests.where((entry) => entry == 'POST /wellar/workspaces/switch'),
        isEmpty,
      );
      expect(
        requests.where((entry) => entry == 'POST /wellar/push-subscriptions/sync'),
        isNotEmpty,
      );
      expect(contextCalls, 1);
    });

    test('google post-auth with missing canonical workspace throws noMembership and clears local state', () async {
      await _prepareSession();

      final requests = <String>[];
      interceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add('${options.method} ${options.path}');
          if (options.path.contains('/auth/google/mobile-exchange')) {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: const <String, dynamic>{
                  'data': <String, dynamic>{
                    'access_token': 'google-access-token',
                    'refresh_token': 'google-refresh-token',
                  },
                },
              ),
            );
            return;
          }
          switch (options.path) {
            case '/users/me':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _userMeResponse(
                    userId: 'user-1',
                    email: 'owner@example.com',
                    roleName: 'owner',
                  ),
                ),
              );
              return;
            case '/wellar/workspaces/context':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _workspaceContextResponse(
                    activeMembershipId: '',
                    memberships: const [],
                  ),
                ),
              );
              return;
            case '/items/business_profile_members':
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 500,
                    data: const <String, dynamic>{
                      'error': 'membership fallback should not be used',
                    },
                  ),
                ),
              );
              return;
            case '/wellar/workspaces/switch':
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 500,
                    data: const <String, dynamic>{
                      'error': 'workspace switch should not be used',
                    },
                  ),
                ),
              );
              return;
            case '/wellar/push-subscriptions/sync':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{'data': <String, dynamic>{}},
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

      await expectLater(
        AuthService.instance.loginWithGoogle(
          googleAuthOverride: () async => (
            idToken: 'google-id-token',
            accessToken: 'google-access-token',
          ),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            AuthFlowError.noMembership,
          ),
        ),
      );

      expect(await OrganizationService.instance.fetchActiveWorkspaceContext(), isNull);
      expect(
        requests.where((entry) => entry == 'GET /items/business_profile_members'),
        isEmpty,
      );
      expect(
        requests.where((entry) => entry == 'POST /wellar/workspaces/switch'),
        isEmpty,
      );
      expect(
        requests.where((entry) => entry == 'POST /wellar/push-subscriptions/sync'),
        isEmpty,
      );
      expect(
        requests.where(
          (entry) =>
              entry.startsWith('GET /items/request_invites') ||
              entry.startsWith('PATCH /items/request_invites'),
        ),
        isEmpty,
      );
    });

    test('startup restore with missing canonical context returns workspace access without membership fallback or switch', () async {
      await _prepareSession();
      await Session.instance.setAuth(
        accessToken: 'session-access',
        refreshToken: 'session-refresh',
        userId: 'user-1',
        userEmail: 'owner@example.com',
        roleName: 'owner',
      );

      final requests = <String>[];
      interceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add('${options.method} ${options.path}');
          switch (options.path) {
            case '/users/me':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _userMeResponse(
                    userId: 'user-1',
                    email: 'owner@example.com',
                    roleName: 'owner',
                  ),
                ),
              );
              return;
            case '/wellar/workspaces/context':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _workspaceContextResponse(
                    activeMembershipId: '',
                    memberships: const [],
                  ),
                ),
              );
              return;
            case '/wellar/workspaces/switch':
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 500,
                    data: const <String, dynamic>{
                      'error': 'workspace switch should not be used',
                    },
                  ),
                ),
              );
              return;
            case '/items/business_profile_members':
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 500,
                    data: const <String, dynamic>{
                      'error': 'membership fallback should not be used',
                    },
                  ),
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

      final result = await resolveVerifiedRouteResult();

      expect(result.kind, VerifiedRouteKind.workspaceAccess);
      expect(result.context, isNull);
      expect(
        requests.where((entry) => entry == 'GET /items/business_profile_members'),
        isEmpty,
      );
      expect(
        requests.where((entry) => entry == 'POST /wellar/workspaces/switch'),
        isEmpty,
      );
      expect(
        requests,
        equals(const [
          'GET /users/me',
          'GET /users/me',
          'GET /wellar/workspaces/context',
        ]),
      );
    });
  });

  group('Workspace access recovery', () {
    final client = DirectusClient.instance.client;
    late InterceptorsWrapper interceptor;

    tearDown(() async {
      client.interceptors.remove(interceptor);
      await Session.instance.clear();
      OrganizationService.instance.clearProfileCache();
      OrganizationService.instance.clearActiveWorkspaceContext();
    });

    testWidgets('refresh access shows explicit organization selector and only switches after tap', (
      WidgetTester tester,
    ) async {
      await _prepareSession();
      await Session.instance.setAuth(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        userId: 'user-1',
        userEmail: 'owner@example.com',
        roleName: 'owner',
      );

      final requests = <String>[];
      var contextCalls = 0;
      var switchCalls = 0;
      var fallbackMembershipLookupCount = 0;
      var workforceMembershipQueryCount = 0;
      interceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add('${options.method} ${options.path}');
          if (options.path.contains('/auth/google/mobile-exchange')) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 500,
                  data: const <String, dynamic>{
                    'error': 'unexpected request',
                  },
                ),
              ),
            );
            return;
          }
          switch (options.path) {
            case '/users/me':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _userMeResponse(
                    userId: 'user-1',
                    email: 'owner@example.com',
                    roleName: 'owner',
                  ),
                ),
              );
              return;
            case '/wellar/workspaces/context':
              contextCalls++;
              if (contextCalls == 1) {
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: _workspaceContextResponse(
                      activeMembershipId: '',
                      memberships: [
                        _membership(
                          id: 'membership-1',
                          memberRole: 'employee',
                          companyId: 'company-1',
                          companyName: 'Company One',
                        ),
                        _membership(
                          id: 'membership-2',
                          memberRole: 'manager',
                          companyId: 'company-2',
                          companyName: 'Company Two',
                        ),
                      ],
                    ),
                  ),
                );
                return;
              }
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _workspaceContextResponse(
                    activeMembershipId: 'membership-2',
                    memberships: [
                      _membership(
                        id: 'membership-1',
                        memberRole: 'employee',
                        companyId: 'company-1',
                        companyName: 'Company One',
                        isCurrent: false,
                      ),
                      _membership(
                        id: 'membership-2',
                        memberRole: 'manager',
                        companyId: 'company-2',
                        companyName: 'Company Two',
                        isCurrent: true,
                      ),
                    ],
                  ),
                ),
              );
              return;
            case '/wellar/workspaces/switch':
              switchCalls++;
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{'data': <String, dynamic>{}},
                ),
              );
              return;
            case '/items/notifications':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{
                    'data': const <dynamic>[],
                  },
                ),
              );
              return;
            case '/items/wellness_scans':
            case '/items/alerts':
            case '/items/scan_requests':
              final businessProfileId =
                  options.queryParameters['filter[business_profile][_eq]']
                      ?.toString();
              if (businessProfileId != 'company-2') {
                fail(
                  'Unexpected manager background query scope: ${options.uri}',
                );
              }
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{
                    'data': const <dynamic>[],
                  },
                ),
              );
              return;
            case '/items/business_profile_members':
              final query = options.queryParameters;
              final businessProfileId = query['filter[business_profile][_eq]']?.toString();
              final currentUserFilter =
                  query['filter[_and][0][user][_eq]']?.toString();
              if (currentUserFilter != null && currentUserFilter.isNotEmpty) {
                fallbackMembershipLookupCount++;
                fail(
                  'Forbidden fallback membership lookup should not occur: ${options.uri}',
                );
              }
              if (businessProfileId == 'company-2') {
                workforceMembershipQueryCount++;
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: const <String, dynamic>{
                      'data': const <dynamic>[],
                    },
                  ),
                );
                return;
              }
              fail('Unexpected business_profile_members query: ${options.uri}');
            case '/auth/refresh':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{
                    'data': <String, dynamic>{
                      'access_token': 'refreshed-access',
                      'refresh_token': 'refreshed-refresh',
                    },
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

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: WorkspaceAccessScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Refresh access'));
      await tester.pumpAndSettle();

      expect(find.text('Choose an organization'), findsOneWidget);
      expect(find.text('Company One'), findsOneWidget);
      expect(find.text('Company Two'), findsOneWidget);
      expect(find.textContaining('EMPLOYEE'), findsOneWidget);
      expect(find.textContaining('MANAGER'), findsOneWidget);
      expect(
        requests.where((entry) => entry == 'POST /wellar/workspaces/switch'),
        isEmpty,
      );
      expect(switchCalls, 0);

      await tester.tap(find.text('Company Two'));

      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
        final routerMounted = find.byType(RoleShellRouter).evaluate().isNotEmpty;
        if (routerMounted &&
            switchCalls == 1 &&
            contextCalls == 2 &&
            workforceMembershipQueryCount == 1) {
          break;
        }
      }

      expect(
        requests.where((entry) => entry == 'POST /wellar/workspaces/switch'),
        isNotEmpty,
      );
      expect(switchCalls, 1);
      expect(contextCalls, 2);
      expect(fallbackMembershipLookupCount, 0);
      expect(workforceMembershipQueryCount, 1);
      expect(find.byType(RoleShellRouter), findsOneWidget);
      final router = tester.widget<RoleShellRouter>(find.byType(RoleShellRouter));
      expect(router.initialContext, isNotNull);
      expect(router.initialContext?.membershipId, 'membership-2');
      expect(router.initialContext?.businessProfileId, 'company-2');
    });
  });

  group('Business profile setup', () {
    final client = DirectusClient.instance.client;
    late InterceptorsWrapper interceptor;

    tearDown(() async {
      client.interceptors.remove(interceptor);
      await Session.instance.clear();
      OrganizationService.instance.clearProfileCache();
      OrganizationService.instance.clearActiveWorkspaceContext();
    });

    testWidgets('sparse 201 waits for refreshed canonical owner context', (
      WidgetTester tester,
    ) async {
      await _prepareSession();
      await Session.instance.setAuth(
        accessToken: 'session-access',
        refreshToken: 'session-refresh',
        userId: 'user-1',
        userEmail: 'owner@example.com',
        roleName: 'employee',
      );

      final contextGate = Completer<void>();
      var contextCalls = 0;

      interceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          switch (options.path) {
            case '/users/me':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _userMeResponse(
                    userId: 'user-1',
                    email: 'owner@example.com',
                    roleName: 'employee',
                  ),
                ),
              );
              return;
            case '/auth/refresh':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{
                    'data': <String, dynamic>{
                      'access_token': 'refreshed-access',
                      'refresh_token': 'refreshed-refresh',
                    },
                  },
                ),
              );
              return;
            case '/wellar/workspaces/create':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 201,
                  data: const <String, dynamic>{},
                ),
              );
              return;
            case '/wellar/workspaces/context':
              contextCalls++;
              if (contextCalls == 1) {
                await contextGate.future;
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: _workspaceContextResponse(
                      activeMembershipId: 'membership-owner',
                      memberships: [
                        _membership(
                          id: 'membership-owner',
                          memberRole: 'owner',
                          companyId: 'company-owner',
                          companyName: 'Owner Company',
                          isCurrent: true,
                        ),
                      ],
                    ),
                  ),
                );
                return;
              }
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _workspaceContextResponse(
                    activeMembershipId: 'membership-owner',
                    memberships: [
                      _membership(
                        id: 'membership-owner',
                        memberRole: 'owner',
                        companyId: 'company-owner',
                        companyName: 'Owner Company',
                        isCurrent: true,
                      ),
                    ],
                  ),
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

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: BusinessProfileWizardScreen(
              plan: Plan(
                id: 'plan-business',
                name: 'Business',
                code: 'business',
                description: 'Business plan',
                monthlyPrice: null,
                yearlyPrice: null,
                trialDays: 14,
                maxMembers: null,
                isBusiness: true,
                features: <String>[],
                isPopular: false,
                isActive: true,
                sortOrder: 1,
              ),
              billingCycle: 'monthly',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Acme Corp');
      await tester.enterText(fields.at(1), 'Healthcare');
      await tester.enterText(fields.at(2), '12');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      await tester.enterText(fields.at(0), 'Ada Lovelace');
      await tester.enterText(fields.at(1), 'owner@example.com');
      await tester.enterText(fields.at(2), '555-0100');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      await tester.enterText(fields.at(0), 'Egypt');
      await tester.enterText(fields.at(1), 'Cairo');
      await tester.enterText(fields.at(2), '1 Readiness Way');
      await tester.tap(find.text('Create workspace'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(RoleShellRouter), findsNothing);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      contextGate.complete();
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pumpAndSettle();

      expect(find.byType(RoleShellRouter), findsOneWidget);
    });

    testWidgets('sparse 201 stops when token refresh fails', (
      WidgetTester tester,
    ) async {
      await _prepareSession();
      await Session.instance.setAuth(
        accessToken: 'session-access',
        refreshToken: 'session-refresh',
        userId: 'user-1',
        userEmail: 'owner@example.com',
        roleName: 'employee',
      );

      var contextCalls = 0;

      interceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          switch (options.path) {
            case '/users/me':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _userMeResponse(
                    userId: 'user-1',
                    email: 'owner@example.com',
                    roleName: 'employee',
                  ),
                ),
              );
              return;
            case '/wellar/workspaces/create':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 201,
                  data: const <String, dynamic>{},
                ),
              );
              return;
            case '/auth/refresh':
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 401,
                    data: const <String, dynamic>{
                      'message': 'Session expired',
                    },
                  ),
                ),
              );
              return;
            case '/wellar/workspaces/context':
              contextCalls++;
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 500,
                    data: const <String, dynamic>{
                      'error': 'unexpected request',
                    },
                  ),
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

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: BusinessProfileWizardScreen(
              plan: Plan(
                id: 'plan-business',
                name: 'Business',
                code: 'business',
                description: 'Business plan',
                monthlyPrice: null,
                yearlyPrice: null,
                trialDays: 14,
                maxMembers: null,
                isBusiness: true,
                features: <String>[],
                isPopular: false,
                isActive: true,
                sortOrder: 1,
              ),
              billingCycle: 'monthly',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Acme Corp');
      await tester.enterText(fields.at(1), 'Healthcare');
      await tester.enterText(fields.at(2), '12');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      await tester.enterText(fields.at(0), 'Ada Lovelace');
      await tester.enterText(fields.at(1), 'owner@example.com');
      await tester.enterText(fields.at(2), '555-0100');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      await tester.enterText(fields.at(0), 'Egypt');
      await tester.enterText(fields.at(1), 'Cairo');
      await tester.enterText(fields.at(2), '1 Readiness Way');
      await tester.tap(find.text('Create workspace'));
      await tester.pumpAndSettle();

      expect(find.byType(RoleShellRouter), findsNothing);
      expect(
        find.text(
          'We created your workspace, but could not refresh access. Try again.',
        ),
        findsOneWidget,
      );
      expect(contextCalls, 0);
    });
  });

  group('Profile organization action', () {
    final client = DirectusClient.instance.client;
    late InterceptorsWrapper interceptor;

    tearDown(() async {
      client.interceptors.remove(interceptor);
      await Session.instance.clear();
      OrganizationService.instance.clearProfileCache();
      OrganizationService.instance.clearActiveWorkspaceContext();
    });

    testWidgets('switch organization action appears before logout and handles single organization state', (
      WidgetTester tester,
    ) async {
      await _prepareSession();
      await Session.instance.setAuth(
        accessToken: 'session-access',
        refreshToken: 'session-refresh',
        userId: 'user-1',
        userEmail: 'owner@example.com',
        roleName: 'owner',
      );

      interceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          switch (options.path) {
            case '/users/me':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _userMeResponse(
                    userId: 'user-1',
                    email: 'owner@example.com',
                    roleName: 'owner',
                  ),
                ),
              );
              return;
            case '/wellar/workspaces/context':
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _workspaceContextResponse(
                    activeMembershipId: 'membership-1',
                    memberships: [
                      _membership(
                        id: 'membership-1',
                        memberRole: 'owner',
                        companyId: 'company-1',
                        companyName: 'Company One',
                        isCurrent: true,
                      ),
                    ],
                  ),
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

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appLanguageControllerProvider.overrideWith(
              (ref) => AppLanguageController(
                initialLanguage: AppLanguage.english,
                loaded: true,
              ),
            ),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final switchOrg = find.text('Switch Organization');
      final logout = find.text('Logout');
      expect(switchOrg, findsOneWidget);
      expect(logout, findsOneWidget);
      expect(
        tester.getTopLeft(switchOrg).dy < tester.getTopLeft(logout).dy,
        isTrue,
      );

      await tester.tap(switchOrg);
      await tester.pumpAndSettle();

      expect(
        find.text('This account only has one active organization.'),
        findsOneWidget,
      );
    });
  });

  group('RoleShellRouter state refresh', () {
    tearDown(() async {
      await Session.instance.clear();
      OrganizationService.instance.clearProfileCache();
      OrganizationService.instance.clearActiveWorkspaceContext();
    });

    testWidgets('didUpdateWidget rebuilds shell when initial context identity changes', (
      WidgetTester tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const firstContext = ActiveWorkspaceContext(
        currentUserId: 'user-1',
        currentUserEmail: 'owner@example.com',
        currentUserFirstName: 'Ada',
        currentUserLastName: 'Lovelace',
        directusRoleId: 'role-owner',
        directusRoleName: 'owner',
        membershipUserId: 'user-1',
        businessProfileId: 'company-1',
        businessProfileName: 'Company One',
        businessProfileStatus: 'true',
        businessPlanCode: 'business',
        businessBillingStatus: 'active',
        membershipId: 'membership-1',
        memberRole: 'owner',
        membershipRole: 'owner',
        finalEffectiveRole: 'owner',
        membershipStatus: 'active',
        departmentId: null,
        departmentName: null,
        scopeLabel: 'OWNER',
      );
      const secondContext = ActiveWorkspaceContext(
        currentUserId: 'user-1',
        currentUserEmail: 'owner@example.com',
        currentUserFirstName: 'Ada',
        currentUserLastName: 'Lovelace',
        directusRoleId: 'role-owner',
        directusRoleName: 'owner',
        membershipUserId: 'user-1',
        businessProfileId: 'company-2',
        businessProfileName: 'Company Two',
        businessProfileStatus: 'true',
        businessPlanCode: 'business',
        businessBillingStatus: 'active',
        membershipId: 'membership-2',
        memberRole: 'owner',
        membershipRole: 'owner',
        finalEffectiveRole: 'owner',
        membershipStatus: 'active',
        departmentId: null,
        departmentName: null,
        scopeLabel: 'OWNER',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: RoleShellRouter(initialContext: firstContext),
          ),
        ),
      );
      await tester.pump();

      expect(
        container.read(activeWorkspaceContextProvider)?.membershipId,
        'membership-1',
      );
      expect(
        container.read(activeWorkspaceContextProvider)?.businessProfileId,
        'company-1',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: RoleShellRouter(initialContext: secondContext),
          ),
        ),
      );
      await tester.pump();

      expect(
        container.read(activeWorkspaceContextProvider)?.membershipId,
        'membership-2',
      );
      expect(
        container.read(activeWorkspaceContextProvider)?.businessProfileId,
        'company-2',
      );
    });
  });
}
