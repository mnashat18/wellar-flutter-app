import 'dart:async';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../utils/safe_debug_log.dart';

import 'scan_service.dart';

typedef ScanPrefocusProgressCallback = void Function(String step);

class ScanFinalizeResult {
  final String scanId;
  final String audioFileId;
  final String videoFileId;
  final String thumbnailFileId;
  final String scanMediaId;

  const ScanFinalizeResult({
    required this.scanId,
    required this.audioFileId,
    required this.videoFileId,
    required this.thumbnailFileId,
    required this.scanMediaId,
  });
}

class ScanPrefinalizeMediaResult {
  final String? videoFileId;
  final String? thumbnailFileId;

  const ScanPrefinalizeMediaResult({
    required this.videoFileId,
    required this.thumbnailFileId,
  });

  bool get hasVideoFile =>
      videoFileId != null && videoFileId!.trim().isNotEmpty;

  bool get hasThumbnailFile =>
      thumbnailFileId != null && thumbnailFileId!.trim().isNotEmpty;
}

class ScanPrepareFailedException implements Exception {
  final String step;
  final Object error;

  const ScanPrepareFailedException({required this.step, required this.error});

  @override
  String toString() => 'ScanPrepareFailedException(step=$step, error=$error)';
}

class ScanFinalizeService {
  ScanFinalizeService._();

  static final ScanFinalizeService instance = ScanFinalizeService._();

  // Match ScanService's mobile video upload window for larger files or slow networks.
  static const Duration _videoUploadTimeout = Duration(minutes: 3);
  static const List<Duration> _processRetryDelays = <Duration>[
    Duration.zero,
    Duration(seconds: 2),
    Duration(seconds: 5),
  ];

  final Map<String, Future<ScanFinalizeResult>> _activeFinalizations = {};
  final Map<String, Future<ScanPrefinalizeMediaResult>>
  _activeMediaPrefinalizations = {};
  final Set<String> _aiProcessRequestedScanIds = <String>{};

  Future<ScanPrefinalizeMediaResult> startMediaPrefinalize({
    required String stagingKey,
    required XFile videoFile,
    required Uint8List thumbnailBytes,
  }) {
    final existing = _activeMediaPrefinalizations[stagingKey];
    if (existing != null) {
      safeDebugLog(
        '[SCAN_PREFINALIZE] duplicate_start ignored has_staging_key=${stagingKey.trim().isNotEmpty}',
      );
      return existing;
    }

    final future = _prefinalizeMedia(
      stagingKey: stagingKey,
      videoFile: videoFile,
      thumbnailBytes: thumbnailBytes,
    );
    _activeMediaPrefinalizations[stagingKey] = future;
    future.whenComplete(() {
      if (identical(_activeMediaPrefinalizations[stagingKey], future)) {
        _activeMediaPrefinalizations.remove(stagingKey);
      }
    });
    return future;
  }

  Future<ScanFinalizeResult> start({
    required String scanId,
    required XFile audioFile,
    required XFile videoFile,
    required Uint8List thumbnailBytes,
    required int durationSeconds,
    String? businessProfileId,
    Future<ScanPrefinalizeMediaResult>? prefinalizedMedia,
    ScanPrefocusProgressCallback? onProgress,
  }) {
    final existing = _activeFinalizations[scanId];
    if (existing != null) {
      safeDebugLog(
        '[SCAN_FINALIZE] duplicate_start ignored has_scan_id=${scanId.trim().isNotEmpty}',
      );
      return existing;
    }

    final future = _finalize(
      scanId: scanId,
      audioFile: audioFile,
      videoFile: videoFile,
      thumbnailBytes: thumbnailBytes,
      durationSeconds: durationSeconds,
      businessProfileId: businessProfileId,
      prefinalizedMedia: prefinalizedMedia,
      onProgress: onProgress,
    );
    _activeFinalizations[scanId] = future;
    future.whenComplete(() {
      if (identical(_activeFinalizations[scanId], future)) {
        _activeFinalizations.remove(scanId);
      }
    });
    return future;
  }

