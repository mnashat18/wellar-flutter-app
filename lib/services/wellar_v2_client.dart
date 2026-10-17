import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/wellar_v2_result.dart';
import '../state/session.dart';
import '../utils/safe_debug_log.dart';
import 'directus_client.dart';

class WellarV2ApiException implements Exception {
  final int? statusCode;
  final String code;
  final String message;
  final bool retryable;

  const WellarV2ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.retryable = false,
  });

  @override
  String toString() => message;
}

class WellarV2Feature {
  static bool enabledFor(String? directusUserId) {
    if (!AppConfig.enableWellarV2Scans) return false;
    final id = directusUserId?.trim();
    if (id == null || id.isEmpty) return false;
    final allowed = AppConfig.wellarV2TestUserAllowlist
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    return allowed.contains(id) && configurationError == null;
  }

  static String? get configurationError {
    final uri = Uri.tryParse(AppConfig.wellarV2BaseUrl.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return 'V2 requires a configured HTTPS service URL.';
    }
    return null;
  }
}

/// Direct client for the standalone V2 contract. It never uses Directus auth,
/// Directus models, or a legacy processor endpoint.
class WellarV2Client {
  WellarV2Client({
    required Dio dio,
    required String baseUrl,
    String? bearerToken,
    Future<String?> Function()? tokenProvider,
    Future<bool> Function()? refreshToken,
  }) : _dio = dio,
       _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), ''),
       _staticBearerToken = bearerToken?.trim(),
       _tokenProvider = tokenProvider,
       _refreshToken = refreshToken;

  final Dio _dio;
  final String _baseUrl;
  final String? _staticBearerToken;
  final Future<String?> Function()? _tokenProvider;
  final Future<bool> Function()? _refreshToken;

  factory WellarV2Client.fromSession({Dio? dio}) {
    if (WellarV2Feature.configurationError != null) {
      throw const WellarV2ApiException(
        statusCode: null,
        code: 'v2_not_configured',
        message: 'Wellar AI V2 is not safely configured.',
      );
    }
    return WellarV2Client(
      dio: dio ?? Dio(),
      baseUrl: AppConfig.wellarV2BaseUrl,
      tokenProvider: () async => Session.instance.accessToken,
      refreshToken: DirectusClient.instance.refreshAuthToken,
    );
  }

  static const int maxVideoBytes = 20 * 1024 * 1024;
  static const int maxAudioBytes = 8 * 1024 * 1024;
  static const int maxImageBytes = 5 * 1024 * 1024;
  static const Duration requestTimeout = Duration(seconds: 20);

  Future<String> uploadVideo(Uint8List bytes, {CancelToken? cancelToken}) =>
      _upload('video', bytes, 'video/mp4', cancelToken);

  Future<String> uploadImage(Uint8List bytes, {CancelToken? cancelToken}) =>
      _upload('image', bytes, 'image/jpeg', cancelToken);

  Future<String> uploadAudio(Uint8List bytes, {CancelToken? cancelToken}) =>
      _upload('audio', bytes, 'audio/wav', cancelToken);

  Future<String> _upload(
    String modality,
    Uint8List bytes,
    String contentType,
    CancelToken? cancelToken,
  ) async {
    if (bytes.isEmpty) {
      throw const WellarV2ApiException(
        statusCode: null,
        code: 'empty_media',
        message: 'Captured media is empty. Retake the scan.',
      );
    }
    if (modality == 'video' &&
        (bytes.length > maxVideoBytes || !_isMp4(bytes))) {
      throw const WellarV2ApiException(
        statusCode: null,
        code: 'unsupported_video',
        message:
            'V2 requires a supported MP4 video under 20 MiB. Retake the scan.',
      );
    }
    if (modality == 'image' &&
        (bytes.length > maxImageBytes || !_isJpeg(bytes))) {
      throw const WellarV2ApiException(
        statusCode: null,
        code: 'unsupported_image',
        message: 'V2 requires a supported JPEG image under 5 MiB.',
      );
    }
    if (modality == 'audio' &&
        (bytes.length > maxAudioBytes || !_isWav(bytes))) {
      throw const WellarV2ApiException(
        statusCode: null,
        code: 'unsupported_audio',
        message: 'V2 requires PCM WAV audio under 8 MiB. Retake the scan.',
      );
    }
    try {
      final response = await _send(
        (options) => _dio.post<dynamic>(
          '$_baseUrl/api/v1/media/$modality',
          data: bytes,
          options: options,
          cancelToken: cancelToken,
        ),
        contentType: contentType,
      );
      final body = _map(response.data);
      final ref = body['media_ref']?.toString() ?? '';
      if (response.statusCode != 201 || !_isMediaRef(ref)) {
        throw _parseError(response.statusCode, body);
      }
      _log(
        'media_upload_accepted',
        modality: modality,
        status: response.statusCode,
      );
      return ref;
    } on DioException catch (error) {
      throw _fromDio(error);
    }
  }

  Future<String> submitScan({
    required List<String> mediaRefs,
    bool? mediaProcessingConsent,
    bool? researchUseConsent,
    required String idempotencyKey,
    CancelToken? cancelToken,
  }) async {
    if (idempotencyKey.trim().isEmpty) {
      throw const WellarV2ApiException(
        statusCode: null,
        code: 'idempotency_key_required',
        message: 'Could not create a safe scan request. Please retry.',
      );
    }
    if (mediaRefs.length > 8 ||
        mediaRefs.toSet().length != mediaRefs.length ||
        mediaRefs.any((ref) => !_isMediaRef(ref))) {
      throw const WellarV2ApiException(
        statusCode: null,
        code: 'invalid_media_refs',
        message: 'V2 media references are invalid. Capture the scan again.',
      );
    }
    final payload = <String, dynamic>{
      'schema_version': '1.0',
      'media_refs': mediaRefs,
      'reaction_task': null,
      'consent': {'media_processing': true, 'research_use': false},
    };
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _send(
          (options) => _dio.post<dynamic>(
            '$_baseUrl/api/v1/scans',
            data: payload,
            options: options,
            cancelToken: cancelToken,
          ),
          contentType: 'application/json',
          idempotencyKey: idempotencyKey,
        );
        final body = _map(response.data);
        final scanId = body['scan_id']?.toString() ?? '';
        if (response.statusCode != 202 || scanId.isEmpty) {
          throw _parseError(response.statusCode, body);
        }
        _log('scan_accepted', status: response.statusCode);
        return scanId;
      } on DioException catch (error) {
        final safeError = _fromDio(error);
        if (attempt == 0 &&
            safeError.retryable &&
            !(cancelToken?.isCancelled ?? false)) {
          continue; // Same key and body: server idempotency makes replay safe.
        }
        throw safeError;
      }
    }
    throw const WellarV2ApiException(
      statusCode: null,
      code: 'submission_failed',
      message: 'V2 could not accept the scan.',
    );
  }

  Future<String> fetchStatus(String scanId, {CancelToken? cancelToken}) async {
    final body = await _get(
      '/api/v1/scans/${Uri.encodeComponent(scanId)}',
      cancelToken,
    );
    final status = body['status']?.toString() ?? 'unknown';
    if (!const {
      'queued',
      'processing',
      'completed',
      'failed',
    }.contains(status)) {
      throw const WellarV2ApiException(
        statusCode: null,
        code: 'unexpected_status',
        message: 'V2 returned an unrecognized scan status.',
      );
    }
    return status;
  }

  Future<WellarV2Result> fetchResult(
    String scanId, {
    CancelToken? cancelToken,
  }) async {
    final body = await _get(
      '/api/v1/scans/${Uri.encodeComponent(scanId)}/result',
      cancelToken,
    );
    final result = WellarV2Result.fromJson(body);
    if (result.schemaVersion != '2.0' ||
        result.scanId != scanId ||
        !const {
          'insufficient_evidence',
          'model_unavailable',
        }.contains(result.status) ||
        result.modelVersion != null ||
        result.modelInvocationStatus != 'not_invoked_no_validated_model' ||
        result.targets.values.any((target) => target.value != null)) {
      throw const WellarV2ApiException(
        statusCode: null,
        code: 'invalid_result_schema',
        message: 'V2 returned a result this app cannot safely display.',
      );
    }
    return result;
  }

  Future<void> deleteMedia(String mediaRef, {CancelToken? cancelToken}) async {
    try {
      final response = await _send(
        (options) => _dio.delete<dynamic>(
          '$_baseUrl/api/v1/media',
          queryParameters: {'media_ref': mediaRef},
          options: options,
          cancelToken: cancelToken,
        ),
        contentType: 'application/json',
      );
      if (response.statusCode != 204) {
        throw _parseError(response.statusCode, _map(response.data));
      }
      _log('media_cleanup_completed', status: 204);
    } on DioException catch (error) {
      throw _fromDio(error);
    }
  }

  Future<Map<String, dynamic>> _get(
    String path,
    CancelToken? cancelToken,
  ) async {
    try {
      final response = await _send(
        (options) => _dio.get<dynamic>(
          '$_baseUrl$path',
          options: options,
          cancelToken: cancelToken,
        ),
        contentType: 'application/json',
      );
      if (response.statusCode != 200) {
        throw _parseError(response.statusCode, _map(response.data));
      }
      return _map(response.data);
    } on DioException catch (error) {
      throw _fromDio(error);
    }
  }

  Future<Response<dynamic>> _send(
    Future<Response<dynamic>> Function(Options options) request, {
    required String contentType,
    String? idempotencyKey,
  }) async {
    final token = await _currentToken();
    if (token == null || token.isEmpty) {
      throw const WellarV2ApiException(
        statusCode: null,
        code: 'v2_auth_missing',
        message: 'Sign in again before starting a V2 scan.',
      );
    }
    try {
      return await request(_options(contentType, token, idempotencyKey));
    } on DioException catch (error) {
      if (error.response?.statusCode != 401 || _refreshToken == null) rethrow;
      final refreshed = await _refreshToken!();
      final retryToken = refreshed ? await _currentToken() : null;
      if (retryToken == null || retryToken.isEmpty) rethrow;
      // Exactly one retry follows the existing Directus refresh path.
      return request(_options(contentType, retryToken, idempotencyKey));
    }
  }

  Future<String?> _currentToken() async =>
      (await _tokenProvider?.call() ?? _staticBearerToken)?.trim();

  Options _options(String contentType, String token, String? idempotencyKey) =>
      Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': contentType,
          if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
        },
        followRedirects: false,
        connectTimeout: requestTimeout,
        sendTimeout: requestTimeout,
        receiveTimeout: requestTimeout,
      );

  WellarV2ApiException _fromDio(DioException error) {
    final status = error.response?.statusCode;
    final body = _map(error.response?.data);
    if (status == 401 || status == 403) {
      return WellarV2ApiException(
        statusCode: status,
        code: 'v2_auth_rejected',
        message:
            'V2 rejected the configured local identity. Check its synthetic scope.',
      );
    }
    if (status == 404 && body['code']?.toString() == 'result_unavailable') {
      return const WellarV2ApiException(
        statusCode: 404,
        code: 'result_unavailable',
        message: 'V2 has not published the result yet.',
        retryable: true,
      );
    }
    final retryable =
        status == null || status >= 500 || status == 429 || status == 408;
    return _parseError(status, body, retryable: retryable);
  }

  WellarV2ApiException _parseError(
    int? status,
    Map<String, dynamic> body, {
    bool retryable = false,
  }) {
    final error = body['error'];
    final detail = body['detail'];
    final source = error is Map
        ? error
        : detail is Map
        ? detail
        : const {};
    final code = source['code']?.toString() ?? 'v2_request_failed';
    if (status == 401 || status == 403) {
      return WellarV2ApiException(
        statusCode: status,
        code: 'v2_auth_rejected',
        message:
            'V2 rejected the configured local identity. Check its synthetic scope.',
      );
    }
    if (status == 404 && code == 'result_unavailable') {
      return const WellarV2ApiException(
        statusCode: 404,
        code: 'result_unavailable',
        message: 'V2 has not published the result yet.',
        retryable: true,
      );
    }
    // Never surface backend body text or exception details: they can contain
    // identifiers, paths or implementation information.
    final safeCode = code.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return WellarV2ApiException(
      statusCode: status,
      code: safeCode.substring(0, min(48, safeCode.length)),
      message: status != null && status >= 500
          ? 'V2 could not complete the request. Retry later.'
          : switch (status) {
              400 || 415 || 422 =>
                'V2 rejected the media or scan request. Check format and consent.',
              404 => 'V2 could not find the requested scan or media.',
              409 => 'V2 detected a conflicting repeated scan submission.',
              413 => 'Media exceeds the V2 service size limit.',
              429 => 'V2 is temporarily at capacity. Wait and retry.',
              _ => 'The local V2 request failed. Check the service and retry.',
            },
      retryable: retryable,
    );
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    // Dio may decode JSON using a Map implementation whose generic type is
    // Map<dynamic, dynamic>. Normalize only string keys so malformed error
    // bodies cannot escape the sanitized API error path with a cast failure.
    return <String, dynamic>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static bool _isMp4(Uint8List bytes) =>
      bytes.length >= 12 && String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp';

  static bool _isJpeg(Uint8List bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff;

  static bool _isMediaRef(String value) => RegExp(
    r'^media://[A-Za-z0-9_-]{1,64}/[A-Fa-f0-9-]{16,128}$',
  ).hasMatch(value);

  static bool _isWav(Uint8List bytes) {
    if (bytes.length < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      return false;
    }
    final view = ByteData.sublistView(bytes);
    var offset = 12;
    int? encoding;
    int? bitsPerSample;
    while (offset + 8 <= bytes.length) {
      final chunk = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final length = view.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (length > bytes.length - body) return false;
      if (chunk == 'fmt ' && length >= 16) {
        encoding = view.getUint16(body, Endian.little);
        bitsPerSample = view.getUint16(body + 14, Endian.little);
      }
      if (chunk == 'data') break;
      offset = body + length + (length.isOdd ? 1 : 0);
    }
    return encoding == 1 && bitsPerSample == 16;
  }

  static String newIdempotencyKey() {
    final random = Random.secure();
    return List<int>.generate(
      32,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static void _log(String event, {String? modality, int? status}) {
    safeDebugLog(
      '[WELLAR_V2] event=$event${modality == null ? '' : ' modality=$modality'}${status == null ? '' : ' status=$status'}',
    );
  }
}
