import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_thumbnail_video/src/image_format.dart' as thumb;
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/request_service.dart';
import '../services/scan_finalize_service.dart';
import '../services/scan_service.dart';
import '../state/app_providers.dart';
import '../services/organization_service.dart';
import '../models/scan_result.dart';
import '../utils/page_transition.dart';
import '../utils/scan_result_polling_policy.dart';
import '../utils/video_compress.dart';
import 'scan/scan_premium_components.dart';
import 'scan_details_screen.dart';

enum ScanFlowStep { intro, consent, permissions, video, audio, focus }

enum ScanStage { overview, consent, permissions, facial, voice, focus }

enum _PostFocusTerminalState { none, failure, pending }

class _WorkflowTerminalResult {
  final ScanFinalizeResult? result;
  final Object? error;
  final StackTrace? stackTrace;

  const _WorkflowTerminalResult.success(this.result)
    : error = null,
      stackTrace = null;

  const _WorkflowTerminalResult.failure(this.error, this.stackTrace)
    : result = null;

  bool get isSuccess => result != null && error == null;
}

class _StageMeta {
  final String headerLabel;
  final int? step;
  final int? totalSteps;

  const _StageMeta({required this.headerLabel, this.step, this.totalSteps});
}

class ScanFlowScreen extends StatefulWidget {
  final String? requestId;
  final bool forceCompletion;

  const ScanFlowScreen({
    super.key,
    this.requestId,
    this.forceCompletion = false,
  });

  @override
  State<ScanFlowScreen> createState() => _ScanFlowScreenState();
}

