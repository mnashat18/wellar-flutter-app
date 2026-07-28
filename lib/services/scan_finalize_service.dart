import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

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
      debugPrint(
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
      debugPrint(
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
      debugPrint(
        '[SCAN_PREFOCUS_TIMING] step=$step duration_ms=${stopwatch.elapsedMilliseconds}',
      );
    }

    void logSlowIfNeeded() {
      if (slowLogged || totalStopwatch.elapsedMilliseconds <= 5000) return;
      slowLogged = true;
      debugPrint(
        '[SCAN_PREFOCUS_SLOW] has_scan_id=${scanId.trim().isNotEmpty} duration_ms=${totalStopwatch.elapsedMilliseconds} current_step=$currentStep',
      );
    }

    debugPrint(
      '[SCAN_FINALIZE] start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
    );

    try {
      debugPrint(
        '[SCAN_FINALIZE] audio_upload_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      debugPrint(
        '[SCAN_FINALIZE] upload_audio_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      setStep('upload_audio');
      final uploadAudioStopwatch = Stopwatch()..start();
      final String audioFileId;
      try {
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
      debugPrint(
        '[SCAN_FINALIZE] upload_audio_success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} has_audio_file_id=${audioFileId.trim().isNotEmpty}',
      );
      debugPrint(
        '[SCAN_FLOW] audio_done ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );

      setStep('upload_video');
      final uploadVideoStopwatch = Stopwatch()..start();
      ScanPrefinalizeMediaResult? stagedMedia;
      if (prefinalizedMedia != null) {
        debugPrint(
          '[SCAN_FINALIZE] prefinalize_media_wait_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
        );
        try {
          stagedMedia = await prefinalizedMedia;
          debugPrint(
            '[SCAN_FINALIZE] prefinalize_media_wait_done ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} video_uploaded=${stagedMedia.hasVideoFile} thumbnail_uploaded=${stagedMedia.hasThumbnailFile}',
          );
        } catch (error) {
          debugPrint(
            '[SCAN_FINALIZE] prefinalize_media_wait_failed ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
          );
        }
      }

      debugPrint(
        '[SCAN_FINALIZE] upload_video_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      final stagedVideoFileId = stagedMedia?.videoFileId?.trim();
      final String videoFileId;
      if (stagedVideoFileId != null && stagedVideoFileId.isNotEmpty) {
        videoFileId = stagedVideoFileId;
        logTiming('upload_video', uploadVideoStopwatch);
        logSlowIfNeeded();
        debugPrint(
          '[SCAN_FINALIZE] upload_video_reused ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} has_video_file_id=${videoFileId.trim().isNotEmpty}',
        );
      } else {
        try {
          videoFileId = await ScanService.instance
              .uploadVideoFile(file: videoFile, scanId: scanId)
              .timeout(_videoUploadTimeout);
          logTiming('upload_video', uploadVideoStopwatch);
          logSlowIfNeeded();
          debugPrint(
            '[SCAN_FINALIZE] upload_video_success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} has_video_file_id=${videoFileId.trim().isNotEmpty}',
          );
        } on TimeoutException catch (error, stackTrace) {
          _logPrefocusFailure(
            scanId: scanId,
            step: 'upload_video',
            error: error,
            stackTrace: stackTrace,
          );
          debugPrint(
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
          debugPrint(
            '[SCAN_FINALIZE] upload_video_failed ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
          );
          throw ScanPrepareFailedException(step: 'upload_video', error: error);
        }
      }

      debugPrint(
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
        debugPrint(
          '[SCAN_FINALIZE] upload_thumbnail_reused ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} has_thumbnail_id=${thumbnailFileId.trim().isNotEmpty}',
        );
      } else {
        if (thumbnailBytes.isEmpty) {
          final error = StateError('thumbnail_missing');
          debugPrint(
            '[SCAN_FINALIZE] upload_thumbnail_failed ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
          );
          throw ScanPrepareFailedException(
            step: 'upload_thumbnail',
            error: error,
          );
        }
        try {
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
        debugPrint(
          '[SCAN_FINALIZE] upload_thumbnail_success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} has_thumbnail_id=${thumbnailFileId.trim().isNotEmpty}',
        );
      }

      debugPrint(
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
      debugPrint(
        '[SCAN_FINALIZE] create_scan_media_success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} has_scan_media_id=${scanMediaId.trim().isNotEmpty}',
      );

      debugPrint(
        '[SCAN_FINALIZE] patch_media_ready_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      debugPrint(
        '[SCAN_FLOW] media_ready_patch_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      setStep('patch_media_ready');
      final patchMediaReadyStopwatch = Stopwatch()..start();
      await ScanService.instance.markWellnessScanMediaReady(scanId: scanId);
      logTiming('patch_media_ready', patchMediaReadyStopwatch);
      logSlowIfNeeded();
      debugPrint(
        '[SCAN_FINALIZE] patch_media_ready_success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      debugPrint(
        '[SCAN_FLOW] media_ready_patch_success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );

      debugPrint(
        '[SCAN_FLOW] process_call_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      setStep('process_accept');
      final processAcceptStopwatch = Stopwatch()..start();
      await _triggerAiProcess(scanId);
      logTiming('process_accept', processAcceptStopwatch);
      logSlowIfNeeded();
      debugPrint(
        '[SCAN_FLOW] process_call_accepted ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      debugPrint(
        '[SCAN_FINALIZE] success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
      );
      debugPrint(
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
        debugPrint(
          '[SCAN_FINALIZE] auth_failure ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
        );
        rethrow;
      }
      final prepareError = error is ScanPrepareFailedException
          ? error.error
          : null;
      if (prepareError is UnauthenticatedException) {
        debugPrint(
          '[SCAN_FINALIZE] auth_failure ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${prepareError.runtimeType}',
        );
        throw prepareError;
      }
      if (error is! ScanPrepareFailedException) {
        debugPrint(
          '[SCAN_FINALIZE] failed ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
        );
      }
      debugPrint(
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
    debugPrint(
      '[SCAN_PREFOCUS_FAILURE] has_scan_id=${scanId.trim().isNotEmpty} step=$step error_type=${error.runtimeType} stack_present=${stackTrace.toString().isNotEmpty}',
    );
  }

  Future<ScanPrefinalizeMediaResult> _prefinalizeMedia({
    required String stagingKey,
    required XFile videoFile,
    required Uint8List thumbnailBytes,
  }) async {
    debugPrint(
      '[SCAN_PREFINALIZE] start ts=${DateTime.now().toIso8601String()} has_staging_key=${stagingKey.trim().isNotEmpty}',
    );

    final videoFuture = (() async {
      try {
        debugPrint(
          '[SCAN_PREFINALIZE] video_upload_start ts=${DateTime.now().toIso8601String()} has_staging_key=${stagingKey.trim().isNotEmpty}',
        );
        final videoFileId = await ScanService.instance
            .uploadVideoFile(file: videoFile, scanId: stagingKey)
            .timeout(_videoUploadTimeout);
        debugPrint(
          '[SCAN_PREFINALIZE] video_upload_success ts=${DateTime.now().toIso8601String()} has_staging_key=${stagingKey.trim().isNotEmpty} has_video_file_id=${videoFileId.trim().isNotEmpty}',
        );
        return videoFileId;
      } catch (error) {
        debugPrint(
          '[SCAN_PREFINALIZE] video_upload_failed ts=${DateTime.now().toIso8601String()} has_staging_key=${stagingKey.trim().isNotEmpty} error_type=${error.runtimeType}',
        );
        return null;
      }
    })();

    final thumbnailFuture = (() async {
      try {
        debugPrint(
          '[SCAN_PREFINALIZE] thumbnail_upload_start ts=${DateTime.now().toIso8601String()} has_staging_key=${stagingKey.trim().isNotEmpty}',
        );
        if (thumbnailBytes.isEmpty) {
          throw StateError('thumbnail_missing');
        }
        final thumbnailFileId = await ScanService.instance.uploadBytes(
          thumbnailBytes,
          filename: 'scan_thumb.jpg',
        );
        debugPrint(
          '[SCAN_PREFINALIZE] thumbnail_upload_success ts=${DateTime.now().toIso8601String()} has_staging_key=${stagingKey.trim().isNotEmpty} has_thumbnail_id=${thumbnailFileId.trim().isNotEmpty}',
        );
        return thumbnailFileId;
      } catch (error) {
        debugPrint(
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
      debugPrint(
        '[SCAN_FINALIZE] finalize_failure_patch success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} failure_reason=scan_prepare_failed',
      );
    } catch (error) {
      debugPrint(
        '[SCAN_FINALIZE] finalize_failure_patch fail ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
      );
    }
  }

  Future<void> _triggerAiProcess(String scanId) async {
    if (_aiProcessRequestedScanIds.contains(scanId)) {
      debugPrint(
        '[AI_TRIGGER] process_request_skipped ts=${DateTime.now().toIso8601String()} reason=already_requested has_scan_id=${scanId.trim().isNotEmpty}',
      );
      return;
    }

    for (var attempt = 0; attempt < _processRetryDelays.length; attempt++) {
      if (attempt > 0) {
        await Future.delayed(_processRetryDelays[attempt]);
      }

      try {
        debugPrint(
          '[AI_TRIGGER] process_request_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty}',
        );
        final processResponse = await ScanService.instance
            .triggerAiServerProcess(scanId: scanId);
        debugPrint(
          '[AI_TRIGGER] process_request_status ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} status=${processResponse.statusCode} body_type=${processResponse.body.runtimeType}',
        );
        if (processResponse.statusCode == 202) {
          _aiProcessRequestedScanIds.add(scanId);
          debugPrint(
            '[SCAN_FINALIZE] process_request success ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} status=${processResponse.statusCode}',
          );
          return;
        }

        final error = StateError(
          'process_not_accepted:${processResponse.statusCode}',
        );
        debugPrint(
          '[AI_TRIGGER] process_request_failed ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} error_type=${error.runtimeType}',
        );
        throw ScanPrepareFailedException(step: 'process_request', error: error);
      } catch (error) {
        final isLastAttempt = attempt == _processRetryDelays.length - 1;
        debugPrint(
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
