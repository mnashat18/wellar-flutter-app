class ScanFailurePresentation {
  final String title;
  final String message;
  final String actionLabel;

  const ScanFailurePresentation({
    required this.title,
    required this.message,
    required this.actionLabel,
  });
}

String scanFailureTitle(String? reason) => _scanFailurePresentation(reason).title;

String scanFailureMessage(String? reason) =>
    _scanFailurePresentation(reason).message;

String scanFailureActionLabel(String? reason) =>
    _scanFailurePresentation(reason).actionLabel;

ScanFailurePresentation scanFailurePresentation(String? reason) =>
    _scanFailurePresentation(reason);

ScanFailurePresentation _scanFailurePresentation(String? reason) {
  switch ((reason ?? '').trim().toLowerCase()) {
    case 'scan_prepare_failed':
      return const ScanFailurePresentation(
        title: 'Scan could not be prepared',
        message:
            'We could not upload or prepare your scan. Please check your connection and try again.',
        actionLabel: 'Try again',
      );
    case 'video_blurry':
      return const ScanFailurePresentation(
        title: 'Video is too blurry',
        message:
            'Your video was not clear enough to analyze. Please retake the scan in better lighting and keep your phone steady.',
        actionLabel: 'Retake scan',
      );
    case 'video_too_dark':
      return const ScanFailurePresentation(
        title: 'Video is too dark',
        message:
            "We couldn't clearly read your face signals. Try again in brighter lighting with your face visible.",
        actionLabel: 'Retake scan',
      );
    case 'video_too_bright':
      return const ScanFailurePresentation(
        title: 'Lighting is too bright',
        message: 'The video is overexposed. Try again with softer lighting.',
        actionLabel: 'Retake scan',
      );
    case 'face_too_far':
      return const ScanFailurePresentation(
        title: 'Face is too far away',
        message:
            'Move a little closer so your face is clearly visible in the frame.',
        actionLabel: 'Retake scan',
      );
    case 'face_too_close':
      return const ScanFailurePresentation(
        title: 'Face is too close',
        message:
            'Move the phone slightly farther away so your full face is visible.',
        actionLabel: 'Retake scan',
      );
    case 'multiple_faces':
      return const ScanFailurePresentation(
        title: 'Multiple faces detected',
        message:
            'Make sure only one face is visible in the frame and try again.',
        actionLabel: 'Retake scan',
      );
    case 'low_quality_media':
      return const ScanFailurePresentation(
        title: 'Media quality is too low',
        message:
            'We could not analyze the scan because the video, audio, or image quality was too low. Please try again with better lighting and less background noise.',
        actionLabel: 'Try again',
      );
    case 'no_face_detected':
      return const ScanFailurePresentation(
        title: 'Face not detected',
        message:
            'We could not clearly detect your face. Please keep your face inside the frame and avoid covering it.',
        actionLabel: 'Retake scan',
      );
    case 'face_not_visible':
      return const ScanFailurePresentation(
        title: 'Face not visible',
        message:
            'Your full face needs to be clearly visible during the scan. Please face the camera directly and try again.',
        actionLabel: 'Retake scan',
      );
    case 'audio_too_quiet':
      return const ScanFailurePresentation(
        title: 'Audio is too quiet',
        message:
            'Your voice was too quiet to analyze. Please speak clearly and keep the phone closer.',
        actionLabel: 'Try again',
      );
    case 'audio_too_short':
      return const ScanFailurePresentation(
        title: 'Audio was too short',
        message:
            'We need a little more speech to analyze your voice. Please try again and read the full sentence clearly.',
        actionLabel: 'Try again',
      );
    case 'no_speech_detected':
      return const ScanFailurePresentation(
        title: 'Voice was not detected',
        message:
            "We couldn't detect enough speech. Try again in a quiet place and speak clearly.",
        actionLabel: 'Try again',
      );
    case 'audio_noisy':
    case 'audio_too_noisy':
      return const ScanFailurePresentation(
        title: 'Too much background noise',
        message:
            'There was too much background noise. Please move to a quieter place and try again.',
        actionLabel: 'Try again',
      );
    case 'phrase_mismatch':
      return const ScanFailurePresentation(
        title: 'Phrase did not match',
        message:
            'The spoken phrase did not match the required sentence. Please read the sentence clearly and try again.',
        actionLabel: 'Try again',
      );
    case 'writeback_failed':
      return const ScanFailurePresentation(
        title: 'Result could not be saved',
        message:
            'Your scan was analyzed, but the result could not be saved. Please try again.',
        actionLabel: 'Try again',
      );
    case 'ai_timeout':
    case 'scan_timeout':
      return const ScanFailurePresentation(
        title: 'Analysis took too long',
        message:
            "We couldn't finish your readiness result right now. Please try again.",
        actionLabel: 'Try again',
      );
    case 'ai_server_error':
    case 'ai_processing_failed':
      return const ScanFailurePresentation(
        title: 'Analysis could not be completed',
        message:
            'We could not complete the readiness analysis right now. Please try again.',
        actionLabel: 'Try again',
      );
    case 'result_not_ready':
      return const ScanFailurePresentation(
        title: 'Result is not ready yet',
        message:
            'Your scan finished uploading, but the readiness result is not available yet. Please try again shortly.',
        actionLabel: 'Try again',
      );
    case 'validation_failed':
      return const ScanFailurePresentation(
        title: 'Scan validation failed',
        message:
            'We could not validate this scan. Please retake it with clear video, clear audio, and good lighting.',
        actionLabel: 'Retake scan',
      );
    default:
      return const ScanFailurePresentation(
        title: 'Scan failed',
        message:
            'Something went wrong while processing your scan. Please try again.',
        actionLabel: 'Try again',
      );
  }
}