  Future<ScanFinalizeResult> _finalize({
    required String scanId,
    required XFile audioFile,
    required XFile videoFile,
    required Uint8List thumbnailBytes,
    required int durationSeconds,
    String? businessProfileId,
    Future<ScanPrefinalizeMediaResult>? prefinalizedMedia,
    ScanPrefocusProgressCallback? onProgress,
  }) async {
    final totalStopwatch = Stopwatch()..start();
    var currentStep = 'start';
    var slowLogged = false;

    void setStep(String step) {
      currentStep = step;
      onProgress?.call(step);
    }

    void logTiming(String step, Stopwatch stopwatch) {
      safeDebugLog(
        '[SCAN_PREFOCUS_TIMING] step=$step duration_ms=${stopwatch.elapsedMilliseconds}',
      );
    }

    void logSlowIfNeeded() {
      if (slowLogged || totalStopwatch.elapsedMilliseconds <= 5000) return;
      slowLogged = true;
      safeDebugLog(
        '[SCAN_PREFOCUS_SLOW] has_scan_id=${scanId.trim().isNotEmpty} duration_ms=${totalStopwatch.elapsedMilliseconds} current_step=$currentStep',
      );
    }

    safeDebugLog(
      '[SCAN_FINALIZE] start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
    );

    try {
      safeDebugLog(
        '[SCAN_FINALIZE] audio_upload_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      safeDebugLog(
        '[SCAN_FINALIZE] upload_audio_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      setStep('upload_audio');
      final uploadAudioStopwatch = Stopwatch()..start();
      final String audioFileId;
      try {
        safeDebugLog('[SCAN_AUDIO_UPLOAD_INVOKE]');
        audioFileId = await ScanService.instance.uploadXFile(
          audioFile,
          filename: 'scan_audio.m4a',
        );
      } catch (error, stackTrace) {
        _logPrefocusFailure(
          scanId: scanId,
          step: 'upload_audio',
          error: error,
          stackTrace: stackTrace,
        );
        throw ScanPrepareFailedException(step: 'upload_audio', error: error);
      }
      logTiming('upload_audio', uploadAudioStopwatch);
      logSlowIfNeeded();
      safeDebugLog(
        '[SCAN_FINALIZE] upload_audio_success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} has_audio_file_id=${audioFileId.trim().isNotEmpty}',
      );
      safeDebugLog(
        '[SCAN_FLOW] audio_done ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );

      setStep('upload_video');
      final uploadVideoStopwatch = Stopwatch()..start();
      ScanPrefinalizeMediaResult? stagedMedia;
      if (prefinalizedMedia != null) {
        safeDebugLog(
          '[SCAN_FINALIZE] prefinalize_media_wait_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
        );
        try {
          stagedMedia = await prefinalizedMedia;
          safeDebugLog(
            '[SCAN_FINALIZE] prefinalize_media_wait_done ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} video_uploaded=${stagedMedia.hasVideoFile} thumbnail_uploaded=${stagedMedia.hasThumbnailFile}',
          );
        } catch (error) {
          safeDebugLog(
            '[SCAN_FINALIZE] prefinalize_media_wait_failed ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
          );
        }
      }

      safeDebugLog(
        '[SCAN_FINALIZE] upload_video_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      final stagedVideoFileId = stagedMedia?.videoFileId?.trim();
      final String videoFileId;
      if (stagedVideoFileId != null && stagedVideoFileId.isNotEmpty) {
        videoFileId = stagedVideoFileId;
        logTiming('upload_video', uploadVideoStopwatch);
        logSlowIfNeeded();
        safeDebugLog(
          '[SCAN_FINALIZE] upload_video_reused ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} has_video_file_id=${videoFileId.trim().isNotEmpty}',
        );
      } else {
        try {
          safeDebugLog('[SCAN_VIDEO_UPLOAD_INVOKE]');
          videoFileId = await ScanService.instance
              .uploadVideoFile(file: videoFile, scanId: scanId)
              .timeout(_videoUploadTimeout);
          logTiming('upload_video', uploadVideoStopwatch);
          logSlowIfNeeded();
          safeDebugLog(
            '[SCAN_FINALIZE] upload_video_success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} has_video_file_id=${videoFileId.trim().isNotEmpty}',
          );
        } on TimeoutException catch (error, stackTrace) {
          _logPrefocusFailure(
            scanId: scanId,
            step: 'upload_video',
            error: error,
            stackTrace: stackTrace,
          );
          safeDebugLog(
            '[SCAN_FINALIZE] upload_video_failed ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
          );
          throw ScanPrepareFailedException(step: 'upload_video', error: error);
        } catch (error, stackTrace) {
          _logPrefocusFailure(
            scanId: scanId,
            step: 'upload_video',
            error: error,
            stackTrace: stackTrace,
          );
          safeDebugLog(
            '[SCAN_FINALIZE] upload_video_failed ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
          );
          throw ScanPrepareFailedException(step: 'upload_video', error: error);
        }
      }

      safeDebugLog(
        '[SCAN_FINALIZE] upload_thumbnail_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      setStep('upload_thumbnail');
      final uploadThumbnailStopwatch = Stopwatch()..start();
      final stagedThumbnailFileId = stagedMedia?.thumbnailFileId?.trim();
      final String thumbnailFileId;
      if (stagedThumbnailFileId != null && stagedThumbnailFileId.isNotEmpty) {
        thumbnailFileId = stagedThumbnailFileId;
        logTiming('upload_thumbnail', uploadThumbnailStopwatch);
        logSlowIfNeeded();
        safeDebugLog(
          '[SCAN_FINALIZE] upload_thumbnail_reused ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} has_thumbnail_id=${thumbnailFileId.trim().isNotEmpty}',
        );
      } else {
        if (thumbnailBytes.isEmpty) {
          final error = StateError('thumbnail_missing');
          safeDebugLog(
            '[SCAN_FINALIZE] upload_thumbnail_failed ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
          );
          throw ScanPrepareFailedException(
            step: 'upload_thumbnail',
            error: error,
          );
        }
        try {
          safeDebugLog('[SCAN_THUMBNAIL_UPLOAD_INVOKE]');
          thumbnailFileId = await ScanService.instance.uploadBytes(
            thumbnailBytes,
            filename: 'scan_thumb.jpg',
          );
        } catch (error, stackTrace) {
          _logPrefocusFailure(
            scanId: scanId,
            step: 'upload_thumbnail',
            error: error,
            stackTrace: stackTrace,
          );
          throw ScanPrepareFailedException(
            step: 'upload_thumbnail',
            error: error,
          );
        }
        logTiming('upload_thumbnail', uploadThumbnailStopwatch);
        logSlowIfNeeded();
        safeDebugLog(
          '[SCAN_FINALIZE] upload_thumbnail_success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} has_thumbnail_id=${thumbnailFileId.trim().isNotEmpty}',
        );
      }

      safeDebugLog(
        '[SCAN_FINALIZE] create_scan_media_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      setStep('create_scan_media');
      final createScanMediaStopwatch = Stopwatch()..start();
      final scanMediaId = await ScanService.instance.createScanMedia(
        scanId: scanId,
        businessProfileId: businessProfileId,
        videoFileId: videoFileId,
        audioFileId: audioFileId,
        thumbnailFileId: thumbnailFileId,
        durationSeconds: durationSeconds,
      );
      logTiming('create_scan_media', createScanMediaStopwatch);
      logSlowIfNeeded();
      safeDebugLog(
        '[SCAN_FINALIZE] create_scan_media_success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} has_scan_media_id=${scanMediaId.trim().isNotEmpty}',
      );

      safeDebugLog(
        '[SCAN_FINALIZE] patch_media_ready_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      safeDebugLog(
        '[SCAN_FLOW] media_ready_patch_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      setStep('patch_media_ready');
      final patchMediaReadyStopwatch = Stopwatch()..start();
      await ScanService.instance.markWellnessScanMediaReady(scanId: scanId);
      logTiming('patch_media_ready', patchMediaReadyStopwatch);
      logSlowIfNeeded();
      safeDebugLog(
        '[SCAN_FINALIZE] patch_media_ready_success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      safeDebugLog(
        '[SCAN_FLOW] media_ready_patch_success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );

      safeDebugLog(
        '[SCAN_FLOW] process_call_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      setStep('process_accept');
      final processAcceptStopwatch = Stopwatch()..start();
      await _triggerAiProcess(
        scanId,
        audioFileId: audioFileId,
        videoFileId: videoFileId,
      );
      logTiming('process_accept', processAcceptStopwatch);
      logSlowIfNeeded();
      safeDebugLog(
        '[SCAN_FLOW] process_call_accepted ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      safeDebugLog(
        '[SCAN_FINALIZE] success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      safeDebugLog(
        '[SCAN_PREFOCUS_TIMING] total_prefocus_wait_ms=${totalStopwatch.elapsedMilliseconds}',
      );
      logSlowIfNeeded();

      return ScanFinalizeResult(
        scanId: scanId,
        audioFileId: audioFileId,
        videoFileId: videoFileId,
        thumbnailFileId: thumbnailFileId,
        scanMediaId: scanMediaId,
      );
    } catch (error, stackTrace) {
      if (error is UnauthenticatedException) {
        safeDebugLog(
          '[SCAN_FINALIZE] auth_failure ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
        );
        rethrow;
      }
      final prepareError = error is ScanPrepareFailedException
          ? error.error
          : null;
      if (prepareError is UnauthenticatedException) {
        safeDebugLog(
          '[SCAN_FINALIZE] auth_failure ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${prepareError.runtimeType}',
        );
        throw prepareError;
      }
      if (error is! ScanPrepareFailedException) {
        safeDebugLog(
          '[SCAN_FINALIZE] failed ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
        );
      }
      safeDebugLog(
        '[SCAN_FINALIZE] failed_stack ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} stack_present=${stackTrace.toString().isNotEmpty}',
      );
      await _markScanFailed(scanId);
      rethrow;
    }
  }

  void _logPrefocusFailure({
    required String scanId,
    required String step,
    required Object error,
    required StackTrace stackTrace,
  }) {
    safeDebugLog(
      '[SCAN_PREFOCUS_FAILURE] has_scan_id=${scanId.trim().isNotEmpty} step=$step error_type=${error.runtimeType} stack_present=${stackTrace.toString().isNotEmpty}',
    );
  }

  Future<ScanPrefinalizeMediaResult> _prefinalizeMedia({
    required String stagingKey,
    required XFile videoFile,
    required Uint8List thumbnailBytes,
  }) async {
    safeDebugLog(
      '[SCAN_PREFINALIZE] start ts=${DateTime.now().toIso8601String()} has_staging_key=${stagingKey.trim().isNotEmpty}',
    );

    final videoFuture = (() async {
      try {
        safeDebugLog(
          '[SCAN_PREFINALIZE] video_upload_start ts=${DateTime.now().toIso8601String()} has_staging_key=${stagingKey.trim().isNotEmpty}',
        );
        final videoFileId = await ScanService.instance
            .uploadVideoFile(file: videoFile, scanId: stagingKey)
            .timeout(_videoUploadTimeout);
        safeDebugLog(
          '[SCAN_PREFINALIZE] video_upload_success ts=${DateTime.now().toIso8601String()} has_staging_key=${stagingKey.trim().isNotEmpty} has_video_file_id=${videoFileId.trim().isNotEmpty}',
        );
        return videoFileId;
      } catch (error) {
        safeDebugLog(
          '[SCAN_PREFINALIZE] video_upload_failed ts=${DateTime.now().toIso8601String()} has_staging_key=${stagingKey.trim().isNotEmpty} error_type=${error.runtimeType}',
        );
        return null;
      }
    })();

    final thumbnailFuture = (() async {
      try {
        safeDebugLog(
          '[SCAN_PREFINALIZE] thumbnail_upload_start ts=${DateTime.now().toIso8601String()} has_staging_key=${stagingKey.trim().isNotEmpty}',
        );
        if (thumbnailBytes.isEmpty) {
          throw StateError('thumbnail_missing');
        }
        final thumbnailFileId = await ScanService.instance.uploadBytes(
          thumbnailBytes,
          filename: 'scan_thumb.jpg',
        );
        safeDebugLog(
          '[SCAN_PREFINALIZE] thumbnail_upload_success ts=${DateTime.now().toIso8601String()} has_staging_key=${stagingKey.trim().isNotEmpty} has_thumbnail_id=${thumbnailFileId.trim().isNotEmpty}',
        );
        return thumbnailFileId;
      } catch (error) {
        safeDebugLog(
          '[SCAN_PREFINALIZE] thumbnail_upload_failed ts=${DateTime.now().toIso8601String()} has_staging_key=${stagingKey.trim().isNotEmpty} error_type=${error.runtimeType}',
        );
        return null;
      }
    })();

    final results = await Future.wait<String?>([videoFuture, thumbnailFuture]);

    return ScanPrefinalizeMediaResult(
      videoFileId: results[0],
      thumbnailFileId: results[1],
    );
  }

  Future<void> _markScanFailed(String scanId) async {
    try {
      await ScanService.instance.markWellnessScanFailed(
        scanId: scanId,
        failureReason: 'scan_prepare_failed',
      );
      safeDebugLog(
        '[SCAN_FINALIZE] finalize_failure_patch success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} failure_reason=scan_prepare_failed',
      );
    } catch (error) {
      safeDebugLog(
        '[SCAN_FINALIZE] finalize_failure_patch fail ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
      );
    }
  }

  Future<void> _triggerAiProcess(
    String scanId, {
    required String audioFileId,
    required String videoFileId,
  }) async {
    if (_aiProcessRequestedScanIds.contains(scanId)) {
      safeDebugLog(
        '[AI_TRIGGER] process_request_skipped ts=${DateTime.now().toIso8601String()} reason=already_requested has_scan_id=${scanId.trim().isNotEmpty}',
      );
      return;
    }

    for (var attempt = 0; attempt < _processRetryDelays.length; attempt++) {
      if (attempt > 0) {
        await Future.delayed(_processRetryDelays[attempt]);
      }

      try {
        safeDebugLog(
          '[AI_TRIGGER] process_request_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
        );
        final processResponse = await ScanService.instance
            .triggerAiServerProcess(
              scanId: scanId,
              audioFileId: audioFileId,
              videoFileId: videoFileId,
            );
        safeDebugLog(
          '[AI_TRIGGER] process_request_status ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} status=${processResponse.statusCode} body_type=${processResponse.body.runtimeType}',
        );
        if (processResponse.statusCode == 202) {
          _aiProcessRequestedScanIds.add(scanId);
          safeDebugLog(
            '[SCAN_FINALIZE] process_request success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} status=${processResponse.statusCode}',
          );
          return;
        }

        final error = StateError(
          'process_not_accepted:${processResponse.statusCode}',
        );
        safeDebugLog(
          '[AI_TRIGGER] process_request_failed ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
        );
        throw ScanPrepareFailedException(step: 'process_request', error: error);
      } catch (error) {
        final isLastAttempt = attempt == _processRetryDelays.length - 1;
        safeDebugLog(
          '[AI_TRIGGER] process_request_failed ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
        );
        if (error is UnauthenticatedException) {
          rethrow;
        }
        if (error is ScanPrepareFailedException) {
          final prepareError = error.error;
          if (prepareError is UnauthenticatedException) {
            throw prepareError;
          }
          rethrow;
        }
        if (error is! ScanServiceException ||
            !_isRetryableProcessError(error)) {
          throw ScanPrepareFailedException(
            step: 'process_request',
            error: error,
          );
        }
        if (isLastAttempt) {
          throw ScanPrepareFailedException(
            step: 'process_request',
            error: error,
          );
        }
      }
    }
  }

  bool _isRetryableProcessError(ScanServiceException error) {
    if (error.statusCode == null || error.statusCode == 0) return true;
    return error.statusCode! >= 500;
  }
}
