import 'package:flutter/foundation.dart';
import 'package:video_compress/video_compress.dart';
import 'package:image_picker/image_picker.dart';

final IVideoCompress _compressor = VideoCompress;
const int _targetBitrate = 3500000;
const int _targetFrameRate = 30;
const String _targetResolution = '1280x720';
const int _maxUploadBytesWithoutRecompress = 5 * 1024 * 1024;

Future<XFile> compressVideoImpl(XFile file) async {
  final stopwatch = Stopwatch()..start();
  try {
    final originalSize = await file.length();
    final mediaInfo = await _compressor.getMediaInfo(file.path);
    final sourceWidth = mediaInfo.width ?? 0;
    final sourceHeight = mediaInfo.height ?? 0;
    debugPrint('[ScanVideo] original video path=${file.path}');
    debugPrint('[ScanVideo] original video file size=$originalSize');
    debugPrint(
      '[ScanVideo] original video resolution=${sourceWidth}x$sourceHeight orientation=${mediaInfo.orientation}',
    );
    debugPrint('[ScanVideo] selected output resolution=$_targetResolution');
    debugPrint('[ScanVideo] selected bitrate=$_targetBitrate');
    debugPrint('[ScanVideo] selected fps=$_targetFrameRate');

    final isMp4Source = file.path.toLowerCase().endsWith('.mp4');
    final hasValidDuration =
        mediaInfo.duration != null && mediaInfo.duration! > 0;
    final codecCompatible = isMp4Source;
    final meetsTargetResolution = sourceWidth > 0 &&
        sourceHeight > 0 &&
        sourceWidth <= 1280 &&
        sourceHeight <= 720;
    final meetsTargetFileSize = originalSize <= _maxUploadBytesWithoutRecompress;
    if (codecCompatible &&
        hasValidDuration &&
        meetsTargetResolution &&
        meetsTargetFileSize) {
      stopwatch.stop();
      debugPrint(
        '[SCAN_VIDEO] compression skipped '
        'reason=already_within_upload_profile '
        'original_size=$originalSize '
        'resolution=${sourceWidth}x$sourceHeight '
        'duration_ms=${stopwatch.elapsedMilliseconds}',
      );
      return file;
    }

    final info = await _compressor.compressVideo(
      file.path,
      quality: VideoQuality.Res1280x720Quality,
      includeAudio: false,
      deleteOrigin: false,
      frameRate: _targetFrameRate,
    );
    stopwatch.stop();
    if (info == null || info.path == null) {
      debugPrint(
        '[SCAN_VIDEO] compression failed '
        'reason=no_output '
        'original_size=$originalSize '
        'source_path=${file.path} '
        'duration_ms=${stopwatch.elapsedMilliseconds}',
      );
      return file;
    }
    final compressed = XFile(info.path!);
    final compressedSize = await compressed.length();
    final outputWidth = info.width ?? 1280;
    final outputHeight = info.height ?? 720;
    debugPrint('[SCAN_VIDEO] compression performed');
    debugPrint('[SCAN_VIDEO] compressed video path=${compressed.path}');
    debugPrint('[SCAN_VIDEO] original_size=$originalSize');
    debugPrint('[SCAN_VIDEO] processed_size=$compressedSize');
    debugPrint('[SCAN_VIDEO] output_resolution=${outputWidth}x$outputHeight');
    debugPrint('[SCAN_VIDEO] bitrate=$_targetBitrate');
    debugPrint('[SCAN_VIDEO] fps=$_targetFrameRate');
    debugPrint(
      '[SCAN_VIDEO] compression duration_ms=${stopwatch.elapsedMilliseconds}',
    );
    return compressed;
  } catch (error) {
    stopwatch.stop();
    debugPrint(
      '[SCAN_VIDEO] compression failed '
      'path=${file.path} '
      'error=$error '
      'duration_ms=${stopwatch.elapsedMilliseconds}',
    );
    return file;
  }
}
