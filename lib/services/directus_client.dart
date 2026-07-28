import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'dart:core';

import '../config/app_config.dart';
import '../state/session.dart';

class DirectusClient {
  DirectusClient._() {
    _baseUrls = _buildBaseUrls();
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrls.first,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.extra['skip_auth'] != true) {
            final token = Session.instance.accessToken;
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final options = error.requestOptions;

          if (_shouldTryAuthRefresh(error, options)) {
            final refreshed = await _refreshAuthToken();
            if (refreshed) {
              try {
                final retried = await _retryRequest(
                  options,
                  authRetry: true,
                  baseRetry: options.extra['base_retry'] == true,
                  transientRetryCount:
                      (options.extra['transient_retry_count'] as int?) ?? 0,
                );
                handler.resolve(retried);
                return;
              } catch (_) {
                // Continue to fallback/network handling.
              }
            }
          }

          final alreadyBaseRetried = options.extra['base_retry'] == true;
          final shouldRetryBase = _shouldRetryWithFallback(
            error,
            alreadyBaseRetried,
          );
          if (shouldRetryBase) {
            _rotateBaseUrl();
            try {
              final retried = await _retryRequest(
                options,
                authRetry: options.extra['auth_retry'] == true,
                baseRetry: true,
                transientRetryCount:
                    (options.extra['transient_retry_count'] as int?) ?? 0,
              );
              handler.resolve(retried);
              return;
            } catch (e) {
              handler.next(e is DioException ? e : error);
              return;
            }
          }

          final transientRetryCount =
              (options.extra['transient_retry_count'] as int?) ?? 0;
          if (_shouldRetryTransientConnection(error, transientRetryCount)) {
            try {
              final backoffMs = 300 * (transientRetryCount + 1);
              await Future<void>.delayed(Duration(milliseconds: backoffMs));
              final retried = await _retryRequest(
                options,
                authRetry: options.extra['auth_retry'] == true,
                baseRetry: options.extra['base_retry'] == true,
                transientRetryCount: transientRetryCount + 1,
              );
              handler.resolve(retried);
              return;
            } catch (e) {
              handler.next(e is DioException ? e : error);
              return;
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  late final Dio _dio;
  late final List<String> _baseUrls;
  int _baseIndex = 0;
  Future<bool>? _refreshInFlight;
  static const int _maxTransientRetries = 2;

  static final DirectusClient instance = DirectusClient._();

  Dio get client => _dio;
  int get instanceId => identityHashCode(this);
  int get dioInstanceId => identityHashCode(_dio);

  static String tokenFingerprint(String? token) {
    final normalized = token?.trim() ?? '';
    if (normalized.isEmpty) return 'empty';
    final hash = Object.hashAll(normalized.codeUnits).toUnsigned(32);
    return 'len${normalized.length}:h${hash.toRadixString(16)}';
  }

  void debugAuthState({
    required String label,
    String? token,
  }) {
    if (!kDebugMode) return;
    final normalizedToken = token?.trim() ?? Session.instance.accessToken?.trim() ?? '';
    debugPrint(
      '[DIRECTUS_CLIENT_STATE] label=$label client_instance_id=$instanceId dio_instance_id=$dioInstanceId token_fp=${tokenFingerprint(normalizedToken)} auth_header_present=${_dio.options.headers['Authorization']?.toString().trim().isNotEmpty == true}',
    );
  }

  List<String> _buildBaseUrls() {
    final urls = <String>[];
    final primary = AppConfig.directusBaseUrl.trim();
    if (primary.isNotEmpty) {
      urls.add(primary);
    }
    final fallback = AppConfig.directusFallbackUrl.trim();
    if (fallback.isNotEmpty && fallback != primary) {
      urls.add(fallback);
    }
    if (urls.isEmpty) {
      urls.add(AppConfig.directusBaseUrl);
    }
    return urls;
  }

  bool _shouldRetryWithFallback(DioException error, bool alreadyRetried) {
    if (alreadyRetried || _baseUrls.length < 2) return false;
    if (error.response != null) return false;
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return true;
      default:
        return false;
    }
  }

  bool _shouldTryAuthRefresh(DioException error, RequestOptions options) {
    if (options.extra['skip_refresh'] == true) return false;
    if (options.extra['auth_retry'] == true) return false;
    if (_isAuthEndpoint(options.path)) return false;
    final status = error.response?.statusCode ?? 0;
    return status == 401;
  }

  bool _isAuthEndpoint(String path) {
    final p = path.toLowerCase();
    return p.startsWith('/auth/login') ||
        p.startsWith('/auth/logout') ||
        p.startsWith('/auth/refresh');
  }

  Future<Response<dynamic>> _retryRequest(
    RequestOptions original, {
    required bool authRetry,
    required bool baseRetry,
    required int transientRetryCount,
  }) async {
    final request = original.copyWith(
      baseUrl: _dio.options.baseUrl,
      extra: {
        ...original.extra,
        'auth_retry': authRetry,
        'base_retry': baseRetry,
        'transient_retry_count': transientRetryCount,
      },
    );
    final token = Session.instance.accessToken;
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    } else {
      request.headers.remove('Authorization');
    }
    return _dio.fetch(request);
  }

  bool _shouldRetryTransientConnection(DioException error, int retryCount) {
    if (retryCount >= _maxTransientRetries) return false;
    if (error.response != null) return false;
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return true;
      default:
        return false;
    }
  }