class _ScanFlowScreenState extends State<ScanFlowScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const int _videoSeconds = 5;
  static const int _audioSeconds = 5;
  static const int _focusDuration = 15;
  static const Duration _maxPostFocusWait = Duration(seconds: 45);
  static const Duration _postFocusFinalizeWait = Duration(seconds: 10);
  static const Duration _postFocusResolveWindow = Duration(seconds: 12);
  static const ScanResultPollingPolicy _postFocusPollingPolicy =
      ScanResultPollingPolicy();
  static const ResolutionPreset _capturePreset = ResolutionPreset.veryHigh;
  static const int _targetFrameRate = 30;
  static const int _targetBitrate = 3500000;
  static const String _targetResolution = '1280x720';

  final AudioRecorder _recorder = AudioRecorder();
  CameraController? _cameraController;

  ScanFlowStep _step = ScanFlowStep.intro;
  bool _initializing = true;
  bool _fatalError = false;
  bool _finalizeFailed = false;
  String? _fatalMessage;
  String? _finalizeFailureMessage;
  String? _finalizeFailureTitle;
  bool _consentAccepted = false;
  bool _cameraPermissionReady = false;
  bool _microphonePermissionReady = false;
  bool _permissionsReady = false;
  bool _videoRecording = false;
  bool _videoStopInProgress = false;
  bool _videoAutoAdvanced = false;
  bool _videoPreparationInProgress = false;
  bool _videoPreparationFailed = false;
  bool _audioRecording = false;
  bool _audioAutoStopInProgress = false;
  bool _audioAutoAdvanced = false;
  bool _audioPermissionRequestInProgress = false;
  bool _submitting = false;
  bool _preparingProcess = false;
  bool _focusActive = false;
  bool _focusDone = false;
  bool _scanFinished = false;
  bool _workflowStarted = false;
  String? _scanId;
  DateTime? _focusShellVisibleAt;
  String _currentFinalizeStep = 'not_started';
  XFile? _videoFile;
  XFile? _audioFile;
  Uint8List? _thumbnailBytes;
  int _videoSecondsLeft = _videoSeconds;
  int _audioSecondsElapsed = 0;
  int _focusSecondsLeft = _focusDuration;
  int _focusScore = 0;
  int _activeTileIndex = 4;
  String _permissionHint = '';
  String? _videoFailureMessage;
  String? _audioFailureMessage;
  Timer? _videoTimer;
  Timer? _audioTimer;
  Timer? _captureGapTimer;
  Timer? _focusTimer;
  Timer? _statusPulseTimer;
  double _statusPhase = 0;
  Future<void>? _videoPreparationFuture;
  Future<_WorkflowTerminalResult>? _workflowFuture;
  Future<ScanPrefinalizeMediaResult>? _prefinalizedMediaFuture;
  bool _workflowSettled = false;
  Object? _backgroundFinalizeFailure;
  StackTrace? _backgroundFinalizeFailureStack;
  _PostFocusTerminalState _postFocusTerminalState =
      _PostFocusTerminalState.none;
  String? _postFocusFailureReason;
  String? _postFocusTimeoutTitle;
  String? _postFocusTimeoutMessage;
  int _videoPreparationVersion = 0;
  int _postFocusResolutionVersion = 0;
  DateTime? _videoStartedAt;
  DateTime? _videoCompletedAt;
  DateTime? _audioStepOpenedAt;
  DateTime? _audioStartedAt;
  DateTime? _audioCompletedAt;
  bool _captureSessionInvalidated = false;
  String? _captureInvalidationReason;
  String? _captureInvalidationMessage;

  ScanStage get _stage {
    return switch (_step) {
      ScanFlowStep.intro => ScanStage.overview,
      ScanFlowStep.consent => ScanStage.consent,
      ScanFlowStep.permissions => ScanStage.permissions,
      ScanFlowStep.video => ScanStage.facial,
      ScanFlowStep.audio => ScanStage.voice,
      ScanFlowStep.focus => ScanStage.focus,
    };
  }

  _StageMeta get _stageMeta => switch (_stage) {
    ScanStage.overview => const _StageMeta(headerLabel: 'Start check-in'),
    ScanStage.consent => const _StageMeta(headerLabel: 'Privacy and consent'),
    ScanStage.permissions => const _StageMeta(headerLabel: 'Permissions check'),
    ScanStage.facial => const _StageMeta(
      headerLabel: 'Camera check',
      step: 1,
      totalSteps: 3,
    ),
    ScanStage.voice => const _StageMeta(
      headerLabel: 'Voice check',
      step: 2,
      totalSteps: 3,
    ),
    ScanStage.focus => const _StageMeta(
      headerLabel: 'Focus task',
      step: 3,
      totalSteps: 3,
    ),
  };

  String _currentRouteName() {
    final route = ModalRoute.of(context);
    final name = route?.settings.name?.trim();
    if (name != null && name.isNotEmpty) return name;
    return route?.runtimeType.toString() ?? 'ScanFlowScreen';
  }

  void _devLog(String tag, String message) {
    if (!kDebugMode) return;
    debugPrint('[$tag] ${_redactDecisionLog(message)}');
  }

  String _redactDecisionLog(String message) {
    String redactIdToken(String input, String key, String outputKey) {
      final pattern = RegExp('$key=([^\\s]+)');
      return input.replaceAllMapped(pattern, (match) {
        final value = match.group(1)?.trim() ?? '';
        final hasValue = value.isNotEmpty && value != '-';
        return '$outputKey=$hasValue';
      });
    }

    var redacted = message;
    redacted = redactIdToken(redacted, 'scan_id', 'has_scan_id');
    redacted = redactIdToken(redacted, 'result_id', 'has_result_id');
    redacted = redactIdToken(redacted, 'workspace_id', 'has_workspace_id');
    redacted = redactIdToken(redacted, 'membership_id', 'has_membership_id');
    redacted = redactIdToken(redacted, 'failure_reason', 'has_failure_reason');
    return redacted;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    _postFocusResolutionVersion++;
    WidgetsBinding.instance.removeObserver(this);
    _videoTimer?.cancel();
    _audioTimer?.cancel();
    _captureGapTimer?.cancel();
    _focusTimer?.cancel();
    _statusPulseTimer?.cancel();
    _recorder.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    debugPrint(
      '[ScanFlow] start flow has_request_id=${widget.requestId?.trim().isNotEmpty == true} force_completion=${widget.forceCompletion}',
    );
    debugPrint(
      '[ScanVideo] capture config preset=${_capturePreset.name} target_resolution=$_targetResolution target_fps=$_targetFrameRate target_bitrate=$_targetBitrate format=H264 MP4',
    );
    _statusPulseTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      setState(() {
        _statusPhase = (_statusPhase + 0.15) % 1;
      });
    });
    if (!mounted) return;
    setState(() => _initializing = false);
    debugPrint(
      '[ScanFlow] current flow step=${_step.name} stage=${_stage.name}',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_isCaptureGapActive && !_audioPermissionRequestInProgress) {
        unawaited(
          _invalidateCaptureSession(
            reason: 'app_backgrounded',
            message:
                'The scan was interrupted. Please retake it in one continuous flow.',
          ),
        );
      }
      _cameraController?.pausePreview();
    } else if (state == AppLifecycleState.resumed) {
      _cameraController?.resumePreview();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: PremiumScanScaffold(
        stepLabel: _stageMeta.headerLabel,
        step: _stageMeta.step,
        totalSteps: _stageMeta.totalSteps,
        onBack: _postFocusTerminalState == _PostFocusTerminalState.pending
            ? _backToHomeOrShell
            : _backAction,
        body: _initializing
            ? const Center(
                child: CircularProgressIndicator(color: ScanTheme.cyan),
              )
            : _fatalError
            ? _buildFatalState()
            : _captureSessionInvalidated
            ? _buildCaptureInvalidatedState()
            : _finalizeFailed
            ? _buildFinalizeFailureState()
            : _postFocusTerminalState != _PostFocusTerminalState.none
            ? _buildPostFocusProcessingState()
            : _buildStepBody(),
        footer:
            _initializing ||
                _fatalError ||
                _captureSessionInvalidated ||
                _preparingProcess ||
                _finalizeFailed ||
                _postFocusTerminalState != _PostFocusTerminalState.none
            ? null
            : _buildFooter(),
      ),
    );
  }

  Widget _buildFatalState() {
    return Center(
      child: FailureStateView(
        title: 'Unable to start assessment',
        message:
            _fatalMessage ??
            'The readiness assessment could not be initialized right now. Please try again.',
        primaryLabel: 'Close',
        primaryAction: () => Navigator.maybePop(context),
        secondaryLabel: 'Back',
        secondaryAction: () => Navigator.maybePop(context),
      ),
    );
  }

  Widget _buildFinalizeFailureState() {
    final title =
        _finalizeFailureTitle ?? 'We could not prepare your assessment';
    return Center(
      child: FailureStateView(
        title: title,
        message: _finalizeFailureMessage ?? 'Please try again.',
        primaryLabel: 'Try again',
        primaryAction: _retryFinalizeAfterFailure,
        secondaryLabel: 'Back',
        secondaryAction: () => Navigator.maybePop(context),
      ),
    );
  }

  Widget _buildPostFocusProcessingState() {
    if (_postFocusTerminalState == _PostFocusTerminalState.failure) {
      return Center(
        child: FailureStateView(
          title: _postFocusTimeoutTitle ?? 'RETAKE NEEDED',
          message:
              _postFocusTimeoutMessage ??
              'We could not get a reliable reading. Please retake with your face clearly visible, good lighting, and clear voice.',
          primaryLabel: 'Retake assessment',
          primaryAction: _restartScanFlow,
          secondaryLabel: 'Back to dashboard',
          secondaryAction: _backToHomeOrShell,
        ),
      );
    }

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.symmetric(horizontal: 18),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF111826),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: ScanTheme.cyan.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ScanTheme.cyan.withOpacity(0.24)),
                  ),
                  child: const Icon(
                    Icons.schedule_rounded,
                    color: ScanTheme.cyan,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _postFocusTimeoutTitle ?? 'Preparing your result',
                        style: GoogleFonts.spaceGrotesk(
                          color: ScanTheme.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _postFocusTimeoutMessage ??
                            "We're reviewing your readiness signals.",
                        style: GoogleFonts.inter(
                          color: ScanTheme.textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            LinearProgressIndicator(
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.05),
              color: ScanTheme.cyan,
            ),
            const SizedBox(height: 18),
            Text(
              'Please keep this screen open while we prepare your readiness result.',
              style: GoogleFonts.inter(
                color: ScanTheme.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ScanSecondaryButton(
                    label: 'Back to dashboard',
                    onPressed: _backToHomeOrShell,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBody() {
    return switch (_step) {
      ScanFlowStep.intro => _buildIntro(),
      ScanFlowStep.consent => _buildConsent(),
      ScanFlowStep.permissions => _buildPermissions(),
      ScanFlowStep.video => _buildVideo(),
      ScanFlowStep.audio => _buildAudio(),
      ScanFlowStep.focus => _buildFocus(),
    };
  }

  bool get _videoPreparationReady =>
      !_videoPreparationInProgress &&
      _videoFile != null &&
      _thumbnailBytes != null &&
      _thumbnailBytes!.isNotEmpty;

  bool get _showVideoHandoffState =>
      _videoPreparationInProgress && _step == ScanFlowStep.video;

  Widget? _buildFooter() {
    return switch (_step) {
      ScanFlowStep.intro => Column(
        children: [
          ScanPrimaryButton(
            label: 'Start readiness check',
            icon: Icons.play_arrow_rounded,
            onPressed: () => _setStep(ScanFlowStep.consent),
          ),
          const SizedBox(height: 10),
          ScanSecondaryButton(
            label: 'Cancel',
            onPressed: () => Navigator.maybePop(context),
          ),
        ],
      ),
      ScanFlowStep.consent => Column(
        children: [
          ScanPrimaryButton(
            label: 'I agree and start',
            icon: Icons.verified_outlined,
            onPressed: () {
              _consentAccepted = true;
              debugPrint('[SCAN_FLOW] consent accepted');
              _setStep(ScanFlowStep.permissions);
            },
          ),
          const SizedBox(height: 10),
          ScanSecondaryButton(
            label: 'Cancel',
            onPressed: () => Navigator.maybePop(context),
          ),
        ],
      ),
      ScanFlowStep.permissions => Column(
        children: [
          ScanPrimaryButton(
            label: _permissionsReady ? 'Continue' : 'Grant and continue',
            icon: Icons.shield_outlined,
            onPressed: _preparePermissions,
          ),
          const SizedBox(height: 10),
          ScanSecondaryButton(
            label: 'Back',
            onPressed: () => _setStep(ScanFlowStep.consent),
          ),
        ],
      ),
      ScanFlowStep.video => Column(
        children: [
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_showVideoHandoffState) ...[
                  const ScanPrimaryButton(
                    label: 'Preparing audio check...',
                    icon: Icons.motion_photos_paused_rounded,
                  ),
                ] else if (_videoFile == null) ...[
                  ScanPrimaryButton(
                    label: _videoRecording
                        ? 'Recording...'
                        : 'Record face video',
                    icon: Icons.videocam_rounded,
                    onPressed: _videoRecording ? null : _recordVideo,
                  ),
                ] else ...[
                  ScanPrimaryButton(
                    label: 'Continue',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () => _setStep(ScanFlowStep.audio),
                  ),
                  const SizedBox(height: 10),
                  ScanSecondaryButton(label: 'Retake', onPressed: _retakeVideo),
                ],
              ],
            ),
          ),
        ],
      ),
      ScanFlowStep.audio => Column(
        children: [
          if (_videoPreparationInProgress) ...[
            StatusPill(
              label: 'Finalizing camera check in background',
              color: ScanTheme.warning,
              icon: Icons.hourglass_top_rounded,
            ),
            const SizedBox(height: 10),
          ],
          if (_audioFile == null) ...[
            ScanPrimaryButton(
              label: _audioRecording ? 'Stop recording' : 'Start voice check',
              icon: Icons.mic_rounded,
              onPressed: _audioRecording
                  ? _stopAudioRecording
                  : _startAudioRecording,
            ),
          ] else ...[
            ScanPrimaryButton(
              label: _videoPreparationReady ? 'Continue' : 'Preparing video...',
              icon: Icons.arrow_forward_rounded,
              onPressed: _submitting || !_videoPreparationReady
                  ? null
                  : _finishScan,
            ),
            const SizedBox(height: 10),
            ScanSecondaryButton(
              label: 'Retake',
              onPressed: _submitting || _videoPreparationInProgress
                  ? null
                  : _retakeAudio,
            ),
          ],
          if (_audioFile == null &&
              !_audioRecording &&
              !_videoPreparationInProgress) ...[
            const SizedBox(height: 10),
            ScanSecondaryButton(
              label: 'Back',
              onPressed: () => _setStep(ScanFlowStep.video),
            ),
          ],
        ],
      ),
      ScanFlowStep.focus => null,
    };
  }

  VoidCallback? get _backAction {
    if (_preparingProcess) return null;
    return switch (_step) {
      ScanFlowStep.intro => () => Navigator.maybePop(context),
      ScanFlowStep.consent => () => _setStep(ScanFlowStep.intro),
      ScanFlowStep.permissions => () => _setStep(ScanFlowStep.consent),
      ScanFlowStep.video => () => _setStep(ScanFlowStep.permissions),
      ScanFlowStep.audio => () => _setStep(ScanFlowStep.video),
      ScanFlowStep.focus => null,
    };
  }

  Widget _buildIntro() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SizedBox(
              width: 170,
              height: 170,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          ScanTheme.cyan.withOpacity(0.22),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 122,
                    height: 122,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ScanTheme.cyan.withOpacity(0.28),
                      ),
                    ),
                    child: const Icon(
                      Icons.health_and_safety_outlined,
                      color: ScanTheme.cyan,
                      size: 42,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Ready for your check-in?',
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                color: ScanTheme.textPrimary,
                fontSize: 31,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'A quick readiness check using camera, voice, and focus signals.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: ScanTheme.textSecondary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 18),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What happens next',
                  style: GoogleFonts.inter(
                    color: ScanTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ...const [
                  _ChecklistItem('1. Camera check'),
                  _ChecklistItem('2. Voice check'),
                  _ChecklistItem('3. Focus task'),
                ],
                const SizedBox(height: 14),
                const _IntroTrustBadge(
                  label: 'Your assessment is handled securely.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A smooth check helps',
                  style: GoogleFonts.inter(
                    color: ScanTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ...const [
                  _ChecklistItem('Good lighting'),
                  _ChecklistItem('Face clearly visible'),
                  _ChecklistItem('Quiet place'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          GlassPanel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ScanTheme.cyan.withOpacity(0.32)),
                    boxShadow: [
                      BoxShadow(
                        color: ScanTheme.cyan.withOpacity(0.16),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: ScanTheme.cyan,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Privacy and consent',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    color: ScanTheme.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'This assessment uses your camera, microphone, and short task activity to generate an operational readiness result. It is not a diagnosis.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: ScanTheme.textSecondary,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 18),
                const _TrustBullet(
                  icon: Icons.videocam_outlined,
                  text: 'Camera access for facial visibility',
                ),
                const _TrustBullet(
                  icon: Icons.mic_none_rounded,
                  text: 'Microphone access for voice clarity',
                ),
                const _TrustBullet(
                  icon: Icons.admin_panel_settings_outlined,
                  text: 'Results are controlled by workspace permissions',
                ),
                const _TrustBullet(
                  icon: Icons.close_rounded,
                  text: 'You can cancel before starting',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissions() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Permissions check',
            style: GoogleFonts.spaceGrotesk(
              color: ScanTheme.textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Camera and microphone access are required to continue.',
            style: GoogleFonts.inter(
              color: ScanTheme.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),
          _PermissionCard(
            icon: Icons.videocam_outlined,
            title: 'Camera access',
            description: 'Required for the facial visibility capture.',
            ready: _cameraPermissionReady,
          ),
          const SizedBox(height: 12),
          _PermissionCard(
            icon: Icons.mic_none_rounded,
            title: 'Microphone access',
            description: 'Required for the voice clarity capture.',
            ready: _microphonePermissionReady,
          ),
          const SizedBox(height: 12),
          const _PermissionCard(
            icon: Icons.cloud_upload_outlined,
            title: 'Upload readiness',
            description: 'Required for media handoff and result processing.',
            ready: true,
          ),
          if (_permissionHint.isNotEmpty) ...[
            const SizedBox(height: 14),
            GlassPanel(
              child: Text(
                _permissionHint,
                style: GoogleFonts.inter(
                  color: ScanTheme.warning,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideo() {
    final captureLabel = _videoPreparationInProgress
        ? 'Preparing'
        : _videoRecording
        ? 'Recording'
        : _videoFile != null
        ? 'Captured'
        : 'Ready';
    final captureColor = _videoPreparationInProgress
        ? ScanTheme.warning
        : _videoRecording
        ? ScanTheme.danger
        : _videoFile != null
        ? ScanTheme.teal
        : ScanTheme.cyan;
    final captureIcon = _videoPreparationInProgress
        ? Icons.auto_awesome_motion_rounded
        : _videoRecording
        ? Icons.fiber_manual_record_rounded
        : _videoFile != null
        ? Icons.check_circle_outline_rounded
        : Icons.videocam_rounded;
    final progress = _videoPreparationInProgress
        ? 0.16
        : _videoRecording
        ? (_videoSeconds - _videoSecondsLeft) / _videoSeconds
        : _videoFile != null
        ? 1.0
        : 0.0;

    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.05),
                  Colors.white.withOpacity(0.02),
                ],
              ),
              border: Border.all(color: ScanTheme.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.24),
                  blurRadius: 22,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCameraPreview(),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.30),
                              Colors.transparent,
                              Colors.black.withOpacity(0.48),
                            ],
                            stops: const [0.0, 0.42, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _CameraFrameOverlay(
                    recording: _videoRecording,
                    secondsLeft: _videoSecondsLeft,
                    phase: _statusPhase,
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        _CaptureStateBadge(
                          label: captureLabel,
                          color: captureColor,
                          icon: captureIcon,
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.42),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: Text(
                            'Step 1 of 3',
                            style: GoogleFonts.inter(
                              color: Colors.white.withOpacity(0.88),
                              fontSize: 10.5,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 12,
                    right: 12,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ScanProgressBar(value: progress),
                        if (_videoFailureMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _videoFailureMessage!,
                            style: GoogleFonts.inter(
                              color: ScanTheme.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudio() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Voice check',
            style: GoogleFonts.spaceGrotesk(
              color: ScanTheme.textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _videoPreparationInProgress
                ? 'We are finalizing your camera check in the background.'
                : 'Speak clearly in a quiet place.',
            style: GoogleFonts.inter(
              color: ScanTheme.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          StatusPill(
            label: _videoPreparationInProgress
                ? 'Camera handoff in progress'
                : _audioRecording
                ? 'Microphone live'
                : 'Microphone ready',
            color: _videoPreparationInProgress
                ? ScanTheme.warning
                : _audioRecording
                ? ScanTheme.cyan
                : ScanTheme.teal,
            icon: _videoPreparationInProgress
                ? Icons.hourglass_top_rounded
                : _audioRecording
                ? Icons.mic_rounded
                : Icons.verified_outlined,
          ),
          if (!_videoPreparationInProgress) ...[
            const SizedBox(height: 6),
            Text(
              'We check voice clarity and signal quality.',
              style: GoogleFonts.inter(
                color: ScanTheme.textSecondary,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 18),
          GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _MicOrb(recording: _audioRecording),
                const SizedBox(height: 14),
                _VoiceWaveform(
                  active: _audioRecording,
                  accent: _audioRecording
                      ? ScanTheme.cyan
                      : ScanTheme.primaryBlue,
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Text(
                    'Today is going to be a productive, focused day.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      color: ScanTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _videoPreparationInProgress
                      ? 'Camera check is finalizing in the background. You can start voice check now.'
                      : _audioRecording
                      ? 'Recording. Speak clearly in your normal voice.'
                      : _audioFile != null
                      ? 'Voice check complete. Continue when you are ready for the focus task.'
                      : 'Speak clearly, then tap Stop when you finish.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: ScanTheme.textSecondary,
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                _CaptureStateBadge(
                  label: _audioRecording
                      ? 'Microphone live'
                      : _audioFile != null
                      ? 'Voice saved'
                      : 'Manual stop',
                  color: _audioRecording
                      ? ScanTheme.cyan
                      : _audioFile != null
                      ? ScanTheme.teal
                      : ScanTheme.primaryBlue,
                  icon: _audioRecording
                      ? Icons.mic_rounded
                      : _audioFile != null
                      ? Icons.check_circle_outline_rounded
                      : Icons.pan_tool_alt_outlined,
                ),
                if (_audioFailureMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _audioFailureMessage!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: ScanTheme.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocus() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Focus task',
            style: GoogleFonts.spaceGrotesk(
              color: ScanTheme.textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _focusDone
                ? 'Focus task complete.'
                : _focusActive
                ? 'Tap the highlighted tile as quickly as you can.'
                : 'A short reaction task helps complete your check-in.',
            style: GoogleFonts.inter(
              color: ScanTheme.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          StatusPill(
            label: _focusDone
                ? 'Task complete'
                : _focusActive
                ? 'Task active'
                : 'Task ready',
            color: _focusDone
                ? ScanTheme.teal
                : _focusActive
                ? ScanTheme.warning
                : ScanTheme.primaryBlue,
            icon: _focusDone
                ? Icons.check_circle_outline_rounded
                : _focusActive
                ? Icons.touch_app_rounded
                : Icons.timer_outlined,
          ),
          const SizedBox(height: 6),
          if (_focusDone) ...[
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const StatusPill(
                    label: 'Task complete',
                    color: ScanTheme.teal,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Nice work.',
                    style: GoogleFonts.inter(
                      color: ScanTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Stand by while we keep preparing your readiness result.',
                    style: GoogleFonts.inter(
                      color: ScanTheme.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 18),
            GlassPanel(
              child: Column(
                children: [
                  Row(
                    children: [
                      StatusPill(
                        label: _focusActive
                            ? 'Score $_focusScore'
                            : 'Get ready',
                        color: ScanTheme.teal,
                      ),
                      const SizedBox(width: 8),
                      StatusPill(
                        label: _focusActive ? '${_focusSecondsLeft}s' : '15s',
                        color: ScanTheme.primaryBlue,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ScanProgressBar(
                    value: _focusActive
                        ? (_focusDuration - _focusSecondsLeft) / _focusDuration
                        : 0,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _focusActive
                        ? 'Tap the highlighted tile as quickly as you can.'
                        : 'Get ready. The focus task will begin automatically.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: ScanTheme.textSecondary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  if (!_focusActive) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Stay calm and react quickly.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: ScanTheme.textSecondary,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  AbsorbPointer(
                    absorbing: !_focusActive,
                    child: FocusTileGrid(
                      activeIndex: _activeTileIndex,
                      onTap: _handleFocusTap,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return GlassPanel(
        child: Center(
          child: Text(
            'Camera preview will appear after permission is granted.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: ScanTheme.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      );
    }
    final size = _cameraController!.value.previewSize;
    if (size == null) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        color: Colors.black,
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: size.height,
              height: size.width,
              child: CameraPreview(_cameraController!),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _preparePermissions() async {
    debugPrint('[SCAN_FLOW] permission check start');
    try {
      await _initCamera();
      _cameraPermissionReady = true;
    } catch (e) {
      _cameraPermissionReady = false;
      _permissionHint =
          'Camera access is missing. Allow camera permission and try again.';
    }
    _microphonePermissionReady = await _ensureAudioPermission();
    if (!_microphonePermissionReady) {
      _permissionHint =
          'Microphone access is missing. Allow microphone permission and try again.';
    }
    _permissionsReady = _cameraPermissionReady && _microphonePermissionReady;
    setState(() {});
    if (_permissionsReady) {
      debugPrint('[SCAN_FLOW] permission check success');
      _setStep(ScanFlowStep.video);
    }
  }

  Future<void> _initCamera() async {
    if (_cameraController?.value.isInitialized == true) return;
    debugPrint('[SCAN_CAMERA] enumerate cameras start');
    final cameras = await availableCameras();
    debugPrint(
      '[SCAN_CAMERA] enumerate cameras success count=${cameras.length}',
    );
    final camera = cameras.firstWhere(
      (item) => item.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      camera,
      _capturePreset,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    debugPrint(
      '[SCAN_CAMERA] initialize lens=${camera.lensDirection.name} preset=${_capturePreset.name}',
    );
    await controller.initialize();
    await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    try {
      final minZoom = await controller.getMinZoomLevel();
      final zoomLevel = math.max(1.0, minZoom);
      await controller.setZoomLevel(zoomLevel);
      debugPrint(
        '[SCAN_CAMERA] zoom reset zoom_level=$zoomLevel min_zoom=$minZoom',
      );
    } catch (e) {
      debugPrint(
        '[SCAN_CAMERA] zoom reset skipped error_type=${e.runtimeType}',
      );
    }
    _cameraController = controller;
    setState(() {});
  }

  Future<void> _recordVideo() async {
    if (_cameraController == null || _videoRecording) return;
    debugPrint('[SCAN_VIDEO] recording start scan_step=video');
    debugPrint(
      '[SCAN_VIDEO] settings preset=${_capturePreset.name} preferred_resolution=$_targetResolution preferred_fps=$_targetFrameRate preferred_bitrate=$_targetBitrate',
    );
    try {
      _videoTimer?.cancel();
      _videoFailureMessage = null;
      _videoAutoAdvanced = false;
      _videoStopInProgress = false;
      _videoPreparationFailed = false;
      _videoPreparationInProgress = false;
      _videoPreparationFuture = null;
      _videoPreparationVersion++;
      _captureSessionInvalidated = false;
      _captureInvalidationReason = null;
      _captureInvalidationMessage = null;
      _videoStartedAt = DateTime.now();
      _videoCompletedAt = null;
      _audioStepOpenedAt = null;
      _audioStartedAt = null;
      _audioCompletedAt = null;
      await _cameraController!.prepareForVideoRecording();
      await _cameraController!.startVideoRecording();
      HapticFeedback.mediumImpact();
      setState(() {
        _videoRecording = true;
        _videoSecondsLeft = _videoSeconds;
        _videoFailureMessage = null;
      });
      _videoTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        if (!mounted) return;
        if (_videoSecondsLeft <= 1) {
          timer.cancel();
          if (kDebugMode) {
            debugPrint(
              '[SCAN_VIDEO_AUTO_COMPLETE] seconds=$_videoSeconds transitioned=true',
            );
          }
          unawaited(_beginVideoToAudioHandoff());
        } else {
          setState(() => _videoSecondsLeft--);
        }
      });
    } catch (e, s) {
      debugPrint('[SCAN_VIDEO] recording failed error_type=${e.runtimeType}');
      debugPrint('[SCAN_VIDEO] stack_present=${s.toString().isNotEmpty}');
      if (mounted) {
        setState(() {
          _videoRecording = false;
          _videoStopInProgress = false;
          _videoPreparationInProgress = false;
          _videoFailureMessage = 'Video recording failed. Please try again.';
        });
      }
      _showError('Unable to start camera scan. Please try again.');
    }
  }

  Future<void> _beginVideoToAudioHandoff() async {
    if (_cameraController == null || !_videoRecording || _videoStopInProgress) {
      return;
    }
    _videoTimer?.cancel();
    _videoStopInProgress = true;
    final preparationVersion = ++_videoPreparationVersion;
    if (mounted) {
      setState(() {
        _videoRecording = false;
        _videoSecondsLeft = 0;
        _videoPreparationInProgress = true;
        _videoPreparationFailed = false;
        _videoFailureMessage = null;
      });
    }
    try {
      final rawFile = await _cameraController!.stopVideoRecording();
      HapticFeedback.selectionClick();
      if (!mounted) return;
      final completedAt = DateTime.now();
      _videoCompletedAt = completedAt;
      debugPrint('[CAPTURE_FLOW] video_completed=true');
      _videoPreparationFuture = _processVideoAfterCapture(
        rawFile,
        preparationVersion: preparationVersion,
      );
      _openAudioStepAfterVideoStop();
      _armCaptureGapTimer();
    } catch (e, s) {
      debugPrint('[SCAN_VIDEO] stop failed error_type=${e.runtimeType}');
      debugPrint('[SCAN_VIDEO] stack_present=${s.toString().isNotEmpty}');
      if (mounted) {
        setState(() {
          _videoRecording = false;
          _videoPreparationInProgress = false;
          _videoPreparationFailed = true;
          _videoFailureMessage =
              'Video capture stopped unexpectedly. Please retry.';
        });
      }
      _showError('Unable to finish camera scan. Please try again.');
    } finally {
      _videoStopInProgress = false;
      if (mounted) {
        setState(() => _videoRecording = false);
      }
    }
  }

  void _openAudioStepAfterVideoStop() {
    if (!mounted || _step != ScanFlowStep.video || _videoAutoAdvanced) return;
    _videoAutoAdvanced = true;
    _audioStepOpenedAt = DateTime.now();
    debugPrint('[CAPTURE_FLOW] audio_step_opened=true');
    _setStep(ScanFlowStep.audio);
  }

  Future<void> _processVideoAfterCapture(
    XFile rawFile, {
    required int preparationVersion,
  }) async {
    try {
      final originalSize = await _safeLength(rawFile);
      debugPrint(
        '[SCAN_VIDEO] original file path_present=${rawFile.path.trim().isNotEmpty}',
      );
      debugPrint('[SCAN_VIDEO] original file size=$originalSize');
      final processed = await _maybeCompressVideo(rawFile);
      final processedSize = await _safeLength(processed);
      debugPrint(
        '[SCAN_VIDEO] processed file path_present=${processed.path.trim().isNotEmpty}',
      );
      debugPrint('[SCAN_VIDEO] processed file size=$processedSize');
      final thumbBytes = await _generateThumbnail(processed);
      if (thumbBytes == null || thumbBytes.isEmpty) {
        throw StateError('thumbnail_missing');
      }
      if (!mounted || preparationVersion != _videoPreparationVersion) return;
      setState(() {
        _videoFile = processed;
        _thumbnailBytes = thumbBytes;
        _videoPreparationInProgress = false;
        _videoPreparationFailed = false;
        _videoFailureMessage = null;
      });
      _startMediaPrefinalizeIfReady();
    } catch (e, s) {
      debugPrint('[SCAN_VIDEO] process failed error_type=${e.runtimeType}');
      debugPrint('[SCAN_VIDEO] stack_present=${s.toString().isNotEmpty}');
      if (mounted && preparationVersion == _videoPreparationVersion) {
        setState(() {
          _videoRecording = false;
          _videoPreparationInProgress = false;
          _videoPreparationFailed = true;
          _audioFile = null;
          _audioFailureMessage = null;
          _videoFailureMessage =
              'Video capture could not be prepared. Please retake the scan.';
          _step = ScanFlowStep.video;
        });
      }
      _showError(
        'Video capture could not be prepared. Please retake the scan.',
      );
    }
  }

  Future<XFile> _maybeCompressVideo(XFile file) async {
    debugPrint(
      '[SCAN_VIDEO] compression request resolution=$_targetResolution fps=$_targetFrameRate bitrate=$_targetBitrate preserve_orientation=true avoid_retranscode=true',
    );
    return compressVideo(file);
  }

  Future<Uint8List?> _generateThumbnail(XFile file) async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: file.path,
        imageFormat: thumb.ImageFormat.JPEG,
        quality: 70,
      );
      debugPrint(
        '[SCAN_VIDEO] thumbnail generated bytes=${bytes.length} has_scan_id=${_scanId?.trim().isNotEmpty == true}',
      );
      return bytes;
    } catch (e) {
      debugPrint(
        '[SCAN_VIDEO] thumbnail generation failed error_type=${e.runtimeType}',
      );
      return null;
    }
  }

  Future<void> _startAudioRecording() async {
    if (_captureSessionInvalidated) {
      _showCaptureInvalidatedMessage();
      return;
    }
    if (!_isVideoToAudioGapValid()) {
      await _invalidateCaptureSession(
        reason: 'step_gap_timeout',
        message:
            'The scan timed out between steps. Please retake it in one continuous flow.',
      );
      return;
    }
    _audioPermissionRequestInProgress = true;
    final hasPermission = await _ensureAudioPermission();
    _audioPermissionRequestInProgress = false;
    if (_captureSessionInvalidated) {
      _showCaptureInvalidatedMessage();
      return;
    }
    if (!_isVideoToAudioGapValid()) {
      await _invalidateCaptureSession(
        reason: 'step_gap_timeout',
        message:
            'The scan timed out between steps. Please retake it in one continuous flow.',
      );
      return;
    }
    if (!hasPermission) {
      await _invalidateCaptureSession(
        reason: 'microphone_permission_denied',
        message: 'Microphone access is required. Allow it and retake the scan.',
      );
      return;
    }
    try {
      _audioFailureMessage = null;
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/scan_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 128000,
          numChannels: 1,
        ),
        path: path,
      );
      debugPrint(
        '[SCAN_AUDIO] settings encoder=aacLc sample_rate=44100 bitrate=128000 channels=1',
      );
      HapticFeedback.mediumImpact();
      setState(() {
        _audioRecording = true;
        _audioSecondsElapsed = 0;
        _audioAutoStopInProgress = false;
        _audioAutoAdvanced = false;
        _audioFailureMessage = null;
        _audioStartedAt = DateTime.now();
      });
      debugPrint(
        '[CAPTURE_FLOW] video_to_audio_gap_ms=${_audioStartedAt!.difference(_videoCompletedAt ?? _audioStartedAt!).inMilliseconds}',
      );
      _cancelCaptureGapTimer();
      _startMediaPrefinalizeIfReady();
      _audioTimer?.cancel();
      _audioTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _audioSecondsElapsed++);
        if (_audioSecondsElapsed >= _audioSeconds &&
            !_audioAutoStopInProgress &&
            _audioRecording) {
          _audioAutoStopInProgress = true;
          timer.cancel();
          unawaited(_handleAudioAutoComplete());
        }
      });
      debugPrint(
        '[SCAN_AUDIO] recording start path_present=${path.trim().isNotEmpty}',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _audioRecording = false;
          _audioFailureMessage = 'Audio recording failed. Please try again.';
        });
      }
      _showError('Audio recording failed. Please try again.');
    }
  }

  Future<void> _stopAudioRecording() async {
    try {
      final path = await _recorder.stop();
      HapticFeedback.selectionClick();
      _audioTimer?.cancel();
      if (path == null || path.isEmpty) {
        if (mounted) {
          setState(() {
            _audioRecording = false;
            _audioFailureMessage = 'Audio recording failed. Please try again.';
          });
        }
        _showError('Audio recording failed. Please try again.');
        return;
      }
      _audioCompletedAt = DateTime.now();
      setState(() {
        _audioRecording = false;
        _audioFile = XFile(path);
        _audioFailureMessage = null;
      });
      debugPrint(
        '[SCAN_AUDIO] recording stop path_present=${path.trim().isNotEmpty}',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _audioRecording = false;
          _audioFailureMessage = 'Audio recording failed. Please try again.';
        });
      }
      _showError('Audio recording failed. Please try again.');
    } finally {
      _audioTimer?.cancel();
      if (mounted) {
        setState(() => _audioRecording = false);
      }
    }
  }

  Future<void> _handleAudioAutoComplete() async {
    if (_audioAutoAdvanced) return;
    _audioAutoAdvanced = true;
    if (!_audioRecording || _audioFile != null) {
      if (kDebugMode) {
        debugPrint(
          '[SCAN_AUDIO_AUTO_COMPLETE] seconds=$_audioSeconds transitioned=false',
        );
      }
      return;
    }
    await _stopAudioRecording();
    final captureReady =
        _audioFile != null &&
        !_captureSessionInvalidated &&
        _audioFailureMessage == null;
    if (kDebugMode) {
      debugPrint(
        '[SCAN_AUDIO_AUTO_COMPLETE] seconds=$_audioSeconds transitioned=$captureReady',
      );
    }
    if (!mounted || !captureReady) return;
    if (_submitting) return;
    unawaited(_finishScan());
  }

  Future<bool> _ensureAudioPermission() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      debugPrint('[SCAN_AUDIO] microphone permission=$hasPermission');
      return hasPermission;
    } catch (e) {
      debugPrint(
        '[SCAN_AUDIO] microphone permission check failed error_type=${e.runtimeType}',
      );
      return false;
    }
  }

  void _startMediaPrefinalizeIfReady() {
    if (_prefinalizedMediaFuture != null) return;
    if (_captureSessionInvalidated || _audioStartedAt == null) return;
    final videoFile = _videoFile;
    final thumbnailBytes = _thumbnailBytes;
    if (videoFile == null || thumbnailBytes == null || thumbnailBytes.isEmpty) {
      return;
    }

    final stagingKey =
        'pending_${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(100000)}';
    _prefinalizedMediaFuture = ScanFinalizeService.instance
        .startMediaPrefinalize(
          stagingKey: stagingKey,
          videoFile: videoFile,
          thumbnailBytes: thumbnailBytes,
        );
    debugPrint(
      '[SCAN_PREFINALIZE] scheduled ts=${DateTime.now().toIso8601String()} has_staging_key=${stagingKey.trim().isNotEmpty}',
    );
  }

  Future<void> _finishScan() async {
    if (_submitting || _audioFile == null) {
      if (_audioFile == null) {
        _showError('Scan data is incomplete. Please retry.');
      }
      return;
    }
    if (!_isVideoToAudioGapValid()) {
      await _invalidateCaptureSession(
        reason: 'step_gap_timeout',
        message:
            'The scan timed out between steps. Please retake it in one continuous flow.',
      );
      return;
    }
    _submitting = true;
    _finalizeFailed = false;
    _finalizeFailureMessage = null;
    try {
      await _awaitPreparedVideoForFinalize();
    } catch (e, s) {
      debugPrint(
        '[SCAN_VIDEO] finalize wait failed error_type=${e.runtimeType}',
      );
      debugPrint(
        '[SCAN_VIDEO] finalize wait stack_present=${s.toString().isNotEmpty}',
      );
      _submitting = false;
      _showError(
        'Video capture could not be prepared. Please retake the scan.',
      );
      if (mounted) {
        setState(() {
          _videoPreparationFailed = true;
          _videoPreparationInProgress = false;
          _step = ScanFlowStep.video;
        });
      }
      return;
    }
    if (_videoFile == null ||
        _thumbnailBytes == null ||
        _thumbnailBytes!.isEmpty) {
      _submitting = false;
      _showError('Scan data is incomplete. Please retry.');
      return;
    }
    try {
      if (_scanId == null) {
        debugPrint('[SCAN_BOOT] step=1 create_wellness_scan start');
        _scanId = await ScanService.instance.createWellnessScan(
          consentGranted: _consentAccepted,
          scanRequestId: widget.requestId,
          requestSource: widget.requestId == null ? 'self' : 'manager_request',
          deviceInfo: {
            'capture_resolution_preferred': _targetResolution,
            'capture_fps_preferred': _targetFrameRate,
            'capture_bitrate_preferred': _targetBitrate,
          },
        );
        debugPrint(
          '[SCAN_BOOT] step=1 create_wellness_scan success has_scan_id=${_scanId?.trim().isNotEmpty == true}',
        );
      }
    } catch (e, s) {
      debugPrint('[SCAN_SUBMIT_FAILED] error_type=${e.runtimeType}');
      debugPrint(
        '[SCAN_SUBMIT_FAILED] stack_present=${s.toString().isNotEmpty}',
      );
      _submitting = false;
      _showError('We could not prepare your assessment. Please try again.');
      setState(() {});
      return;
    }
    debugPrint(
      '[VOICE] continue_pressed has_scan_id=${_scanId?.trim().isNotEmpty == true}',
    );
    setState(() {});
    try {
      final finalizeFuture = _startWorkflowIfNeeded();
      unawaited(finalizeFuture);
      if (!mounted) return;
      _preparingProcess = false;
      _setStep(ScanFlowStep.focus);
      setState(() {});
      if (!mounted) return;
      _startFocusTask();
    } catch (e, s) {
      debugPrint(
        '[SCAN_FLOW_ORDER_ERROR] ts=${DateTime.now().toIso8601String()} has_scan_id=${_scanId?.trim().isNotEmpty == true} audioUploaded=${_audioFile != null} videoUploaded=${_videoFile != null} thumbnailUploaded=${_thumbnailBytes != null && _thumbnailBytes!.isNotEmpty} scanMediaCreated=false mediaReadyPatched=false processCallStarted=false processAccepted=false error_type=${e.runtimeType}',
      );
      debugPrint(
        '[SCAN_FLOW_ORDER_ERROR] stack_present=${s.toString().isNotEmpty}',
      );
      if (!mounted) return;
      _preparingProcess = false;
      _submitting = false;
      _showFinalizeFailureState();
    }
  }

  Future<void> _awaitPreparedVideoForFinalize() async {
    final future = _videoPreparationFuture;
    if (future != null) {
      await future;
    }
    if (!_videoPreparationReady || _videoPreparationFailed) {
      throw StateError('video_preparation_incomplete');
    }
  }

  Future<_WorkflowTerminalResult> _startWorkflowIfNeeded() {
    if (_workflowFuture != null) {
      debugPrint(
        '[ScanFlow] duplicate trigger ignored has_scan_id=${_scanId?.trim().isNotEmpty == true} reason=workflow_future_exists',
      );
      return _workflowFuture!;
    }
    if (_workflowStarted) {
      debugPrint(
        '[ScanFlow] duplicate trigger ignored has_scan_id=${_scanId?.trim().isNotEmpty == true} reason=workflow_already_started',
      );
      return _workflowFuture!;
    }
    if (_scanId == null ||
        _audioFile == null ||
        _videoFile == null ||
        _thumbnailBytes == null ||
        _thumbnailBytes!.isEmpty) {
      throw StateError('finalize_prerequisites_missing');
    }
    _workflowStarted = true;
    _workflowSettled = false;
    _backgroundFinalizeFailure = null;
    _backgroundFinalizeFailureStack = null;
    _workflowFuture = (() async {
      try {
        final result = await ScanFinalizeService.instance.start(
          scanId: _scanId!,
          audioFile: _audioFile!,
          videoFile: _videoFile!,
          thumbnailBytes: _thumbnailBytes!,
          durationSeconds: _videoSeconds + _audioSecondsElapsed,
          prefinalizedMedia: _prefinalizedMediaFuture,
          onProgress: (step) {
            _currentFinalizeStep = step;
          },
        );
        _workflowSettled = true;
        debugPrint(
          '[SCAN_FLOW_ORDER_ASSERT] ts=${DateTime.now().toIso8601String()} has_scan_id=${_scanId?.trim().isNotEmpty == true} audioUploaded=true videoUploaded=true thumbnailUploaded=true scanMediaCreated=true mediaReadyPatched=true processCallStarted=true processAccepted=true',
        );
        return _WorkflowTerminalResult.success(result);
      } catch (error, stackTrace) {
        _backgroundFinalizeFailure = error;
        _backgroundFinalizeFailureStack = stackTrace;
        _workflowSettled = true;
        debugPrint(
          '[SCAN_FINALIZE] background_finalize_failed_deferred has_scan_id=${_scanId?.trim().isNotEmpty == true} error_type=${error.runtimeType}',
        );
        debugPrint(
          '[SCAN_FINALIZE] background_finalize_failed_stack_present=${stackTrace.toString().isNotEmpty}',
        );
        return _WorkflowTerminalResult.failure(error, stackTrace);
      }
    })();
    return _workflowFuture!;
  }

  Future<void> _markScanFailedAfterFinalizeError(Object error) async {
    if (_scanId == null) return;
    try {
      await ScanService.instance.markWellnessScanFailed(
        scanId: _scanId!,
        failureReason: 'scan_prepare_failed',
      );
      debugPrint(
        '[SCAN_FINALIZE] finalize_failure_patch success has_scan_id=${_scanId?.trim().isNotEmpty == true} failure_reason=scan_prepare_failed',
      );
    } catch (e) {
      debugPrint(
        '[SCAN_FINALIZE] finalize_failure_patch fail has_scan_id=${_scanId?.trim().isNotEmpty == true} error_type=${e.runtimeType}',
      );
    }
  }

  void _startFocusTask() {
    _focusTimer?.cancel();
    final waitMs = _focusShellVisibleAt == null
        ? 0
        : DateTime.now().difference(_focusShellVisibleAt!).inMilliseconds;
    debugPrint(
      '[FOCUS_GAME_WAITING_FOR_PROCESS] has_scan_id=${_scanId?.trim().isNotEmpty == true} elapsed_ms=$waitMs',
    );
    if (waitMs > 2000) {
      debugPrint(
        '[FOCUS_GAME_START_DELAY] has_scan_id=${_scanId?.trim().isNotEmpty == true} elapsed_ms=$waitMs current_finalize_step=$_currentFinalizeStep',
      );
    }
    debugPrint(
      '[SCAN_FLOW] focus_task_start ts=${DateTime.now().toIso8601String()} has_scan_id=${_scanId?.trim().isNotEmpty == true}',
    );
    debugPrint(
      '[SCAN_FLOW] focus_task_game_start ts=${DateTime.now().toIso8601String()} has_scan_id=${_scanId?.trim().isNotEmpty == true}',
    );
    debugPrint(
      '[SCAN_FINALIZE] focus_task_start ts=${DateTime.now().toIso8601String()} has_scan_id=${_scanId?.trim().isNotEmpty == true}',
    );
    debugPrint(
      '[FOCUS_TASK] start ts=${DateTime.now().toIso8601String()} has_scan_id=${_scanId?.trim().isNotEmpty == true}',
    );
    setState(() {
      _focusActive = true;
      _focusDone = false;
      _focusSecondsLeft = _focusDuration;
      _focusScore = 0;
      _activeTileIndex = _randomTile();
    });
    _focusTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_focusSecondsLeft <= 1) {
        timer.cancel();
        _completeFocusTask();
      } else {
        setState(() => _focusSecondsLeft--);
      }
    });
  }

  void _handleFocusTap(int index) {
    if (!_focusActive || _focusDone) return;
    if (index == _activeTileIndex) {
      HapticFeedback.lightImpact();
      setState(() {
        _focusScore++;
        _activeTileIndex = _randomTile(excluding: index);
      });
    }
  }

  int _randomTile({int? excluding}) {
    final random = math.Random();
    var next = random.nextInt(9);
    if (excluding != null && next == excluding) {
      next = (next + 1) % 9;
    }
    return next;
  }

  void _completeFocusTask() {
    _focusTimer?.cancel();
    final scanId = _scanId ?? 'pending';
    final timestamp = DateTime.now().toIso8601String();
    final workflowState = _workflowFuture == null
        ? 'null'
        : (_workflowSettled ? 'settled' : 'pending');
    _devLog(
      'POST_FOCUS',
      'focus_done ts=$timestamp has_scan_id=${scanId != 'pending'} current_route=${_currentRouteName()} finalize_future_state=$workflowState',
    );
    debugPrint('[FOCUS_TASK] complete has_scan_id=${scanId != 'pending'}');
    debugPrint('[ScanFlow] focus_done has_scan_id=${scanId != 'pending'}');
    debugPrint('[RESULT] focus_done has_scan_id=${scanId != 'pending'}');
    setState(() {
      _focusActive = false;
      _focusDone = true;
      _focusSecondsLeft = 0;
    });
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      unawaited(_finishAfterFocusTask());
    });
  }

  Future<void> _finishAfterFocusTask() async {
    final workflowFuture = _workflowFuture;
    final resolutionVersion = ++_postFocusResolutionVersion;
    final deadline = DateTime.now().add(_maxPostFocusWait);
    if (workflowFuture == null) {
      debugPrint(
        '[FOCUS_TASK] finalize_failed has_scan_id=${_scanId?.trim().isNotEmpty == true} error=no_workflow_future',
      );
      await _markScanFailedAfterFinalizeError(StateError('no_workflow_future'));
      if (!mounted) return;
      _showPostFocusFailure('scan_prepare_failed');
      return;
    }

    final scanId = _scanId ?? 'pending';
    _devLog(
      'POST_FOCUS',
      'finalize_wait_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId != 'pending'} current_route=${_currentRouteName()} finalize_future_state=${_workflowSettled ? 'settled' : 'pending'}',
    );
    debugPrint(
      '[ScanFlow] finalize_wait_start has_scan_id=${scanId != 'pending'}',
    );

    if (!_workflowSettled) {
      debugPrint(
        '[FOCUS_TASK] awaiting_finalize has_scan_id=${scanId != 'pending'}',
      );
      debugPrint(
        '[RESULT] finalize_wait_start has_scan_id=${scanId != 'pending'}',
      );
      _preparingProcess = true;
      if (mounted) setState(() {});
    }

    try {
      final terminal = !_workflowSettled
          ? await workflowFuture.timeout(_postFocusFinalizeWait)
          : await workflowFuture;
      final result = terminal.result;
      if (!terminal.isSuccess || result == null) {
        final error = terminal.error ?? _backgroundFinalizeFailure;
        final stackTrace =
            terminal.stackTrace ?? _backgroundFinalizeFailureStack;
        debugPrint(
          '[FOCUS_TASK] finalize_failed has_scan_id=${_scanId?.trim().isNotEmpty == true} error_type=${error.runtimeType}',
        );
        debugPrint(
          '[FOCUS_TASK] finalize_failed_stack_present=${stackTrace?.toString().isNotEmpty == true}',
        );
        if (!mounted) return;
        _preparingProcess = false;
        _submitting = false;
        _showPostFocusFailure('scan_prepare_failed');
        return;
      }
      _devLog(
        'POST_FOCUS',
        'finalize_wait_done ts=${DateTime.now().toIso8601String()} has_scan_id=${result.scanId.trim().isNotEmpty} current_route=${_currentRouteName()} finalize_future_state=settled',
      );
      debugPrint(
        '[FOCUS_TASK] finalize_success has_scan_id=${result.scanId.trim().isNotEmpty}',
      );
      debugPrint(
        '[ScanFlow] finalize_wait_done has_scan_id=${result.scanId.trim().isNotEmpty}',
      );
      debugPrint(
        '[RESULT] finalize_wait_done has_scan_id=${result.scanId.trim().isNotEmpty}',
      );
      if (!mounted || resolutionVersion != _postFocusResolutionVersion) return;
      _preparingProcess = true;
      setState(() {});
      await _resolvePostFocusResult(
        deadline: deadline,
        resolutionVersion: resolutionVersion,
      );
    } on TimeoutException {
      debugPrint(
        '[FOCUS_TASK] finalize_still_running has_scan_id=${_scanId?.trim().isNotEmpty == true} wait_seconds=${_postFocusFinalizeWait.inSeconds}',
      );
      if (!mounted || resolutionVersion != _postFocusResolutionVersion) return;
      _showPostFocusPending();
      unawaited(
        _observeBackgroundFinalize(
          workflowFuture: workflowFuture,
          resolutionVersion: resolutionVersion,
        ),
      );
      await _resolvePostFocusResult(
        deadline: deadline,
        resolutionVersion: resolutionVersion,
      );
    } catch (e, s) {
      debugPrint(
        '[FOCUS_TASK] finalize_failed has_scan_id=${_scanId?.trim().isNotEmpty == true} error_type=${e.runtimeType}',
      );
      debugPrint(
        '[FOCUS_TASK] finalize_failed_stack_present=${s.toString().isNotEmpty}',
      );
      await _markScanFailedAfterFinalizeError(e);
      if (!mounted) return;
      _preparingProcess = false;
      _submitting = false;
      _showPostFocusFailure('scan_prepare_failed');
    }
  }

  Future<void> _observeBackgroundFinalize({
    required Future<_WorkflowTerminalResult> workflowFuture,
    required int resolutionVersion,
  }) async {
    final terminal = await workflowFuture;
    if (!mounted || resolutionVersion != _postFocusResolutionVersion) return;
    if (terminal.isSuccess && terminal.result != null) {
      return;
    }
    final error = terminal.error ?? _backgroundFinalizeFailure;
    if (error != null) {
      await _markScanFailedAfterFinalizeError(error);
    }
    if (!mounted || resolutionVersion != _postFocusResolutionVersion) return;
    _showPostFocusFailure('scan_prepare_failed');
  }

  Future<void> _resolvePostFocusResult({
    required DateTime deadline,
    required int resolutionVersion,
  }) async {
    final scanId = _scanId;
    if (scanId == null || !mounted) {
      _showPostFocusFailure('scan_prepare_failed');
      return;
    }

    _devLog(
      'POST_FOCUS',
      'post_focus_resolve_start ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} current_route=${_currentRouteName()} finalize_future_state=${_workflowSettled ? 'settled' : 'pending'}',
    );
    debugPrint(
      '[ScanFlow] post_focus_resolve_start has_scan_id=${scanId.trim().isNotEmpty}',
    );
    ActiveWorkspaceContext? workspace;
    try {
      workspace = await OrganizationService.instance
          .fetchActiveWorkspaceContext();
    } catch (e, s) {
      debugPrint(
        '[ScanFlow] post_focus_workspace_context_unavailable has_scan_id=${scanId.trim().isNotEmpty} error_type=${e.runtimeType}',
      );
      debugPrint(
        '[ScanFlow] post_focus_workspace_context_stack_present=${s.toString().isNotEmpty}',
      );
    }
    final workspaceId = (workspace?.businessProfileId ?? '').trim();
    final membershipId = (workspace?.membershipId ?? '').trim();
    final effectiveRole = (workspace?.finalEffectiveRole ?? '').trim();
    final directusRole = (workspace?.directusRoleName ?? '').trim();
    final pollingStartedAt = DateTime.now();
    var attempt = 0;

    while (mounted &&
        resolutionVersion == _postFocusResolutionVersion &&
        DateTime.now().isBefore(deadline)) {
      attempt++;
      ScanResultLookup? lookup;
      try {
        lookup = await ScanService.instance.fetchScanResultLookupForScan(
          scanId,
        );
      } catch (e, s) {
        debugPrint(
          '[ScanFlow] post_focus_resolve_result_error has_scan_id=${scanId.trim().isNotEmpty} attempt=$attempt error_type=${e.runtimeType}',
        );
        debugPrint(
          '[ScanFlow] post_focus_resolve_result_stack_present=${s.toString().isNotEmpty}',
        );
      }

      final scanResultsCount = lookup?.count ?? 0;
      final firstResultId = lookup?.firstResultId?.trim();
      var scanStatus = lookup?.result != null || scanResultsCount > 0
          ? null
          : await _fetchPostFocusStatus(scanId, attempt);
      final status = scanStatus?.status ?? 'unknown';
      final failureReason = scanStatus?.failureReason;

      if (lookup?.result != null) {
        _devLog(
          'SCAN_DECISION',
          'decision=show_result reason=result_parsed scan_id=$scanId attempt=$attempt status=$status failure_reason=${failureReason ?? '-'} scan_results_count=$scanResultsCount result_id=${lookup!.result!.id} workspace_id=${workspaceId.isEmpty ? '-' : workspaceId} membership_id=${membershipId.isEmpty ? '-' : membershipId} effective_role=${effectiveRole.isEmpty ? '-' : effectiveRole} directus_role=${directusRole.isEmpty ? '-' : directusRole} ts=${DateTime.now().toIso8601String()}',
        );
        debugPrint(
          '[ScanFlow] post_focus_result_found has_scan_id=${scanId.trim().isNotEmpty}',
        );
        _openResultPollingScreen(lookup.result!);
        return;
      }

      if (scanResultsCount > 0 &&
          (firstResultId != null && firstResultId.isNotEmpty)) {
        try {
          debugPrint(
            '[SCAN_RESULTS] direct_lookup_retry has_scan_id=${scanId.trim().isNotEmpty} has_result_id=${firstResultId.trim().isNotEmpty} attempt=$attempt',
          );
          final directResult = await ScanService.instance.fetchScanResultById(
            firstResultId,
          );
          if (directResult != null) {
            _devLog(
              'SCAN_DECISION',
              'decision=show_result reason=result_visible scan_id=$scanId attempt=$attempt status=$status failure_reason=${failureReason ?? '-'} scan_results_count=$scanResultsCount result_id=${directResult.id} source=direct_by_id workspace_id=${workspaceId.isEmpty ? '-' : workspaceId} membership_id=${membershipId.isEmpty ? '-' : membershipId} effective_role=${effectiveRole.isEmpty ? '-' : effectiveRole} directus_role=${directusRole.isEmpty ? '-' : directusRole} ts=${DateTime.now().toIso8601String()}',
            );
            debugPrint(
              '[ScanFlow] post_focus_result_found has_scan_id=${scanId.trim().isNotEmpty}',
            );
            _openResultPollingScreen(directResult);
            return;
          }
        } catch (e, s) {
          debugPrint(
            '[ScanFlow] post_focus_resolve_direct_result_error has_scan_id=${scanId.trim().isNotEmpty} attempt=$attempt has_result_id=${firstResultId.trim().isNotEmpty} error_type=${e.runtimeType}',
          );
          debugPrint(
            '[ScanFlow] post_focus_resolve_direct_result_stack_present=${s.toString().isNotEmpty}',
          );
        }
      }

      if (scanStatus == null) {
        scanStatus = await _fetchPostFocusStatus(scanId, attempt);
      }

      final statusForLog = scanStatus?.status ?? 'unknown';
      final failureReasonForLog = scanStatus?.failureReason;
      _devLog(
        'SCAN_DECISION',
        'attempt=$attempt scan_id=$scanId status=$statusForLog failure_reason=${failureReasonForLog ?? '-'} scan_results_count=$scanResultsCount decision=${scanStatus?.isFailed == true ? 'show_failure' : 'retry'} reason=${scanStatus?.isFailed == true ? 'failed' : 'no_result'} workspace_id=${workspaceId.isEmpty ? '-' : workspaceId} membership_id=${membershipId.isEmpty ? '-' : membershipId} effective_role=${effectiveRole.isEmpty ? '-' : effectiveRole} directus_role=${directusRole.isEmpty ? '-' : directusRole} ts=${DateTime.now().toIso8601String()}',
      );

      if (scanStatus?.isFailed == true) {
        _devLog(
          'SCAN_DECISION',
          'decision=show_failure reason=failed scan_id=$scanId attempt=$attempt status=$statusForLog failure_reason=${failureReasonForLog ?? '-'} scan_results_count=$scanResultsCount',
        );
        debugPrint(
          '[ScanFlow] post_focus_failed reason=${scanStatus?.failureReason}',
        );
        _showPostFocusFailure(scanStatus?.failureReason);
        return;
      }

      if (scanStatus?.isCompleted == true) {
        final resolved = await _resolveCompletedPostFocusResult(
          scanId: scanId,
          attempt: attempt,
          scanResultsCount: scanResultsCount,
          firstResultId: firstResultId,
          workspaceId: workspaceId,
          membershipId: membershipId,
          effectiveRole: effectiveRole,
          directusRole: directusRole,
          maxDeadline: deadline,
          resolutionVersion: resolutionVersion,
        );
        if (resolved) return;
      }

      if (!mounted || resolutionVersion != _postFocusResolutionVersion) return;
      final elapsed = DateTime.now().difference(pollingStartedAt);
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        break;
      }
      final nextDelay = _postFocusPollingPolicy.nextDelay(elapsed);
      _devLog(
        'SCAN_DECISION',
        'decision=retry reason=result_missing scan_id=$scanId attempt=$attempt status=$statusForLog failure_reason=${failureReasonForLog ?? '-'} scan_results_count=$scanResultsCount next_delay_ms=${nextDelay.inMilliseconds}',
      );
      await Future.delayed(nextDelay < remaining ? nextDelay : remaining);
    }

    if (!mounted || resolutionVersion != _postFocusResolutionVersion) return;
    _devLog(
      'SCAN_DECISION',
      'decision=show_timeout reason=bounded_retry_exhausted scan_id=$scanId attempts=$attempt ts=${DateTime.now().toIso8601String()}',
    );
    debugPrint(
      '[ScanFlow] post_focus_timeout has_scan_id=${scanId.trim().isNotEmpty}',
    );
    _showPostFocusTimeout();
  }

  Future<WellnessScanStatus?> _fetchPostFocusStatus(
    String scanId,
    int attempt,
  ) async {
    try {
      return await ScanService.instance.fetchWellnessScanStatus(scanId);
    } catch (e, s) {
      debugPrint(
        '[ScanFlow] post_focus_resolve_status_error has_scan_id=${scanId.trim().isNotEmpty} attempt=$attempt error_type=${e.runtimeType}',
      );
      debugPrint(
        '[ScanFlow] post_focus_resolve_status_stack_present=${s.toString().isNotEmpty}',
      );
      return null;
    }
  }

  Future<bool> _resolveCompletedPostFocusResult({
    required String scanId,
    required int attempt,
    required int scanResultsCount,
    required String? firstResultId,
    required String workspaceId,
    required String membershipId,
    required String effectiveRole,
    required String directusRole,
    required DateTime maxDeadline,
    required int resolutionVersion,
  }) async {
    final consistencyDeadline = DateTime.now().add(
      ScanResultPollingPolicy.completedConsistencyWindow,
    );
    var consistencyAttempt = 0;
    while (mounted &&
        resolutionVersion == _postFocusResolutionVersion &&
        DateTime.now().isBefore(consistencyDeadline) &&
        DateTime.now().isBefore(maxDeadline)) {
      consistencyAttempt++;
      if (firstResultId != null && firstResultId.isNotEmpty) {
        try {
          debugPrint(
            '[SCAN_RESULTS] completed_consistency_direct_lookup has_scan_id=${scanId.trim().isNotEmpty} has_result_id=${firstResultId.trim().isNotEmpty} attempt=$attempt.$consistencyAttempt',
          );
          final directResult = await ScanService.instance.fetchScanResultById(
            firstResultId,
          );
          if (directResult != null) {
            _devLog(
              'SCAN_DECISION',
              'decision=show_result reason=completed_result_visible scan_id=$scanId attempt=$attempt.$consistencyAttempt scan_results_count=$scanResultsCount result_id=${directResult.id} workspace_id=${workspaceId.isEmpty ? '-' : workspaceId} membership_id=${membershipId.isEmpty ? '-' : membershipId} effective_role=${effectiveRole.isEmpty ? '-' : effectiveRole} directus_role=${directusRole.isEmpty ? '-' : directusRole} ts=${DateTime.now().toIso8601String()}',
            );
            debugPrint(
              '[ScanFlow] post_focus_result_found has_scan_id=${scanId.trim().isNotEmpty}',
            );
            _openResultPollingScreen(directResult);
            return true;
          }
        } catch (e, s) {
          debugPrint(
            '[ScanFlow] post_focus_completed_direct_result_error has_scan_id=${scanId.trim().isNotEmpty} attempt=$attempt.$consistencyAttempt has_result_id=${firstResultId.trim().isNotEmpty} error_type=${e.runtimeType}',
          );
          debugPrint(
            '[ScanFlow] post_focus_completed_direct_result_stack_present=${s.toString().isNotEmpty}',
          );
        }
      }

      try {
        final lookup = await ScanService.instance.fetchScanResultLookupForScan(
          scanId,
        );
        final result = lookup.result;
        final directResultId = lookup.firstResultId?.trim();
        if (result != null) {
          _devLog(
            'SCAN_DECISION',
            'decision=show_result reason=completed_result_parsed scan_id=$scanId attempt=$attempt.$consistencyAttempt scan_results_count=${lookup.count} result_id=${result.id} workspace_id=${workspaceId.isEmpty ? '-' : workspaceId} membership_id=${membershipId.isEmpty ? '-' : membershipId} effective_role=${effectiveRole.isEmpty ? '-' : effectiveRole} directus_role=${directusRole.isEmpty ? '-' : directusRole} ts=${DateTime.now().toIso8601String()}',
          );
          debugPrint(
            '[ScanFlow] post_focus_result_found has_scan_id=${scanId.trim().isNotEmpty}',
          );
          _openResultPollingScreen(result);
          return true;
        }
        if (directResultId != null && directResultId.isNotEmpty) {
          final directResult = await ScanService.instance.fetchScanResultById(
            directResultId,
          );
          if (directResult != null) {
            _devLog(
              'SCAN_DECISION',
              'decision=show_result reason=completed_result_visible scan_id=$scanId attempt=$attempt.$consistencyAttempt scan_results_count=${lookup.count} result_id=${directResult.id} workspace_id=${workspaceId.isEmpty ? '-' : workspaceId} membership_id=${membershipId.isEmpty ? '-' : membershipId} effective_role=${effectiveRole.isEmpty ? '-' : effectiveRole} directus_role=${directusRole.isEmpty ? '-' : directusRole} ts=${DateTime.now().toIso8601String()}',
            );
            debugPrint(
              '[ScanFlow] post_focus_result_found has_scan_id=${scanId.trim().isNotEmpty}',
            );
            _openResultPollingScreen(directResult);
            return true;
          }
        }
      } catch (e, s) {
        debugPrint(
          '[ScanFlow] post_focus_completed_lookup_error has_scan_id=${scanId.trim().isNotEmpty} attempt=$attempt.$consistencyAttempt error_type=${e.runtimeType}',
        );
        debugPrint(
          '[ScanFlow] post_focus_completed_lookup_stack_present=${s.toString().isNotEmpty}',
        );
      }

      if (!mounted || resolutionVersion != _postFocusResolutionVersion) {
        return true;
      }
      await Future.delayed(ScanResultPollingPolicy.midPollInterval);
    }

    _devLog(
      'SCAN_DECISION',
      'decision=retry reason=completed_result_not_yet_visible scan_id=$scanId attempt=$attempt ts=${DateTime.now().toIso8601String()}',
    );
    return false;
  }

  void _openResultPollingScreen(ScanResult result) {
    _postFocusResolutionVersion++;
    _devLog(
      'POST_FOCUS',
      'navigate_result_screen ts=${DateTime.now().toIso8601String()} has_scan_id=${_scanId?.trim().isNotEmpty == true} has_result_id=${result.id.trim().isNotEmpty} current_route=${_currentRouteName()}',
    );
    debugPrint(
      '[ScanFlow] final route/result has_scan_id=${_scanId?.trim().isNotEmpty == true}',
    );
    _scanFinished = true;
    _preparingProcess = false;
    final container = ProviderScope.containerOf(context, listen: false);
    Navigator.pushReplacement(
      context,
      fadeSlideRoute(
        ScanDetailsScreen(
          result: result,
          scanId: _scanId,
          markAsLatest: true,
          allowRetry: true,
          retryRequestId: widget.requestId,
          retryForceCompletion: widget.forceCompletion,
        ),
      ),
    );
    unawaited(_completeRequestAfterResultReady(container));
  }

  Future<void> _completeRequestAfterResultReady(
    ProviderContainer container,
  ) async {
    if (widget.requestId == null || _scanId == null) return;
    try {
      final currentRequest = await RequestService.instance.fetchRequestById(
        widget.requestId!,
      );
      if (currentRequest == null) {
        debugPrint(
          '[REQUEST_SCAN_FLOW] completion skipped reason=request_missing has_request_id=${widget.requestId!.trim().isNotEmpty}',
        );
        return;
      }
      final currentStatus = currentRequest.displayStatus.trim().toLowerCase();
      if (currentStatus == 'cancelled' ||
          currentStatus == 'completed' ||
          currentRequest.scanId?.trim().isNotEmpty == true) {
        debugPrint(
          '[REQUEST_SCAN_FLOW] completion skipped reason=request_ineligible has_request_id=${widget.requestId!.trim().isNotEmpty} status=$currentStatus has_scan_id=${currentRequest.scanId?.trim().isNotEmpty == true}',
        );
        return;
      }
      await RequestService.instance.updateRequestStatus(
        requestId: widget.requestId!,
        responseStatus: 'completed',
        scanId: _scanId!,
        workflowStatus: 'completed',
      );
      container.read(refreshTickProvider.notifier).state++;
      container.invalidate(homeDataProvider);
      container.invalidate(homeScansProvider);
      container.invalidate(historyProvider);
      container.invalidate(historyTimelineProvider);
      container.invalidate(ownerHistoryTimelineProvider);
      container.invalidate(profileProvider);
      container.invalidate(usersProvider);
      container.invalidate(incomingRequestsProvider);
      container.invalidate(sentRequestsProvider);
      container.invalidate(alertsProvider);
      container.invalidate(notificationsProvider);
      container.invalidate(unreadNotificationsProvider);
      container.invalidate(exportsProvider);
      container.invalidate(activityEventsProvider);
    } catch (e, s) {
      debugPrint(
        '[REQUEST_SCAN_FLOW] completion update failed error_type=${e.runtimeType}',
      );
      debugPrint(
        '[REQUEST_SCAN_FLOW] stack_present=${s.toString().isNotEmpty}',
      );
    }
  }

  void _retakeVideo() {
    _videoTimer?.cancel();
    _cancelCaptureGapTimer();
    _videoPreparationVersion++;
    setState(() {
      _videoFile = null;
      _thumbnailBytes = null;
      _videoSecondsLeft = _videoSeconds;
      _prefinalizedMediaFuture = null;
      _videoPreparationFuture = null;
      _videoRecording = false;
      _videoStopInProgress = false;
      _videoAutoAdvanced = false;
      _videoPreparationInProgress = false;
      _videoPreparationFailed = false;
      _videoFailureMessage = null;
      _videoStartedAt = null;
      _videoCompletedAt = null;
      _audioStepOpenedAt = null;
      _audioStartedAt = null;
      _audioCompletedAt = null;
      _captureSessionInvalidated = false;
      _captureInvalidationReason = null;
      _captureInvalidationMessage = null;
    });
  }

  void _retakeAudio() {
    _audioTimer?.cancel();
    setState(() {
      _audioFile = null;
      _audioSecondsElapsed = 0;
      _audioAutoStopInProgress = false;
      _audioAutoAdvanced = false;
      _audioFailureMessage = null;
      _audioStartedAt = null;
      _audioCompletedAt = null;
    });
    _armCaptureGapTimer();
  }

  void _retryFinalizeAfterFailure() {
    if (!mounted) return;
    setState(() {
      _finalizeFailed = false;
      _finalizeFailureMessage = null;
      _finalizeFailureTitle = null;
      _submitting = false;
      _preparingProcess = false;
      _workflowFuture = null;
      _prefinalizedMediaFuture = null;
      _workflowStarted = false;
      _workflowSettled = false;
      _backgroundFinalizeFailure = null;
      _backgroundFinalizeFailureStack = null;
      _scanId = null;
      _step = ScanFlowStep.audio;
      _scanFinished = false;
      _postFocusTerminalState = _PostFocusTerminalState.none;
      _postFocusFailureReason = null;
      _postFocusTimeoutTitle = null;
      _postFocusTimeoutMessage = null;
    });
    debugPrint(
      '[SCAN_FINALIZE] retry_ready has_scan_id=${_scanId?.trim().isNotEmpty == true}',
    );
  }

  void _showFinalizeFailureState() {
    _finalizeFailed = true;
    _finalizeFailureMessage =
        'We could not prepare your assessment. Please try again.';
    _finalizeFailureTitle = 'We could not prepare your assessment';
    _scanFinished = true;
    setState(() {});
  }

  void _showPostFocusFailure(String? reason) {
    if (!mounted) return;
    setState(() {
      _postFocusTerminalState = _PostFocusTerminalState.failure;
      _postFocusFailureReason = reason;
      _postFocusTimeoutTitle = 'RETAKE NEEDED';
      _postFocusTimeoutMessage =
          'We could not get a reliable reading. Please retake with your face clearly visible, good lighting, and clear voice.';
      _preparingProcess = false;
      _submitting = false;
      _scanFinished = true;
    });
  }

  void _showPostFocusPending() {
    if (!mounted) return;
    setState(() {
      _postFocusTerminalState = _PostFocusTerminalState.pending;
      _postFocusTimeoutTitle = 'Preparing your result';
      _postFocusTimeoutMessage = "We're reviewing your readiness signals.";
      _postFocusFailureReason = null;
      _preparingProcess = false;
      _submitting = false;
      _scanFinished = true;
    });
  }

  void _showPostFocusTimeout() {
    if (!mounted) return;
    setState(() {
      _postFocusTerminalState = _PostFocusTerminalState.failure;
      _postFocusFailureReason = 'scan_timeout';
      _postFocusTimeoutTitle = 'RETAKE NEEDED';
      _postFocusTimeoutMessage =
          "We couldn't complete a reliable reading in time. Please try again.";
      _preparingProcess = false;
      _submitting = false;
      _scanFinished = true;
    });
  }

  void _restartScanFlow() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      fadeSlideRoute(
        ScanFlowScreen(
          requestId: widget.requestId,
          forceCompletion: widget.forceCompletion,
        ),
      ),
    );
  }

  void _backToHomeOrShell() {
    if (!mounted) return;
    _postFocusResolutionVersion++;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _setStep(ScanFlowStep step) {
    if (!mounted) return;
    setState(() => _step = step);
    debugPrint('[ScanFlow] current flow step=${step.name}');
    if (step == ScanFlowStep.focus) {
      _focusShellVisibleAt ??= DateTime.now();
      debugPrint(
        '[FOCUS_SHELL_VISIBLE] has_scan_id=${_scanId?.trim().isNotEmpty == true} ts=${_focusShellVisibleAt!.toIso8601String()}',
      );
      debugPrint(
        '[SCAN_FLOW] focus_task_screen_visible ts=${DateTime.now().toIso8601String()} has_scan_id=${_scanId?.trim().isNotEmpty == true}',
      );
    }
  }

  bool get _isAudioCaptureActive => _step == ScanFlowStep.audio;

  bool get _isCaptureGapActive =>
      _videoCompletedAt != null &&
      _audioStartedAt == null &&
      !_captureSessionInvalidated;

  bool get _isVideoToAudioGapActive =>
      _videoCompletedAt != null &&
      _audioStartedAt == null &&
      !_captureSessionInvalidated;

  bool _isVideoToAudioGapValid() {
    final completedAt = _videoCompletedAt;
    final startedAt = _audioStartedAt;
    if (completedAt == null) return true;
    if (startedAt != null) {
      final gap = startedAt.difference(completedAt);
      return gap <= const Duration(seconds: 10);
    }
    final elapsed = DateTime.now().difference(completedAt);
    return elapsed <= const Duration(seconds: 10);
  }

  void _armCaptureGapTimer() {
    _captureGapTimer?.cancel();
    if (!_isVideoToAudioGapActive) return;
    final completedAt = _videoCompletedAt;
    if (completedAt == null) return;
    final elapsed = DateTime.now().difference(completedAt);
    final remaining = const Duration(seconds: 10) - elapsed;
    if (remaining.isNegative || remaining == Duration.zero) {
      unawaited(
        _invalidateCaptureSession(
          reason: 'step_gap_timeout',
          message:
              'The scan timed out between steps. Please retake it in one continuous flow.',
        ),
      );
      return;
    }
    _captureGapTimer = Timer(remaining, () {
      if (!mounted || !_isVideoToAudioGapActive) return;
      unawaited(
        _invalidateCaptureSession(
          reason: 'step_gap_timeout',
          message:
              'The scan timed out between steps. Please retake it in one continuous flow.',
        ),
      );
    });
  }

  void _cancelCaptureGapTimer() {
    _captureGapTimer?.cancel();
    _captureGapTimer = null;
  }

  Future<void> _invalidateCaptureSession({
    required String reason,
    required String message,
  }) async {
    if (_captureSessionInvalidated && _captureInvalidationReason == reason) {
      return;
    }
    debugPrint('[CAPTURE_FLOW] capture_invalidated_reason=$reason');
    _cancelCaptureGapTimer();
    _videoTimer?.cancel();
    _audioTimer?.cancel();
    if (_audioRecording) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }
    if (_videoRecording || _videoStopInProgress) {
      try {
        await _cameraController?.stopVideoRecording();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _captureSessionInvalidated = true;
      _captureInvalidationReason = reason;
      _captureInvalidationMessage = message;
      _videoRecording = false;
      _videoStopInProgress = false;
      _videoPreparationInProgress = false;
      _videoPreparationFailed = false;
      _videoFailureMessage = null;
      _audioRecording = false;
      _audioFailureMessage = null;
      _submitting = false;
      _preparingProcess = false;
      _workflowFuture = null;
      _prefinalizedMediaFuture = null;
      _workflowStarted = false;
      _workflowSettled = false;
      _backgroundFinalizeFailure = null;
      _backgroundFinalizeFailureStack = null;
      _audioStartedAt = null;
      _audioCompletedAt = null;
      _videoFile = null;
      _audioFile = null;
      _thumbnailBytes = null;
    });
    _showCaptureInvalidatedMessage();
  }

  void _showCaptureInvalidatedMessage() {
    final message =
        _captureInvalidationMessage ??
        'The scan timed out between steps. Please retake it in one continuous flow.';
    _showError(message);
  }

  Widget _buildCaptureInvalidatedState() {
    return Center(
      child: FailureStateView(
        title: 'RETAKE NEEDED',
        message:
            _captureInvalidationMessage ??
            'The scan timed out between steps. Please retake it in one continuous flow.',
        primaryLabel: 'Retake scan',
        primaryAction: _restartScanFlow,
        secondaryLabel: 'Close',
        secondaryAction: () => Navigator.maybePop(context),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (!widget.forceCompletion || _scanFinished) {
      return true;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ScanTheme.backgroundSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Pre-shift scan in progress',
          style: GoogleFonts.inter(
            color: ScanTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Please complete the pre-shift scan before leaving.',
          style: GoogleFonts.inter(color: ScanTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: GoogleFonts.inter(color: ScanTheme.cyan)),
          ),
        ],
      ),
    );
    return false;
  }

  Future<int> _safeLength(XFile file) async {
    try {
      return await file.length();
    } catch (_) {
      return 0;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _JourneyPill extends StatelessWidget {
  final String label;
  final bool active;
  final bool completed;

  const _JourneyPill({
    required this.label,
    required this.active,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    final color = completed
        ? ScanTheme.teal
        : active
        ? ScanTheme.cyan
        : Colors.white.withOpacity(0.14);
    final textColor = completed || active
        ? ScanTheme.textPrimary
        : ScanTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(active || completed ? 0.16 : 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active || completed
              ? color.withOpacity(0.45)
              : ScanTheme.border,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            completed
                ? Icons.check_circle_outline_rounded
                : active
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 14,
            color: textColor,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidancePill extends StatelessWidget {
  final String label;
  final bool active;

  const _GuidancePill({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? ScanTheme.cyan.withOpacity(0.16)
            : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? ScanTheme.cyan.withOpacity(0.36)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: active ? ScanTheme.textPrimary : ScanTheme.textSecondary,
          fontSize: 11.5,
          fontWeight: active ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
  }
}

class _CaptureStateBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _CaptureStateBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: ScanTheme.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceWaveform extends StatelessWidget {
  final bool active;
  final Color accent;

  const _VoiceWaveform({required this.active, required this.accent});

  @override
  Widget build(BuildContext context) {
    const heights = <double>[14, 22, 30, 18, 26, 34, 20, 28, 16, 24, 32, 18];
    return SizedBox(
      height: 42,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < heights.length; i++) ...[
            AnimatedContainer(
              duration: Duration(milliseconds: 220 + (i * 18)),
              curve: Curves.easeInOut,
              width: 7,
              height: active
                  ? heights[i]
                  : math.max(10.0, heights[i] * 0.45).toDouble(),
              decoration: BoxDecoration(
                color: (active ? accent : ScanTheme.textSecondary).withOpacity(
                  active ? 0.9 : 0.45,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            if (i < heights.length - 1) const SizedBox(width: 5),
          ],
        ],
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  final String text;

  const _ChecklistItem(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: ScanTheme.teal,
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: GoogleFonts.inter(
              color: ScanTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroTrustBadge extends StatelessWidget {
  final String label;

  const _IntroTrustBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ScanTheme.teal.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ScanTheme.teal.withOpacity(0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.shield_outlined, color: ScanTheme.teal, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: ScanTheme.teal,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustBullet extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TrustBullet({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ScanTheme.cyan, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: ScanTheme.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool ready;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.ready,
  });

  @override
  Widget build(BuildContext context) {
    final color = ready ? ScanTheme.teal : ScanTheme.warning;
    return GlassPanel(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withOpacity(0.30)),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: ScanTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    color: ScanTheme.textSecondary,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          StatusPill(label: ready ? 'Ready' : 'Required', color: color),
        ],
      ),
    );
  }
}

class _CameraFrameOverlay extends StatelessWidget {
  final bool recording;
  final int secondsLeft;
  final double phase;

  const _CameraFrameOverlay({
    required this.recording,
    required this.secondsLeft,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    final glow = recording ? ScanTheme.cyan : Colors.white24;
    return Center(
      child: SizedBox(
        width: 286,
        height: 374,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: glow.withOpacity(0.8), width: 2),
                boxShadow: recording
                    ? [
                        BoxShadow(
                          color: ScanTheme.cyan.withOpacity(
                            0.16 + (phase * 0.08),
                          ),
                          blurRadius: 26,
                        ),
                      ]
                    : null,
              ),
            ),
            Positioned(top: 18, left: 18, child: _frameCorner(glow)),
            Positioned(
              top: 18,
              right: 18,
              child: Transform.rotate(angle: 1.5708, child: _frameCorner(glow)),
            ),
            Positioned(
              bottom: 18,
              left: 18,
              child: Transform.rotate(
                angle: -1.5708,
                child: _frameCorner(glow),
              ),
            ),
            Positioned(
              bottom: 18,
              right: 18,
              child: Transform.rotate(angle: 3.1416, child: _frameCorner(glow)),
            ),
            Positioned(
              top: 28 + (phase * 92),
              left: 36,
              right: 36,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      ScanTheme.cyan.withOpacity(recording ? 0.9 : 0.28),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            if (recording)
              Positioned(
                top: 22,
                child: StatusPill(
                  label: 'Hold steady ${secondsLeft}s',
                  color: ScanTheme.danger,
                  icon: Icons.fiber_manual_record_rounded,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _frameCorner(Color color) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: color, width: 3),
          left: BorderSide(color: color, width: 3),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _CountdownRing extends StatelessWidget {
  final double progress;
  final String label;
  final Color color;

  const _CountdownRing({
    required this.progress,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress.clamp(0, 1),
            strokeWidth: 5,
            backgroundColor: Colors.white10,
            color: color,
          ),
          Text(
            label,
            style: GoogleFonts.inter(
              color: ScanTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MicOrb extends StatelessWidget {
  final bool recording;

  const _MicOrb({required this.recording});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 108,
      height: 108,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            (recording ? ScanTheme.danger : ScanTheme.cyan).withOpacity(0.22),
            Colors.transparent,
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.05),
            border: Border.all(
              color: (recording ? ScanTheme.danger : ScanTheme.cyan)
                  .withOpacity(0.35),
            ),
          ),
          child: Icon(
            Icons.mic_rounded,
            color: recording ? ScanTheme.danger : ScanTheme.cyan,
            size: 30,
          ),
        ),
      ),
    );
  }
}
