import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config/app_config.dart';
import '../state/session.dart';
import '../models/user_profile.dart';
import 'directus_client.dart';
import 'invite_service.dart';
import 'organization_service.dart';
import 'push_notification_service.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  Dio get _client => DirectusClient.instance.client;
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  GoogleSignIn get _googleSignIn {
    final serverClientId = AppConfig.googleMobileClientId.trim();
    if (serverClientId.isNotEmpty) {
      return GoogleSignIn(serverClientId: serverClientId);
    }
    return GoogleSignIn();
  }

  bool get isGoogleOAuthReady => true;

  static const Duration _loginHardTimeout = Duration(seconds: 20);

  Future<void> login({required String email, required String password}) async {
    debugPrint('[AUTH_DEBUG] login_start=true');
    try {
      OrganizationService.instance.clearProfileCache();
      OrganizationService.instance.clearActiveWorkspaceContext();
      final response = await _client
          .post(
            '/auth/login',
            data: {'email': email, 'password': password},
          )
          .timeout(_loginHardTimeout);
      final data = _extractDataMap(response.data);
      final access = data['access_token']?.toString();
      final refresh = data['refresh_token']?.toString();
      if (access == null) {
        throw Exception('Missing access token');
      }

      await Session.instance.setAuth(
        accessToken: access,
        refreshToken: refresh,
      );
      debugPrint('[AUTH_DEBUG] session_saved=true');

      try {
        await _loadMe();
      } catch (e) {
        _logAuthFailure('login_profile', e);
      }

      try {
        await InviteService.instance.claimInvitesForCurrentUser();
        final token = Session.instance.pendingInviteToken;
        if (token != null && token.trim().isNotEmpty) {
          await InviteService.instance.claimInviteByToken(token.trim());
          await Session.instance.setPendingInviteToken(null);
        }
      } catch (e) {
        _logAuthFailure('login_invites', e);
      }
    } on TimeoutException {
      debugPrint('[AUTH_DEBUG] login_exception_type=TimeoutException');
      throw Exception('The server took too long. Try again.');
    } on DioException catch (e) {
      debugPrint('[AUTH_DEBUG] login_exception_type=${e.runtimeType}');
      debugPrint('[AUTH_DEBUG] login_dio_status=${e.response?.statusCode ?? 0}');
      throw Exception(_extractMessage(e));
    } catch (e) {
      debugPrint('[AUTH_DEBUG] login_exception_type=${e.runtimeType}');
      throw Exception('Sign in could not be completed. Try again.');
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    debugPrint('[AUTH_DEBUG] register_start=true');
    try {
      final response = await _client
          .post(
            '/users/register',
            data: {
              'email': email,
              'password': password,
              'first_name': firstName,
              'last_name': lastName,
            },
          )
          .timeout(_loginHardTimeout);
      final data = _extractDataMap(response.data);
      final access = data['access_token']?.toString();
      final refresh = data['refresh_token']?.toString();
      if (access != null && access.isNotEmpty) {
        await Session.instance.setAuth(
          accessToken: access,
          refreshToken: refresh,
        );
        debugPrint('[AUTH_DEBUG] session_saved=true');
        return true;
      }
      debugPrint('[AUTH_DEBUG] session_saved=false');
      return false;
    } on TimeoutException {
      debugPrint('[AUTH_DEBUG] register_exception_type=TimeoutException');
      throw Exception('The server took too long. Try again.');
    } on DioException catch (e) {
      debugPrint('[AUTH_DEBUG] register_exception_type=${e.runtimeType}');
      debugPrint('[AUTH_DEBUG] register_dio_status=${e.response?.statusCode ?? 0}');
      throw Exception(_extractMessage(e));
    } catch (e) {
      debugPrint('[AUTH_DEBUG] register_exception_type=${e.runtimeType}');
      throw Exception(_extractMessageForGeneralFailure(e));
    }
  }

  Future<PasswordResetRequestResult> requestPasswordReset({
    required String email,
  }) async {
    try {
      final response = await _client.post(
        '/auth/password/request',
        data: {
          'email': email,
          'reset_url': '${AppConfig.publicWebBaseUrl}/reset-password',
        },
        options: Options(extra: {'skip_auth': true, 'skip_refresh': true}),
      );
      final status = response.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        return PasswordResetRequestResult.success;
      }
      return PasswordResetRequestResult.unavailable;
    } on DioException catch (error) {
      return _classifyPasswordResetRequestResult(error);
    }
  }

  PasswordResetRequestResult _classifyPasswordResetRequestResult(
    DioException error,
  ) {
    final status = error.response?.statusCode ?? 0;
    if (status == 404 || status == 405 || status == 422) {
      return PasswordResetRequestResult.unavailable;
    }
    if (status >= 500 && status < 600) {
      return PasswordResetRequestResult.unavailable;
    }

    switch (error.type) {
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.unknown:
        return PasswordResetRequestResult.unavailable;
      case DioExceptionType.badResponse:
        return PasswordResetRequestResult.unavailable;
    }
  }

  Future<void> loginWithGoogle({
    Future<({String idToken, String? accessToken})?> Function()?
        googleAuthOverride,
  }) async {
    _googleAuthLog('start');
    _googleAuthLog('flow: native_google_sdk');
    try {
      final googleAuth = googleAuthOverride == null
          ? await _signInWithGoogleSdk()
          : await googleAuthOverride();
      if (googleAuth == null) {
        _googleAuthLog('account selected: false');
        throw const AuthFlowException(AuthFlowError.googleCancelled);
      }
      _googleAuthLog('account selected: true');

      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;
      _googleAuthLog(
        'idToken available: ${idToken.isNotEmpty}',
      );
      _googleAuthLog(
        'accessToken available: ${accessToken != null && accessToken.isNotEmpty}',
      );
      if (idToken.isEmpty) {
        throw const AuthFlowException(AuthFlowError.googleNoIdToken);
      }

      final exchanged = await _exchangeWithMobileAuth(
        idToken: idToken,
        accessToken: accessToken,
      );
      final finalAccess = exchanged?.$1;
      final refreshToken = exchanged?.$2;

      if (finalAccess == null || finalAccess.isEmpty) {
        _googleAuthLog('directus session created: false');
        throw const AuthFlowException(AuthFlowError.noWorkspaceSession);
      }

      await Session.instance.setAuth(
        accessToken: finalAccess,
        refreshToken: refreshToken,
      );
      _googleAuthLog('session created: true');
      _googleAuthLog('directus session created: true');
      debugPrint('[Auth] Directus access token stored: true');
      _googleAuthLog('tokens stored: true');

      try {
        final me = await _loadMe(logGoogleStatus: true);
        _googleAuthLog('current user loaded: ${me.id.isNotEmpty}');
      } catch (e) {
        _logAuthFailure('google_profile', e);
      }

      try {
        await InviteService.instance.claimInvitesForCurrentUser();
        final token = Session.instance.pendingInviteToken;
        if (token != null && token.trim().isNotEmpty) {
          debugPrint('[PostLogin] route: invite-claim');
          await InviteService.instance.claimInviteByToken(token.trim());
          await Session.instance.setPendingInviteToken(null);
        }
      } catch (e) {
        _logAuthFailure('google_invites', e);
      }
    } on AuthFlowException catch (e) {
      _googleAuthLog('session created: false');
      _googleAuthLog('Directus session created: false');
      debugPrint('[Auth] Directus access token stored: false');
      _googleAuthLog('tokens stored: false');
      _googleAuthLog('/users/me success: false');
      if (e.code == AuthFlowError.invalidSession) {
        await _clearAuthStateAfterGoogleFailure();
      }
      rethrow;
    } on DioException catch (e) {
      _googleAuthLog('session created: false');
      _googleAuthLog('Directus session created: false');
      debugPrint('[Auth] Directus access token stored: false');
      _googleAuthLog('tokens stored: false');
      _googleAuthLog('/users/me success: false');
      if (_isTransientNetworkMessage(_extractMessage(e).toLowerCase())) {
        throw const AuthFlowException(AuthFlowError.networkIssue);
      }
      throw const AuthFlowException(AuthFlowError.googleConfigMissing);
    } catch (_) {
      _googleAuthLog('session created: false');
      _googleAuthLog('Directus session created: false');
      debugPrint('[Auth] Directus access token stored: false');
      _googleAuthLog('tokens stored: false');
      _googleAuthLog('/users/me success: false');
      throw const AuthFlowException(AuthFlowError.googleConfigMissing);
    }
  }

  Future<({String idToken, String? accessToken})?> _signInWithGoogleSdk() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    return (idToken: auth.idToken ?? '', accessToken: auth.accessToken);
  }

  Future<(String, String?)?> _exchangeWithMobileAuth({
    required String idToken,
    required String? accessToken,
  }) async {
    final endpoint =
        '${AppConfig.googleMobileExchangeBaseUrl}${AppConfig.googleMobileExchangePath}';
    _googleAuthLog('exchange URL: $endpoint');
    try {
      final response = await _client.post(
        endpoint,
        data: {
          'id_token': idToken,
          if (accessToken != null && accessToken.isNotEmpty)
            'access_token': accessToken,
        },
        options: Options(extra: {'skip_auth': true, 'skip_refresh': true}),
      );
      _googleAuthLog('exchange status: ${response.statusCode ?? 0}');
      if ((response.statusCode ?? 0) != 200) {
        _googleAuthLog(
          'exchange body on error: ${_sanitizeLogResponse(response.data)}',
        );
      }
      final payload = response.data;
      Map<String, dynamic>? body;
      if (payload is Map<String, dynamic>) {
        body = payload['data'] is Map<String, dynamic>
            ? payload['data'] as Map<String, dynamic>
            : payload;
      }
      final access = body?['access_token']?.toString();
      final refresh = body?['refresh_token']?.toString();
      _googleAuthLog(
        'response has access_token: ${access != null && access.isNotEmpty}',
      );
      _googleAuthLog(
        'response has refresh_token: ${refresh != null && refresh.isNotEmpty}',
      );
      if (access == null || access.isEmpty) return null;
      return (access, refresh);
    } on DioException catch (e) {
      _googleAuthLog('exchange status: ${e.response?.statusCode ?? 0}');
      _googleAuthLog(
        'exchange body on error: ${_sanitizeLogResponse(e.response?.data)}',
      );
      _googleAuthLog('response has access_token: false');
      _googleAuthLog('response has refresh_token: false');
      if ((e.response?.statusCode ?? 0) == 404) {
        throw const AuthFlowException(AuthFlowError.googleExchangeMissing);
      }
      rethrow;
    }
  }

  Future<void> _clearAuthStateAfterGoogleFailure() async {
    OrganizationService.instance.clearProfileCache();
    OrganizationService.instance.clearActiveWorkspaceContext();
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _firebaseAuth.signOut();
    } catch (_) {}
    await Session.instance.clear();
  }

  Map<String, dynamic> _extractDataMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final nested = raw['data'];
      if (nested is Map<String, dynamic>) {
        return nested;
      }
      return raw;
    }
    return const {};
  }

  void _logAuthFailure(String scope, Object error) {
    debugPrint('[AUTH_DEBUG] ${scope}_exception_type=${error.runtimeType}');
    if (error is DioException) {
      debugPrint(
        '[AUTH_DEBUG] ${scope}_dio_status=${error.response?.statusCode ?? 0}',
      );
    }
  }

  void _googleAuthLog(String message) {
    if (kDebugMode) {
      debugPrint('[GoogleAuth] $message');
    }
  }

  bool _isTransientNetworkMessage(String message) {
    return message.contains('connection') ||
        message.contains('timeout') ||
        message.contains('network') ||
        message.contains('socket') ||
        message.contains('host lookup') ||
        message.contains('temporary failure');
  }

  String _sanitizeLogResponse(dynamic data) {
    if (data == null) return 'null';
    if (data is Map) {
      final copy = <String, dynamic>{};
      data.forEach((key, value) {
        final k = key.toString().toLowerCase();
        if (k.contains('token') || k.contains('secret')) {
          copy[key.toString()] = '***';
        } else {
          copy[key.toString()] = value;
        }
      });
      return copy.toString();
    }
    return data.toString();
  }

  Future<UserProfile> fetchProfile() async {
    return _loadMe();
  }

  Future<UserProfile> _loadMe({bool logGoogleStatus = false}) async {
    final response = await _client.get(
      '/users/me',
      queryParameters: {'fields': 'id,email,first_name,role.id,role.name'},
    );
    if (logGoogleStatus) {
      debugPrint('[Auth] /users/me status: ${response.statusCode ?? 0}');
      debugPrint('[Auth] /users/me success: true');
    }
    final data = response.data['data'] as Map<String, dynamic>;
    final profile = UserProfile.fromJson(data);
    await Session.instance.setAuth(
      accessToken: Session.instance.accessToken ?? '',
      userId: profile.id,
      userEmail: profile.email,
      userName: profile.name,
      roleName: profile.roleName,
    );
    debugPrint('[Auth] current user id=${profile.id} email=${profile.email}');
    return profile;
  }

  Future<SessionValidationState> validateSession() async {
    final token = Session.instance.accessToken;
    debugPrint(
      '[Auth] validate session start has_token=${token != null && token.isNotEmpty}',
    );
    if (token == null || token.isEmpty) {
      return SessionValidationState.unauthenticated;
    }
    try {
      await _loadMe();
      debugPrint('[Auth] validate session success');
      return SessionValidationState.authenticated;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 401) {
        debugPrint('[Auth] validate session failed -> clearing session');
        OrganizationService.instance.clearProfileCache();
        await Session.instance.clear();
        return SessionValidationState.unauthenticated;
      }
      debugPrint('[Auth] validate session unavailable status=$status');
      return SessionValidationState.validationUnavailable;
    } catch (_) {
      debugPrint('[Auth] validate session unavailable');
      return SessionValidationState.validationUnavailable;
    }
  }

  Future<void> logout() async {
    OrganizationService.instance.clearProfileCache();
    OrganizationService.instance.clearActiveWorkspaceContext();
    try {
      await PushNotificationService.instance.unregisterDevice();
    } catch (_) {}
    try {
      final refreshToken = Session.instance.refreshToken;
      await _client.post(
        '/auth/logout',
        data: {
          if (refreshToken != null && refreshToken.isNotEmpty)
            'refresh_token': refreshToken,
        },
      );
    } catch (_) {}
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _firebaseAuth.signOut();
    } catch (_) {}
    await Session.instance.clear();
    OrganizationService.instance.clearProfileCache();
    OrganizationService.instance.clearActiveWorkspaceContext();
  }

  String _extractMessage(DioException e) {
    final status = e.response?.statusCode ?? 0;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'The server took too long. Try again.';
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
      case DioExceptionType.badResponse:
        break;
    }
    if (status == 401 || status == 403) {
      return 'Invalid email or password.';
    }
    if (status == 409) {
      return 'Account already exists.';
    }
    final data = e.response?.data;
    if (data is Map) {
      final errors = data['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        if (first is Map && first['message'] != null) {
          return first['message'].toString();
        }
      }
      if (data['message'] != null) {
        return data['message'].toString();
      }
    }
    final message = (e.message ?? '').toLowerCase();
    if (message.contains('timeout')) {
      return 'The server took too long. Try again.';
    }
    if (message.contains('connection') ||
        message.contains('network') ||
        message.contains('socket') ||
        message.contains('host lookup')) {
      return 'Could not connect to Wellar right now. Check your connection.';
    }
    return e.message ?? 'Request could not be completed. Try again.';
  }

  String _extractMessageForGeneralFailure(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('timeout')) {
      return 'The server took too long. Try again.';
    }
    if (raw.contains('connection') ||
        raw.contains('network') ||
        raw.contains('socket') ||
        raw.contains('host lookup')) {
      return 'Could not connect to Wellar right now. Check your connection.';
    }
    return 'Account creation could not be completed. Try again.';
  }
}

enum SessionValidationState {
  authenticated,
  unauthenticated,
  validationUnavailable,
}

enum AuthFlowError {
  googleCancelled,
  googleNoIdToken,
  networkIssue,
  googleExchangeMissing,
  googleConfigMissing,
  noWorkspaceSession,
  noMembership,
  invalidSession,
}

class AuthFlowException implements Exception {
  final AuthFlowError code;
  const AuthFlowException(this.code);
}

enum PasswordResetRequestResult { success, unavailable }