  Future<bool> _refreshAuthToken() async {
    if (_refreshInFlight != null) {
      return _refreshInFlight!;
    }
    final refreshFuture = _performRefresh();
    _refreshInFlight = refreshFuture;
    try {
      return await refreshFuture;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<bool> refreshAuthToken() {
    debugPrint('[WORKSPACE_SWITCH_AUTH] refresh_mode=json');
    debugPrint(
      '[WORKSPACE_SWITCH_AUTH] refresh_token_present=${(Session.instance.refreshToken?.trim().isNotEmpty == true)}',
    );
    return _refreshAuthToken().then((refreshed) {
      debugPrint(
        '[WORKSPACE_SWITCH_AUTH] refreshed_access_token_present=${(Session.instance.accessToken?.trim().isNotEmpty == true)}',
      );
      if (refreshed) {
        syncAuthorizationHeaderFromSession();
      }
      return refreshed;
    });
  }

  Future<bool> refreshSessionAfterWorkspaceSwitch() async {
    final refreshToken = Session.instance.refreshToken?.trim();
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    final refreshClient = _buildRefreshClient();
    final refreshed = await _refreshWithClient(
      refreshClient,
      {
        'refresh_token': refreshToken,
        'mode': 'json',
      },
    );
    if (!refreshed) {
      return false;
    }

    debugAuthState(label: 'refresh_session_after_workspace_switch_post_refresh');
    final sessionTokenPresent =
        Session.instance.accessToken?.trim().isNotEmpty == true;
    final headerMatchesSession = syncAuthorizationHeaderFromSession();
    return sessionTokenPresent && headerMatchesSession;
  }

  bool syncAuthorizationHeaderFromSession() {
    final token = Session.instance.accessToken?.trim();
    if (token != null && token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
    final headerValue = _dio.options.headers['Authorization']?.toString().trim();
    final headerPresent = headerValue != null && headerValue.isNotEmpty;
    final matchesSession =
        (token != null && token.isNotEmpty) && headerValue == 'Bearer $token';
    debugPrint(
      '[WORKSPACE_SWITCH_AUTH] session_token_present=${token != null && token.isNotEmpty}',
    );
    debugPrint(
      '[WORKSPACE_SWITCH_AUTH] dio_auth_header_present=$headerPresent',
    );
    debugPrint(
      '[WORKSPACE_SWITCH_AUTH] auth_header_matches_session=$matchesSession',
    );
    debugAuthState(label: 'sync_authorization_header_from_session', token: token);
    return matchesSession;
  }

  Future<bool> _performRefresh() async {
    final refreshToken = Session.instance.refreshToken?.trim();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      final ok = await _refreshWithPayload({
        'refresh_token': refreshToken,
        'mode': 'json',
      });
      if (ok) return true;
    }

    // Cookie refresh fallback for environments using refresh cookies.
    final cookieRefresh = await _refreshWithPayload({'mode': 'json'});
    if (cookieRefresh) return true;

    return false;
  }

  Future<bool> _refreshWithPayload(Map<String, dynamic> payload) async {
    try {
      final response = await _dio.post(
        '/auth/refresh',
        data: payload,
        options: Options(
          headers: {'Authorization': null},
          extra: {'skip_auth': true, 'skip_refresh': true},
        ),
      );
      final data = _extractDataMap(response.data);
      final access = data['access_token']?.toString();
      if (access == null || access.isEmpty) return false;

      final refreshed = data['refresh_token']?.toString();
      if (refreshed != null && refreshed.isNotEmpty) {
        await Session.instance.setAuth(
          accessToken: access,
          refreshToken: refreshed,
        );
        syncAuthorizationHeaderFromSession();
      } else {
        await Session.instance.setAuth(accessToken: access);
        syncAuthorizationHeaderFromSession();
      }
      return true;
    } on DioException {
      return false;
    }
  }

  Dio _buildRefreshClient() {
    return Dio(
      BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: _dio.options.connectTimeout,
        receiveTimeout: _dio.options.receiveTimeout,
        sendTimeout: _dio.options.sendTimeout,
      ),
    );
  }

  Future<bool> _refreshWithClient(
    Dio client,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await client.post(
        '/auth/refresh',
        data: payload,
      );
      final data = _extractDataMap(response.data);
      final access = data['access_token']?.toString().trim() ??
          data['token']?.toString().trim();
      if (access == null || access.isEmpty) return false;

      final refreshed = data['refresh_token']?.toString().trim();
      if (refreshed != null && refreshed.isNotEmpty) {
        await Session.instance.setAuth(
          accessToken: access,
          refreshToken: refreshed,
        );
        syncAuthorizationHeaderFromSession();
      } else {
        await Session.instance.setAuth(accessToken: access);
        syncAuthorizationHeaderFromSession();
      }
      return true;
    } on DioException {
      return false;
    }
  }

  Map<String, dynamic> _extractDataMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final nested = raw['data'];
      if (nested is Map<String, dynamic>) return nested;
      return raw;
    }
    return const {};
  }

  void _rotateBaseUrl() {
    if (_baseUrls.length < 2) return;
    _baseIndex = (_baseIndex + 1) % _baseUrls.length;
    _dio.options.baseUrl = _baseUrls[_baseIndex];
  }
}
