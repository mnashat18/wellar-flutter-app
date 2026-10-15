import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/wellar_v2_result.dart';
import '../services/wellar_v2_client.dart';
import 'wellar_v2_result_screen.dart';

class WellarV2ProcessingScreen extends StatefulWidget {
  const WellarV2ProcessingScreen({
    super.key,
    required this.videoFile,
    required this.audioFile,
    this.imageBytes,
  });

  final XFile videoFile;
  final XFile audioFile;
  final Uint8List? imageBytes;

  @override
  State<WellarV2ProcessingScreen> createState() =>
      _WellarV2ProcessingScreenState();
}

class _WellarV2ProcessingScreenState extends State<WellarV2ProcessingScreen> {
  late final CancelToken _cancelToken = CancelToken();
  late final WellarV2Client _client;
  final List<String> _uploadedRefs = [];
  String _message = 'Preparing compatible local media…';
  bool _accepted = false;
  bool _submissionOutcomeUnknown = false;
  bool _terminalReached = false;
  bool _finished = false;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    try {
      _client = WellarV2Client.fromSession();
      unawaited(_run());
    } on WellarV2ApiException catch (error) {
      _finished = true;
      _message = error.message;
    }
  }

  @override
  void dispose() {
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel('V2 scan screen closed');
    }
    super.dispose();
  }

  Future<void> _run() async {
    try {
      _setMessage('Checking captured MP4 and WAV media…');
      final videoLength = await File(widget.videoFile.path).length();
      final audioLength = await File(widget.audioFile.path).length();
      final imageBytes = widget.imageBytes ?? Uint8List(0);
      if (imageBytes.length > WellarV2Client.maxImageBytes ||
          videoLength > WellarV2Client.maxVideoBytes ||
          audioLength > WellarV2Client.maxAudioBytes) {
        throw const WellarV2ApiException(
          statusCode: 413,
          code: 'media_too_large',
          message:
              'Captured media exceeds the supported local V2 size limit. Retake the scan.',
        );
      }
      final video = await File(widget.videoFile.path).readAsBytes();
      final audio = await File(widget.audioFile.path).readAsBytes();
      if (_cancelToken.isCancelled) return;

      _setMessage('Uploading video to local Wellar AI V2…');
      _uploadedRefs.add(
        await _client.uploadImage(imageBytes, cancelToken: _cancelToken),
      );
      _uploadedRefs.add(
        await _client.uploadVideo(video, cancelToken: _cancelToken),
      );
      _setMessage('Uploading WAV audio to local Wellar AI V2…');
      _uploadedRefs.add(
        await _client.uploadAudio(audio, cancelToken: _cancelToken),
      );

      _setMessage('Submitting consented V2 scan…');
      final idempotencyKey = WellarV2Client.newIdempotencyKey();
      String scanId;
      try {
        scanId = await _client.submitScan(
          mediaRefs: List.unmodifiable(_uploadedRefs),
          idempotencyKey: idempotencyKey,
          cancelToken: _cancelToken,
        );
      } on WellarV2ApiException catch (error) {
        _submissionOutcomeUnknown =
            error.statusCode == null ||
            error.statusCode! >= 500 ||
            error.statusCode == 429 ||
            error.statusCode == 408;
        rethrow;
      }
      _accepted = true;
      _setMessage('V2 accepted the scan. Waiting for the local worker…');
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      WellarV2Result? result;
      while (DateTime.now().isBefore(deadline)) {
        if (_cancelToken.isCancelled) return;
        final status = await _client.fetchStatus(
          scanId,
          cancelToken: _cancelToken,
        );
        if (status == 'queued') {
          _setMessage('Status: queued. Waiting for a V2 worker…');
        } else if (status == 'processing') {
          _setMessage('Status: running. V2 is processing the scan…');
        }
        if (status == 'failed') {
          _terminalReached = true;
          _setMessage('Status: failed. V2 could not complete this scan.');
          throw const WellarV2ApiException(
            statusCode: null,
            code: 'scan_failed',
            message: 'The local V2 worker reported a terminal failure.',
          );
        }
        if (status == 'completed') {
          _terminalReached = true;
          _setMessage('Status: completed. Retrieving the V2 result…');
          try {
            result = await _client.fetchResult(
              scanId,
              cancelToken: _cancelToken,
            );
            break;
          } on WellarV2ApiException catch (error) {
            if (error.code != 'result_unavailable') rethrow;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      if (result == null) {
        throw const WellarV2ApiException(
          statusCode: null,
          code: 'poll_timeout',
          message:
              'Timed out waiting for a local V2 result. The scan may still be processing.',
          retryable: true,
        );
      }
      await _cleanupMedia();
      if (!mounted) return;
      setState(() => _finished = true);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => WellarV2ResultScreen(result: result!),
        ),
      );
    } on DioException catch (_) {
      _fail(
        'The local V2 request was interrupted. Check the service and network.',
      );
    } on WellarV2ApiException catch (error) {
      if (error.code == 'result_unavailable') {
        _fail(
          'V2 accepted the scan but has not published a result. Keep the local worker running and retry later.',
        );
      } else {
        _fail(error.message);
      }
    } on FileSystemException catch (_) {
      _fail('Captured media is no longer available. Retake the scan.');
    } catch (_) {
      _fail(
        'The local V2 scan could not be completed. Check the service and retake if needed.',
      );
    } finally {
      // If submission was never accepted, uploaded refs are not worker inputs
      // and may be removed immediately. Once accepted, media must remain until
      // terminal processing; V2 retention is the fallback after cancellation.
      if ((!_accepted && !_submissionOutcomeUnknown) || _terminalReached) {
        await _cleanupMedia();
      }
    }
  }

  Future<void> _cleanupMedia() async {
    final refs = List<String>.of(_uploadedRefs).reversed.toList();
    _uploadedRefs.clear();
    for (final ref in refs) {
      try {
        await _client.deleteMedia(ref);
      } catch (_) {
        // Do not expose media references or server error details in UI/logs.
      }
    }
  }

  void _setMessage(String message) {
    if (mounted) setState(() => _message = message);
  }

  void _fail(String message) {
    if (!mounted || _cancelled) return;
    setState(() {
      _message = message;
      _finished = true;
    });
  }

  void _cancel() {
    _cancelled = true;
    _cancelToken.cancel('User cancelled local V2 wait');
    // The API has no scan-cancel route. An already accepted job may continue;
    // its media is retained for the worker and then governed by V2 retention.
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Local V2 scan'),
      leading: IconButton(
        tooltip: 'Cancel',
        onPressed: _finished ? () => Navigator.of(context).pop() : _cancel,
        icon: const Icon(Icons.close),
      ),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_finished) const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(_message, textAlign: TextAlign.center),
            if (_finished) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Return'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
