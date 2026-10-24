import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/safe_debug_log.dart';

import '../models/scan_result.dart';
import '../models/wellar_v2_result.dart';
import '../services/scan_service.dart';
import '../state/app_providers.dart';
import '../utils/page_transition.dart';
import '../utils/dashboard_navigation.dart';
import '../utils/scan_result_display.dart';
import '../widgets/responsive_card_grid.dart';
import 'scan/scan_premium_components.dart';
import 'scan_flow_impl_normalized.dart';

enum _ResultLoadState { loading, ready, timeout, failed }

class ScanDetailsScreen extends StatefulWidget {
  final ScanResult? result;
  final WellarV2Result? v2Result;
  final String? scanId;
  final bool markAsLatest;
  final bool allowRetry;
  final String? retryRequestId;
  final bool retryForceCompletion;
  final bool immediateMode;
  final Duration? maxInitialWait;

  const ScanDetailsScreen({
    super.key,
    this.result,
    this.v2Result,
    this.scanId,
    this.markAsLatest = false,
    this.allowRetry = false,
    this.retryRequestId,
    this.retryForceCompletion = false,
    this.immediateMode = false,
    this.maxInitialWait,
  });

  @override
  State<ScanDetailsScreen> createState() => _ScanDetailsScreenState();
}

class _ScanDetailsScreenState extends State<ScanDetailsScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _fastPollInterval = Duration(seconds: 2);
  static const Duration _slowPollInterval = Duration(seconds: 4);
  static const Duration _fastPollWindow = Duration(seconds: 60);
  static const Duration _defaultMaxPollDuration = Duration(seconds: 45);
  static const Duration _defaultCompletedResultFetchWindow = Duration(
    seconds: 20,
  );
  static const Duration _completedResultFetchInterval = Duration(seconds: 2);
  static const int _maxTransientNetworkErrors = 5;
  static const int _fallbackResultStartAttempt = 16;
  static const int _fallbackResultEveryAttempts = 5;

  ScanResult? _result;
  _ResultLoadState _state = _ResultLoadState.loading;
  Timer? _pollTimer;
  bool _pollInFlight = false;
  bool _terminalStateReached = false;
  bool _resolvingCompleted = false;
  String? _activePollingScanId;
  int _pollAttempts = 0;
  int _networkErrors = 0;
  DateTime? _pollStartedAt;
  DateTime? _completedAt;
  String? _failureReason;
  String? _timeoutTitle;
  String? _timeoutMessage;
  String? _loadingMessage;
  late final AnimationController _revealController;
  String? _lastAppliedResultId;
  String? _lastLoggedResultId;

  Duration get _effectiveMaxPollDuration => widget.immediateMode
      ? (widget.maxInitialWait ?? const Duration(seconds: 10))
      : _defaultMaxPollDuration;

  Duration get _effectiveCompletedResultFetchWindow => widget.immediateMode
      ? const Duration(seconds: 8)
      : _defaultCompletedResultFetchWindow;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    if (widget.v2Result != null) {
      _state = _ResultLoadState.ready;
      _revealController.forward(from: 0);
    } else if (widget.result != null) {
      if (kDebugMode) {
        safeDebugLog(
          '[POST_FOCUS] result_screen_init has_result=true has_scan_id=${widget.result!.scanId.trim().isNotEmpty} immediate_mode=${widget.immediateMode}',
        );
      }
      _applyInitialResult(widget.result!);
    } else if (widget.scanId != null && widget.scanId!.isNotEmpty) {
      if (kDebugMode) {
        safeDebugLog(
          '[POST_FOCUS] result_screen_init has_result=false has_scan_id=${widget.scanId?.trim().isNotEmpty == true} immediate_mode=${widget.immediateMode}',
        );
      }
      safeDebugLog(
        '[RESULT_UX] resume_existing_scan has_scan_id=${widget.scanId?.trim().isNotEmpty == true}',
      );
      _startPolling();
    } else {
      _state = _ResultLoadState.timeout;
      _timeoutTitle = 'Result is not available';
      _timeoutMessage = 'The readiness result could not be loaded right now.';
    }
  }

  @override
  void dispose() {
    _stopPolling(markTerminal: true);
    _revealController.dispose();
    super.dispose();
  }

  void _startPolling() {
    if (_pollTimer != null &&
        _activePollingScanId == widget.scanId &&
        !_terminalStateReached) {
      safeDebugLog(
        '[RESULT] polling already active has_scan_id=${widget.scanId?.trim().isNotEmpty == true}',
      );
      return;
    }
    if (kDebugMode) {
      safeDebugLog(
        '[POST_FOCUS] result_poll_start has_scan_id=${widget.scanId?.trim().isNotEmpty == true} immediate_mode=${widget.immediateMode}',
      );
    }
    safeDebugLog(
      '[RESULT] poll_start has_scan_id=${widget.scanId?.trim().isNotEmpty == true}',
    );
    if (widget.immediateMode) {
      safeDebugLog(
        '[RESULT] post_focus_result_check_start has_scan_id=${widget.scanId?.trim().isNotEmpty == true}',
      );
    }
    _stopPolling();
    _pollAttempts = 0;
    _networkErrors = 0;
    _loadingMessage = null;
    _pollStartedAt = DateTime.now();
    _activePollingScanId = widget.scanId;
    _terminalStateReached = false;
    _resolvingCompleted = false;
    unawaited(_pollOnce());
    _scheduleNextPoll();
  }

  void _applyInitialResult(ScanResult result) {
    if (!mounted) return;
    _result = result;
    _lastAppliedResultId = result.id;
    _state = _ResultLoadState.ready;
    safeDebugLog(
      '[RESULT] ready has_scan_id=${result.scanId.trim().isNotEmpty}',
    );
    safeDebugLog(
      '[RESULT] render_result has_scan_id=${result.scanId.trim().isNotEmpty} has_risk_level=${result.overallState.trim().isNotEmpty} has_confidence=${result.confidence != null}',
    );
    if (widget.immediateMode) {
      safeDebugLog(
        '[RESULT] result_found has_scan_id=${result.scanId.trim().isNotEmpty}',
      );
    }
    _revealController.forward(from: 0);
    if (widget.markAsLatest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncResultToProviders(result);
      });
    }
  }

  Future<void> _pollOnce() async {
    if (!mounted ||
        widget.scanId == null ||
        _terminalStateReached ||
        _state == _ResultLoadState.ready) {
      return;
    }
    if (_pollInFlight) {
      safeDebugLog(
        '[RESULT] duplicate poll skipped has_scan_id=${widget.scanId?.trim().isNotEmpty == true}',
      );
      return;
    }
    _pollInFlight = true;
    _pollAttempts++;
    final pollElapsed = _pollStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(_pollStartedAt!);

    try {
      final scan = await ScanService.instance.fetchWellnessScanStatus(
        widget.scanId!,
      );
      _completedAt = scan.completedAt ?? _completedAt;
      safeDebugLog(
        '[RESULT] poll_attempt=$_pollAttempts has_scan_id=${widget.scanId?.trim().isNotEmpty == true} status=${scan.status}',
      );
      if (_pollAttempts % 5 == 0) {
        safeDebugLog(
          '[RESULT] status checkpoint has_scan_id=${widget.scanId?.trim().isNotEmpty == true} attempt=$_pollAttempts status=${scan.status}',
        );
      }
      _updateProgressState(pollElapsed);
      _networkErrors = 0;
      if (scan.isFailed) {
        safeDebugLog(
          '[RESULT] failed_detected has_scan_id=${widget.scanId?.trim().isNotEmpty == true} has_failure_reason=${scan.failureReason?.trim().isNotEmpty == true}',
        );
        if (widget.immediateMode) {
          safeDebugLog(
            '[RESULT] failed_status_found has_scan_id=${widget.scanId?.trim().isNotEmpty == true} has_failure_reason=${scan.failureReason?.trim().isNotEmpty == true}',
          );
        }
        _setFailedState(scan.failureReason);
        return;
      }
      if (scan.isCompleted) {
        safeDebugLog(
          '[RESULT] completed_detected has_scan_id=${widget.scanId?.trim().isNotEmpty == true}',
        );
        await _resolveCompletedScan();
        return;
      }
      if (await _tryResolveResultFallback()) {
        return;
      }
      if (pollElapsed >= const Duration(seconds: 30) &&
          pollElapsed.inSeconds % 10 < _nextPollInterval().inSeconds) {
        safeDebugLog(
          '[RESULT_UX] long_processing has_scan_id=${widget.scanId?.trim().isNotEmpty == true} elapsed_seconds=${pollElapsed.inSeconds}',
        );
      }
      if (pollElapsed >= _effectiveMaxPollDuration) {
        await _handleTimeout();
      }
    } on DioException catch (e) {
      if (_isTransientNetworkError(e)) {
        _networkErrors++;
        safeDebugLog(
          '[RESULT] transient_network_error has_scan_id=${widget.scanId?.trim().isNotEmpty == true} count=$_networkErrors error_type=${e.type}',
        );
        if (!mounted) return;
        setState(() {
          _loadingMessage = 'Connection issue. Retrying...';
        });
        if (_networkErrors >= _maxTransientNetworkErrors) {
          _setTimeoutState(
            title: 'Connection problem',
            message:
                'We could not check your scan result. Please check your internet connection and try again.',
          );
        } else if (pollElapsed >= _effectiveMaxPollDuration) {
          await _handleTimeout();
        }
      } else {
        _setTimeoutState(
          title: 'Processing check delayed',
          message:
              'The assessment is still being prepared. You can retry the check or start a fresh scan.',
        );
      }
    } catch (e) {
      safeDebugLog(
        '[RESULT] poll unexpected error has_scan_id=${widget.scanId?.trim().isNotEmpty == true} error_type=${e.runtimeType}',
      );
      _setTimeoutState(
        title: 'Connection problem',
        message:
            'We could not check your scan result. Please check your internet connection and try again.',
      );
    } finally {
      _pollInFlight = false;
      if (!_terminalStateReached &&
          mounted &&
          _state == _ResultLoadState.loading) {
        _scheduleNextPoll();
      }
    }
  }

  Future<void> _resolveCompletedScan() async {
    if (_resolvingCompleted || widget.scanId == null) return;
    _resolvingCompleted = true;
    _stopPolling(markTerminal: true);
    try {
      final deadline = DateTime.now().add(_effectiveCompletedResultFetchWindow);
      while (DateTime.now().isBefore(deadline)) {
        safeDebugLog(
          '[RESULT] fetch_scan_result_start has_scan_id=${widget.scanId?.trim().isNotEmpty == true}',
        );
        final result = await ScanService.instance.fetchScanResultForScan(
          widget.scanId!,
        );
        if (result != null) {
          safeDebugLog(
            '[RESULT] fetch_scan_result_success has_scan_id=${widget.scanId?.trim().isNotEmpty == true} has_result_id=${result.id.trim().isNotEmpty}',
          );
          if (widget.immediateMode) {
            safeDebugLog(
              '[RESULT] result_found has_scan_id=${widget.scanId?.trim().isNotEmpty == true}',
            );
          }
          _setResult(result);
          return;
        }
        safeDebugLog(
          '[RESULT] fetch_scan_result_empty_retry has_scan_id=${widget.scanId?.trim().isNotEmpty == true}',
        );
        await Future.delayed(_completedResultFetchInterval);
      }
      _setTimeoutState(
        title: 'Final assessment is still syncing',
        message:
            'Your assessment completed, but the result record is not available yet. Please check again shortly.',
      );
    } catch (e) {
      safeDebugLog(
        '[RESULT] fetch completed result failed has_scan_id=${widget.scanId?.trim().isNotEmpty == true} error_type=${e.runtimeType}',
      );
      _setTimeoutState(
        title: 'Connection problem',
        message:
            'We could not check your scan result. Please check your internet connection and try again.',
      );
    } finally {
      _resolvingCompleted = false;
    }
  }

  Future<bool> _tryResolveResultFallback() async {
    if (widget.scanId == null) return false;
    if (_pollAttempts < _fallbackResultStartAttempt) return false;
    if (_pollAttempts % _fallbackResultEveryAttempts != 0) return false;
    try {
      safeDebugLog(
        '[RESULT] fallback_scan_results_lookup has_scan_id=${widget.scanId?.trim().isNotEmpty == true} attempt=$_pollAttempts',
      );
      final result = await ScanService.instance.fetchScanResultForScan(
        widget.scanId!,
      );
      if (result != null) {
        safeDebugLog(
          '[RESULT] fetch_scan_result_success has_scan_id=${widget.scanId?.trim().isNotEmpty == true} has_result_id=${result.id.trim().isNotEmpty}',
        );
        if (widget.immediateMode) {
          safeDebugLog(
            '[RESULT] result_found has_scan_id=${widget.scanId?.trim().isNotEmpty == true}',
          );
        }
        _setResult(result);
        return true;
      }
      safeDebugLog(
        '[RESULT] fetch_scan_result_empty_retry has_scan_id=${widget.scanId?.trim().isNotEmpty == true}',
      );
    } catch (e) {
      safeDebugLog(
        '[RESULT] fallback_scan_results_failed has_scan_id=${widget.scanId?.trim().isNotEmpty == true} error_type=${e.runtimeType}',
      );
    }
    return false;
  }

  Future<void> _handleTimeout() async {
    _stopPolling(markTerminal: true);
    if (widget.scanId == null) {
      _setTimeoutState(
        title: 'This is taking longer than expected',
        message:
            'Your assessment is still being processed. You can check again or start a new scan.',
      );
      return;
    }
    try {
      final scan = await ScanService.instance.fetchWellnessScanStatus(
        widget.scanId!,
      );
      _completedAt = scan.completedAt ?? _completedAt;
      safeDebugLog(
        '[RESULT] timeout final check has_scan_id=${widget.scanId?.trim().isNotEmpty == true} status=${scan.status} has_failure_reason=${scan.failureReason?.trim().isNotEmpty == true}',
      );
      if (scan.isFailed) {
        _setFailedState(scan.failureReason);
        return;
      }
      if (scan.isCompleted) {
        await _resolveCompletedScan();
        return;
      }
    } catch (_) {}
    if (widget.scanId != null) {
      try {
        safeDebugLog(
          '[RESULT] timeout_scan_results_lookup has_scan_id=${widget.scanId?.trim().isNotEmpty == true}',
        );
        final result = await ScanService.instance.fetchScanResultForScan(
          widget.scanId!,
        );
        if (result != null) {
          safeDebugLog(
            '[RESULT] timeout_scan_results_hit has_scan_id=${widget.scanId?.trim().isNotEmpty == true} has_result_id=${result.id.trim().isNotEmpty}',
          );
          if (widget.immediateMode) {
            safeDebugLog(
              '[RESULT] result_found has_scan_id=${widget.scanId?.trim().isNotEmpty == true}',
            );
          }
          _setResult(result);
          return;
        }
      } catch (e) {
        safeDebugLog(
          '[RESULT] timeout_scan_results_failed has_scan_id=${widget.scanId?.trim().isNotEmpty == true} error_type=${e.runtimeType}',
        );
      }
    }
    if (widget.immediateMode) {
      safeDebugLog(
        '[RESULT] post_focus_timeout has_scan_id=${widget.scanId?.trim().isNotEmpty == true}',
      );
      _setTimeoutState(
        title: 'RETAKE NEEDED',
        message:
            "We couldn't complete a reliable reading in time. Please try again.",
      );
      return;
    }
    _setTimeoutState(
      title: 'RETAKE NEEDED',
      message:
          "We couldn't complete a reliable reading in time. Please try again.",
    );
  }

  void _setResult(ScanResult result) {
    if (!mounted) return;
    if (_lastAppliedResultId == result.id && _state == _ResultLoadState.ready) {
      return;
    }
    _result = result;
    _lastAppliedResultId = result.id;
    _state = _ResultLoadState.ready;
    safeDebugLog(
      '[RESULT] ready has_scan_id=${result.scanId.trim().isNotEmpty}',
    );
    safeDebugLog(
      '[RESULT] render_result has_scan_id=${result.scanId.trim().isNotEmpty} has_risk_level=${result.overallState.trim().isNotEmpty} has_confidence=${result.confidence != null}',
    );
    if (widget.immediateMode) {
      safeDebugLog(
        '[RESULT] result_found has_scan_id=${result.scanId.trim().isNotEmpty}',
      );
    }
    if (widget.markAsLatest) {
      _syncResultToProviders(result);
    }
    _revealController.forward(from: 0);
    setState(() {});
  }

  void _syncResultToProviders(ScanResult result) {
    if (!mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    safeDebugLog(
      '[RESULT_REFRESH] invalidating owner dashboard providers has_scan_id=${result.scanId.trim().isNotEmpty}',
    );
    safeDebugLog(
      '[RESULT_REFRESH] invalidating owner readiness distribution has_scan_id=${result.scanId.trim().isNotEmpty}',
    );
    container.read(latestScanResultProvider.notifier).state = result;
    container.read(refreshTickProvider.notifier).state++;
    container.invalidate(homeDataProvider);
    container.invalidate(homeScansProvider);
    container.invalidate(historyProvider);
    container.invalidate(ownerHistoryTimelineProvider);
    container.invalidate(profileProvider);
    container.invalidate(usersProvider);
    container.invalidate(sentRequestsProvider);
    container.invalidate(incomingRequestsProvider);
    container.invalidate(notificationsProvider);
    container.invalidate(unreadNotificationsProvider);
    container.invalidate(alertsProvider);
    container.invalidate(exportsProvider);
    container.invalidate(activityEventsProvider);
  }

  void _setFailedState(String? reason) {
    if (!mounted) return;
    _stopPolling(markTerminal: true);
    _failureReason = reason;
    safeDebugLog(
      '[RESULT] failed has_scan_id=${widget.scanId?.trim().isNotEmpty == true} has_failure_reason=${reason?.trim().isNotEmpty == true}',
    );
    setState(() => _state = _ResultLoadState.failed);
  }

  void _setTimeoutState({required String title, required String message}) {
    if (!mounted) return;
    _stopPolling(markTerminal: true);
    _timeoutTitle = title;
    _timeoutMessage = message;
    _loadingMessage = null;
    setState(() => _state = _ResultLoadState.timeout);
  }

  void _stopPolling({bool markTerminal = false}) {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInFlight = false;
    _activePollingScanId = null;
    if (markTerminal) {
      _terminalStateReached = true;
    }
  }

  void _scheduleNextPoll() {
    _pollTimer?.cancel();
    final interval = _nextPollInterval();
    _pollTimer = Timer(interval, () => unawaited(_pollOnce()));
  }

  void _updateProgressState(Duration elapsed) {
    final progressState = switch (elapsed.inSeconds) {
      < 8 => 'uploading',
      < 20 => 'preparing',
      < 60 => 'analyzing',
      < 120 => 'finalizing',
      _ => 'almost_ready',
    };
    safeDebugLog('[RESULT_UX] progress_state=$progressState');
    final nextMessage = switch (progressState) {
      'uploading' => 'Uploading scan media',
      'preparing' => 'Preparing analysis',
      'analyzing' => 'Analysis in progress',
      'finalizing' => 'Finalizing assessment',
      _ => 'Almost ready',
    };
    if (_loadingMessage == nextMessage) return;
    if (!mounted || _state != _ResultLoadState.loading) {
      _loadingMessage = nextMessage;
      return;
    }
    setState(() {
      _loadingMessage = nextMessage;
    });
  }

  Duration _nextPollInterval() {
    final startedAt = _pollStartedAt;
    if (startedAt == null) return _fastPollInterval;
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < _fastPollWindow) return _fastPollInterval;
    return _slowPollInterval;
  }

  bool _isTransientNetworkError(DioException e) {
    if (e.response != null) return false;
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout;
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScanScaffold(
      stepLabel: _state == _ResultLoadState.ready
          ? 'Readiness assessment'
          : 'Preparing your result',
      onBack: _backToShellRoot,
      body: switch (_state) {
        _ResultLoadState.loading => _buildProcessing(),
        _ResultLoadState.timeout => _buildTimeout(),
        _ResultLoadState.failed => _buildFailure(),
        _ResultLoadState.ready => _buildResult(),
      },
    );
  }

  Widget _buildProcessing() {
    return Center(
      child: GlassPanel(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ScanTheme.cyan.withValues(alpha: 0.34),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: ScanTheme.cyan.withValues(alpha: 0.18),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: ScanTheme.cyan,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preparing your result',
                        style: GoogleFonts.spaceGrotesk(
                          color: ScanTheme.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'We are reviewing your readiness signals.',
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
            const SizedBox(height: 20),
            Text(
              'Please keep this screen open while we prepare the final assessment.',
              style: GoogleFonts.inter(
                color: ScanTheme.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ScanSecondaryButton(
                label: 'Back to dashboard',
                onPressed: _backToShellRoot,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeout() {
    return Center(
      child: FailureStateView(
        title: _timeoutTitle ?? 'RETAKE NEEDED',
        message:
            _timeoutMessage ??
            "We couldn't complete a reliable reading in time. Please try again.",
        primaryLabel: 'Retake assessment',
        primaryAction: () {
          _startFreshScan();
        },
        secondaryLabel: 'Back to dashboard',
        secondaryAction: _backToShellRoot,
      ),
    );
  }

  Widget _buildFailure() {
    return Center(
      child: FailureStateView(
        title: 'RETAKE NEEDED',
        message:
            'We could not get a reliable reading. Please retake with your face clearly visible, good lighting, and clear voice.',
        primaryLabel: 'Retake assessment',
        primaryAction: _startFreshScan,
        secondaryLabel: 'Back to dashboard',
        secondaryAction: _backToShellRoot,
      ),
    );
  }

  Widget _buildResult() {
    final v2Result = widget.v2Result;
    if (v2Result != null) return _buildV2Result(v2Result);
    final result = _result!;
    _logResultFields(result);
    final statusLabel = displayRiskLevelLabel(result.riskLevel);
    final scanTime = result.completedAt ?? _completedAt ?? result.dateCreated;
    final retakeRequired = _isRetakeRequiredResult(result, statusLabel);
    final prominentStatus = retakeRequired
        ? 'Unavailable - please retake the scan'
        : _prominentStatusLabel(statusLabel);
    final primaryMessage = retakeRequired
        ? 'We could not get a reliable reading. Please retake with your face clearly visible, good lighting, and clear voice.'
        : _whatThisMeansBody(statusLabel);
    final influenceNotes = _employeeWhyResultBullets(
      result,
      statusLabel,
      retakeRequired: retakeRequired,
    );
    final statusColor = retakeRequired
        ? ScanTheme.textSecondary
        : _resultStatusColor(statusLabel);
    final ctas = _resultCtas(statusLabel, retakeRequired: retakeRequired);
    final readinessScore = _readinessScoreForDisplay(result);
    final scoreLabel = _formatPercent(readinessScore) ?? '-';
    final confidenceLabel = _formatPercent(result.confidence);
    final cameraLabel = _formatPercent(result.cameraConfidence);
    final voiceLabel = _formatPercent(result.voiceConfidence);
    final taskDisplay = _focusTaskScoreDisplay(result);
    final recommendation = _bestText(
      result.recommendedAction ?? result.suggestedAction,
      _defaultActionForState(statusLabel),
    );
    final explanation = _bestText(
      result.explanation ??
          result.readinessSummary ??
          result.operationalSummary,
      _explanationFallback(statusLabel),
    );
    final technicalMetrics = visibleSignalMetrics(result);
    final assessmentDetails = assessmentDetailsForDisplay(result);
    safeDebugLog(
      '[RESULT_UI] status_label=$statusLabel retake_required=$retakeRequired',
    );

    return FadeTransition(
      opacity: _revealController,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAnimatedSection(
              begin: 0.00,
              end: 0.16,
              child: _ResultSummaryCard(
                statusLabel: prominentStatus,
                statusColor: statusColor,
                conclusion: primaryMessage,
                completionTime: _formatDate(scanTime),
                retakeRequired: retakeRequired,
                scoreLabel: scoreLabel,
              ),
            ),
            const SizedBox(height: 12),
            _buildAnimatedSection(
              begin: 0.16,
              end: 0.30,
              child: _ResultMetricsCard(
                scoreLabel: scoreLabel,
                riskLabel: prominentStatus,
                confidenceLabel: confidenceLabel,
                cameraLabel: cameraLabel,
                voiceLabel: voiceLabel,
                taskLabel: taskDisplay.score != null
                    ? _formatPercent(taskDisplay.score)
                    : null,
              ),
            ),
            if (retakeRequired) ...[
              const SizedBox(height: 12),
              _buildAnimatedSection(
                begin: 0.30,
                end: 0.44,
                child: _PlainSectionCard(
                  title: 'What to improve',
                  body: '',
                  accent: ScanTheme.warning,
                  footer: Column(
                    children: influenceNotes
                        .take(3)
                        .map(
                          (bullet) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _WhyResultBullet(text: bullet),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              _buildAnimatedSection(
                begin: 0.30,
                end: 0.44,
                child: _PlainSectionCard(
                  title: 'What this means',
                  body: explanation,
                  accent: statusColor,
                ),
              ),
              const SizedBox(height: 12),
              _buildAnimatedSection(
                begin: 0.44,
                end: 0.58,
                child: _PlainSectionCard(
                  title: 'Recommended action',
                  body: recommendation,
                  accent: ScanTheme.primaryBlue,
                ),
              ),
            ],
            if (retakeRequired) ...[
              const SizedBox(height: 12),
              _buildAnimatedSection(
                begin: 0.44,
                end: 0.58,
                child: _PlainSectionCard(
                  title: 'Recommended next step',
                  body: recommendation,
                  accent: ScanTheme.primaryBlue,
                ),
              ),
            ],
            if (technicalMetrics.isNotEmpty ||
                assessmentDetails.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildAnimatedSection(
                begin: 0.58,
                end: 0.74,
                child: _TechnicalDetailsCard(
                  scoreLabel: scoreLabel,
                  confidenceLabel: confidenceLabel,
                  completionTime: _formatDate(scanTime),
                  metrics: technicalMetrics,
                  details: assessmentDetails,
                  aiModelVersion: result.aiModelVersion,
                ),
              ),
            ],
            const SizedBox(height: 16),
            ScanPrimaryButton(
              label: ctas.primaryLabel,
              onPressed: ctas.primaryRetake
                  ? _startFreshScan
                  : _backToShellRoot,
            ),
            if (ctas.secondaryLabel != null) ...[
              const SizedBox(height: 10),
              ScanSecondaryButton(
                label: ctas.secondaryLabel!,
                onPressed: ctas.secondaryRetake
                    ? _startFreshScan
                    : _backToShellRoot,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildV2Result(WellarV2Result result) {
    final indicator = result.drowsinessIndicator;
    final quality = result.quality;
    final videoQuality = quality['video']?.toString();
    final audioQuality = quality['audio']?.toString();
    final indicatorQuality = indicator['status']?.toString();
    final qualityLabel = [videoQuality, audioQuality]
        .where((value) => value != null && value.trim().isNotEmpty)
        .join(' · ');
    final effectiveQuality = qualityLabel.isNotEmpty
        ? qualityLabel
        : (indicatorQuality ?? 'unavailable');
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final stateEnglish = indicatorQuality == 'insufficient_quality'
        ? 'Unavailable'
        : switch (indicator['state']?.toString().toLowerCase()) {
            'stable' => 'Stable',
            'low focus' || 'low_focus' => 'Low focus',
            'elevated fatigue' || 'elevated_fatigue' => 'Elevated fatigue',
            'high risk' || 'high_risk' => 'High risk',
            _ => 'Unavailable',
          };
    final insufficient = indicatorQuality == 'insufficient_quality' ||
        stateEnglish == 'Unavailable';
    final state = isArabic
        ? switch (stateEnglish) {
            'Stable' => 'مستقر',
            'Low focus' => 'انخفاض التركيز',
            'Elevated fatigue' => 'مؤشرات إرهاق مرتفعة',
            'High risk' => 'مؤشرات مرتفعة',
            _ => 'القراءة غير متاحة',
          }
        : stateEnglish;
    final statusColor = insufficient
        ? ScanTheme.textSecondary
        : _stateColor(stateEnglish);
    final explanatoryCopy = insufficient
        ? (isArabic
              ? 'الإشارات المتاحة غير كافية لعرض قراءة. حسّن الإضاءة وثبّت الكاميرا وأعد الفحص إذا رغبت.'
              : 'The available signals are insufficient for a reading. Improve lighting, steady the camera, and retake if you choose.')
        : (isArabic
              ? 'هذه مؤشرات وصفية أولية وليست تشخيصًا أو تنبؤًا مُعتمدًا. استخدمها للاسترشاد فقط.'
              : 'These are indicative descriptive signals, not a diagnosis or validated prediction. Use them as guidance only.');
    final behavioral = result.behavioralEvidence;
    final visibleEvidence = _stringMap(behavioral['visible_fatigue_indicators']);
    final vigilanceEvidence = _stringMap(behavioral['vigilance_indicators']);
    final visibleObservations = _stringMap(visibleEvidence['observations']);
    final visibleReasons = _displayAbstentionReasons(visibleEvidence['abstention_reasons'], isArabic);
    final vigilanceReasons = _displayAbstentionReasons(vigilanceEvidence['abstention_reasons'], isArabic);
    final evidenceMetrics = _displayEvidenceMetrics(visibleObservations, result.measurements, isArabic);
    final predictionDisabled =
        _stringMap(behavioral['model_prediction'])['status'] == 'disabled' ||
        result.predictionExtension['status'] == 'disabled';
    final unverifiedReactionTask =
        _stringMap(result.measurements['vigilance'])['status'] ==
        'observed_unverified';

    return FadeTransition(
      opacity: _revealController,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAnimatedSection(
              begin: 0,
              end: 0.22,
              child: _ResultSummaryCard(
                statusLabel: state,
                statusColor: statusColor,
                conclusion: explanatoryCopy,
                completionTime: 'V2',
                retakeRequired: insufficient,
                scoreLabel: effectiveQuality,
                secondaryInfoLabel: isArabic ? 'جودة الإشارة' : 'Signal quality',
              ),
            ),
            const SizedBox(height: 12),
            _V2EvidenceSection(
              isArabic: isArabic,
              statusColor: statusColor,
              visibleStatus: visibleEvidence['status']?.toString(),
              vigilanceStatus: vigilanceEvidence['status']?.toString(),
              measurements: evidenceMetrics,
              unavailableReasons: [...visibleReasons, ...vigilanceReasons],
              predictionDisabled: predictionDisabled,
              unverifiedReactionTask: unverifiedReactionTask,
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _stringMap(dynamic value) => value is Map
      ? value.map((key, item) => MapEntry(key.toString(), item))
      : const {};

  List<ScanResultMetricDisplay> _displayEvidenceMetrics(
    Map<String, dynamic> observations,
    Map<String, dynamic> measurements,
    bool isArabic,
  ) {
    const labels = <String, (String, String, String)>{
      'short_clip_eye_closure_fraction': ('Short-clip eye closure', 'إغلاق العين خلال المقطع', 'fraction'),
      'blink_rate_per_minute': ('Blink rate', 'معدل الرمش', 'events/min'),
      'blink_event_count': ('Observed blink events', 'مرات الرمش المرصودة', 'events'),
      'face_coverage': ('Face visibility', 'وضوح الوجه', 'fraction'),
      'median_eye_aspect_ratio': ('Eye geometry', 'قياس شكل العين', 'ratio'),
      'median_mouth_aspect_ratio': ('Mouth geometry', 'قياس شكل الفم', 'ratio'),
      'mean_luminance': ('Image brightness', 'إضاءة الصورة', ''),
      'mean_blur_variance': ('Image sharpness', 'حدة الصورة', ''),
    };
    final candidates = <String, dynamic>{...observations};
    final fatigue = _stringMap(measurements['fatigue']);
    candidates.addAll(_stringMap(fatigue['observations']));
    final metrics = <ScanResultMetricDisplay>[];
    for (final entry in labels.entries) {
      final observation = _stringMap(candidates[entry.key]);
      final value = observation['value'];
      if (value is! num || !value.isFinite) continue;
      final formatted = value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(2);
      final units = entry.value.$3;
      metrics.add(
        ScanResultMetricDisplay(
          label: isArabic ? entry.value.$2 : entry.value.$1,
          value: units.isEmpty ? formatted : '$formatted $units',
        ),
      );
    }
    final vigilance = _stringMap(measurements['vigilance']);
    final vigilanceValue = _stringMap(vigilance['value']);
    if (vigilance['status'] == 'observed_unverified') {
      for (final entry in <(String, String, String)>[
        (
          'median_valid_rt_ms',
          'Median reaction time (unverified)',
          'وسيط زمن الاستجابة (غير متحقق)',
        ),
        (
          'p90_valid_rt_ms',
          '90th percentile reaction time (unverified)',
          'المئين 90 لزمن الاستجابة (غير متحقق)',
        ),
      ]) {
        final value = vigilanceValue[entry.$1];
        if (value is num && value.isFinite) {
          metrics.add(ScanResultMetricDisplay(
            label: isArabic ? entry.$3 : entry.$2,
            value: '${value.toStringAsFixed(0)} ms',
          ));
        }
      }
    }
    return metrics;
  }

  List<String> _displayAbstentionReasons(dynamic reasons, bool isArabic) {
    if (reasons is! List) return const [];
    const labels = <String, (String, String)>{
      'reaction_task_measurement_missing': ('No reaction-time task measurement was submitted.', 'مافيش قياس لزمن الاستجابة ضمن نتيجة الفحص.'),
      'sampling_rate_insufficient_for_blink_resolution': ('Video sampling could not resolve blink events.', 'معدل أخذ عينات الفيديو مايسمحش بقياس الرمش بدقة.'),
      'short_clip_eye_closure_unavailable_or_insufficient': ('Eye-closure measurement was unavailable.', 'قياس إغلاق العين غير متاح.'),
      'video_quality_insufficient': ('Video quality did not support this observation.', 'جودة الفيديو ماكفتش للرصد ده.'),
      'image_quality_insufficient': ('Image quality did not support this observation.', 'جودة الصورة ماكفتش للرصد ده.'),
    };
    final displayed = reasons.map((reason) {
      final label = labels[reason.toString()];
      if (label != null) return isArabic ? label.$2 : label.$1;
      return isArabic
          ? 'بعض الملاحظات المطلوبة ماكانتش متاحة في النتيجة دي.'
          : 'Some requested observations were unavailable in this result.';
    });
    return displayed
        .toSet()
        .toList(growable: false);
  }

  void _retryScan() {
    Navigator.pushReplacement(
      context,
      fadeSlideRoute(
        ScanFlowScreen(
          requestId: widget.retryRequestId,
          forceCompletion: widget.retryForceCompletion,
        ),
      ),
    );
  }

  void _backToShellRoot() {
    if (!mounted) return;
    goToDashboard(context);
  }

  void _startFreshScan() {
    Navigator.pushReplacement(
      context,
      fadeSlideRoute(
        ScanFlowScreen(
          requestId: widget.allowRetry ? widget.retryRequestId : null,
          forceCompletion: widget.allowRetry && widget.retryForceCompletion,
        ),
      ),
    );
  }

  void _logResultFields(ScanResult result) {
    if (!kDebugMode) return;
    if (_lastLoggedResultId == result.id) return;
    _lastLoggedResultId = result.id;
    final taskValidated = hasValidatedTaskSignal(result);
    safeDebugLog(
      '[RESULT_FIELD] field=task_signal_validated value=${taskValidated ? 'yes' : 'no'}',
    );
    safeDebugLog(
      '[RESULT_FIELD] has_ai_model_version=${result.aiModelVersion?.trim().isNotEmpty == true} has_baseline_used=${result.baselineUsed != null}',
    );
    safeDebugLog(
      '[RESULT_FIELD] field=confidence_drift_present=${result.confidenceDrift != null}',
    );
    safeDebugLog(
      '[RESULT_FIELD] field=confidence_present=${result.confidence != null}',
    );
    safeDebugLog(
      '[RESULT_FIELD] field=date_created_present=${result.dateCreated != null}',
    );
  }

  String _humanReadableRisk(String state) {
    final v = state.trim().toLowerCase();
    if (v == 'stable') return 'Stable';
    if (v == 'low_focus' || v == 'low focus') return 'Low focus';
    if (v == 'elevated_fatigue' || v == 'elevated fatigue') {
      return 'Elevated fatigue';
    }
    if (v == 'moderate') return 'Moderate';
    if (v == 'high_risk' || v == 'high risk' || v == 'high') return 'High risk';
    if (v == 'critical') return 'Critical';
    if (v.isEmpty) return 'Review needed';
    return v
        .split(RegExp(r'[_\s]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _humanReadableSuggestedAction(String? action) {
    final normalized = action?.trim() ?? '';
    switch (normalized) {
      case 'continue_normal_activity':
        return 'Continue normal activity';
      case 'short_recovery_break':
        return 'Short recovery break';
      case 'repeat_scan':
        return 'Verify readiness / Repeat scan';
      case 'rest_advised':
        return 'Rest advised';
      case 'held_from_task':
        return 'Hold from task';
      case '':
        return '';
      default:
        return normalized;
    }
  }

  double? _taskScoreForDisplay(ScanResult result) {
    final task = result.taskPerformanceScore;
    if (task != null) return task;
    return null;
  }

  double? _readinessScoreForDisplay(ScanResult result) {
    return result.readinessScore;
  }

  String _baselineValueForDisplay(ScanResult result) {
    if (result.baselineUsed != null) {
      return result.baselineUsed! ? 'Used' : 'Not used for this assessment';
    }
    return 'Not recorded';
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'Stable':
        return ScanTheme.teal;
      case 'Low focus':
        return ScanTheme.warning;
      case 'Elevated fatigue':
        return const Color(0xFFF97316);
      case 'Moderate':
        return const Color(0xFFF59E0B);
      case 'High':
      case 'High risk':
        return ScanTheme.danger;
      case 'Critical':
        return const Color(0xFFDC2626);
      default:
        return ScanTheme.primaryBlue;
    }
  }

  String _summaryMessage(String state) {
    switch (state) {
      case 'Stable':
        return 'You appear ready for normal operations.';
      case 'Low focus':
        return 'Your focus signals are slightly reduced.';
      case 'Elevated fatigue':
        return 'Fatigue indicators are elevated. Consider a short rest or review.';
      case 'Moderate':
        return 'Moderate indicators detected. Review readiness before critical work.';
      case 'High':
        return 'High risk indicators detected. Do not continue critical work without review.';
      case 'Critical':
        return 'Critical indicators detected. Stop and escalate for review immediately.';
      case 'High risk':
        return 'High risk indicators detected. Do not continue critical work without review.';
      default:
        return 'The result needs review before critical work continues.';
    }
  }

  String _defaultActionForState(String state) {
    switch (state) {
      case 'Stable':
        return 'Proceed with normal work. Recheck if your condition changes.';
      case 'Low focus':
        return 'Take a short reset, hydrate, and retake the scan if needed.';
      case 'Elevated fatigue':
        return 'Pause and consider supervisor review before critical tasks.';
      case 'Moderate':
        return 'Take a short reset and review readiness before continuing.';
      case 'High':
        return 'Stop and escalate to a supervisor or workspace administrator.';
      case 'Critical':
        return 'Stop immediately and request urgent review.';
      case 'High risk':
        return 'Stop and escalate to a supervisor or workspace administrator.';
      default:
        return 'Retake the scan or request manual review.';
    }
  }

  String _explanationFallback(String state) {
    switch (state) {
      case 'Stable':
        return 'Your scan signals look consistent enough for normal readiness. Continue to monitor how you feel.';
      case 'Low focus':
        return 'Your scan suggests reduced focus. Consider a short pause before starting critical tasks.';
      case 'Elevated fatigue':
        return 'Your scan suggests fatigue indicators are elevated. Rest or supervisor review may be appropriate.';
      case 'Moderate':
        return 'Your scan suggests moderate readiness concerns. A short pause and review may help.';
      case 'High':
        return 'Your scan suggests high risk indicators. Escalate for review before continuing safety-sensitive work.';
      case 'Critical':
        return 'Your scan suggests critical risk indicators. Stop and request urgent review.';
      case 'High risk':
        return 'Your scan suggests high risk indicators. Escalate for review before continuing safety-sensitive work.';
      default:
        return 'Your result is available, but it should be reviewed carefully before critical work.';
    }
  }

  double _normalizeScore(double? value) {
    return _percentToProgress(_normalizePercent(value));
  }

  String? _formatPercent(double? value) {
    final normalized = _normalizePercent(value);
    if (normalized == null) return null;
    return '$normalized%';
  }

  int? _normalizePercent(double? value) {
    if (value == null || !value.isFinite || value < 0) return null;
    if (value <= 1) return (value * 100).round();
    return value.round();
  }

  double _percentToProgress(int? value) {
    if (value == null) return 0;
    return (value / 100).clamp(0, 1);
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _bestText(String? primary, String fallback) {
    final normalized = primary?.trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }

  Color _resultStatusColor(String statusLabel) {
    switch (statusLabel.toLowerCase()) {
      case 'stable':
        return ScanTheme.teal;
      case 'low focus':
        return ScanTheme.warning;
      case 'elevated fatigue':
        return const Color(0xFFF97316);
      case 'moderate':
        return const Color(0xFFF59E0B);
      case 'high risk':
        return ScanTheme.danger;
      case 'critical':
        return const Color(0xFFDC2626);
      default:
        return ScanTheme.primaryBlue;
    }
  }

  Widget _buildAnimatedSection({
    required Widget child,
    required double begin,
    required double end,
  }) {
    return AnimatedBuilder(
      animation: _revealController,
      child: child,
      builder: (context, childWidget) {
        final curve = CurvedAnimation(
          parent: _revealController,
          curve: Interval(begin, end, curve: Curves.easeOutCubic),
        );
        final opacity = curve.value;
        final offset = 16 * (1 - opacity);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, offset),
            child: childWidget,
          ),
        );
      },
    );
  }

  _FocusTaskScoreDisplay _focusTaskScoreDisplay(ScanResult result) {
    final task = _taskScoreForDisplay(result);
    if (task != null) {
      return _FocusTaskScoreDisplay(
        label: _formatPercent(task) ?? 'Completed',
        source: 'task_performance_score',
        score: task,
        logValue: task.toString(),
      );
    }

    return const _FocusTaskScoreDisplay(
      label: 'Completed',
      source: 'completed_only',
      score: null,
      logValue: 'Completed',
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Completion time not recorded';
    final local = date.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[local.month - 1];
    return '${local.day.toString().padLeft(2, '0')} $month ${local.year} • ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _prominentStatusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'stable':
        return 'STABLE';
      case 'low focus':
        return 'LOW FOCUS';
      case 'high risk':
        return 'HIGH RISK';
      default:
        return status.toUpperCase();
    }
  }

  String _humanConfidenceLabel(double? confidence) {
    final percent = _normalizePercent(confidence);
    if (percent == null) return 'Unavailable';
    if (percent < 45) return 'Low confidence';
    if (percent < 70) return 'Moderate confidence';
    return 'High confidence';
  }

  String _whatThisMeansBody(String status) {
    switch (status.trim().toLowerCase()) {
      case 'stable':
        return 'You are ready to continue work.';
      case 'low focus':
        return 'Take a short break, then retake before continuing safety-sensitive work.';
      case 'high risk':
        return 'Do not continue safety-sensitive work. Supervisor review is required.';
      default:
        return 'Do not continue safety-sensitive work. Supervisor review is required.';
    }
  }

  bool _isRetakeRequiredResult(ScanResult result, String statusLabel) {
    if (statusLabel == 'Unavailable - please retake the scan') return true;
    final actionText = [
      result.suggestedAction,
      result.recommendedAction,
    ].whereType<String>().join(' ').toLowerCase();
    final explanationText = [
      result.explanation,
      result.readinessSummary,
      result.operationalSummary,
    ].whereType<String>().join(' ').toLowerCase();
    final wantsRetake =
        actionText.contains('repeat_scan') ||
        actionText.contains('repeat scan') ||
        actionText.contains('retake') ||
        actionText.contains('retry');
    final qualityIssue =
        explanationText.contains('reliable') ||
        explanationText.contains('visibility') ||
        explanationText.contains('lighting') ||
        explanationText.contains('quality') ||
        explanationText.contains('audio') ||
        explanationText.contains('face') ||
        explanationText.contains('blurry') ||
        explanationText.contains('noisy') ||
        explanationText.contains('weak');
    return wantsRetake &&
        qualityIssue;
  }

  String _employeeRecommendedNextStep(
    ScanResult result,
    String statusLabel, {
    required bool retakeRequired,
  }) {
    if (retakeRequired) return 'Retake assessment';
    final action = [result.recommendedAction, result.suggestedAction]
        .whereType<String>()
        .map((v) => v.trim().toLowerCase())
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    switch (action) {
      case 'continue_normal_activity':
        return 'Continue work as normal';
      case 'short_recovery_break':
        return 'Take a short break';
      case 'repeat_scan':
      case 'repeat scan':
        return 'Retake assessment';
      case 'rest_advised':
        return 'Take a short break';
      case 'held_from_task':
        return 'Speak with your supervisor';
    }
    switch (statusLabel.trim().toLowerCase()) {
      case 'stable':
        return 'Continue work as normal';
      case 'low focus':
        return 'Take a short break';
      case 'elevated fatigue':
        return 'Speak with your supervisor';
      default:
        return 'Retake assessment';
    }
  }

  List<String> _employeeWhyResultBullets(
    ScanResult result,
    String statusLabel, {
    required bool retakeRequired,
  }) {
    final bullets = <String>[];
    final camera = _normalizePercent(result.cameraConfidence);
    final voice = _normalizePercent(result.voiceConfidence);
    final task = _normalizePercent(_taskScoreForDisplay(result));
    final explanation = (result.explanation ?? '').toLowerCase();

    void addBullet(String value) {
      if (value.trim().isEmpty ||
          bullets.contains(value) ||
          bullets.length >= 3) {
        return;
      }
      bullets.add(value);
    }

    if (retakeRequired) {
      if (camera != null && camera < 45) {
        addBullet('Make sure your face is clearly visible to the camera');
      }
      if (voice != null && voice < 45) {
        addBullet('Speak clearly in a quiet place');
      }
      if (bullets.isEmpty && explanation.contains('lighting')) {
        addBullet('Move to better lighting before retaking');
      }
      if (bullets.isEmpty) {
        addBullet('Use steady framing, good lighting, and clear voice');
      }
      return bullets.take(2).toList();
    }

    if (statusLabel.trim().toLowerCase() == 'low focus' &&
        task != null &&
        task < 60) {
      addBullet('Your reaction speed was lower than usual');
    }
    if (camera != null) {
      addBullet(
        camera >= 70
            ? 'Your face stayed clearly visible during the camera check'
            : 'Camera clarity affected the reading',
      );
    }
    if (voice != null) {
      addBullet(
        voice >= 70
            ? 'Your voice sample was clear'
            : 'Voice clarity affected the reading',
      );
    }
    if (bullets.length < 3 && statusLabel.trim().toLowerCase() == 'high risk') {
      addBullet(
        'Several readiness signals showed stronger concern than normal',
      );
    }
    if (bullets.length < 3 && statusLabel.trim().toLowerCase() == 'stable') {
      addBullet('Your camera, voice, and task signals were consistent overall');
    }
    if (bullets.isEmpty) {
      addBullet('Your overall scan signals were used to produce this result');
    }
    return bullets.take(3).toList();
  }

  _ResultCtas _resultCtas(String statusLabel, {required bool retakeRequired}) {
    if (retakeRequired) {
      return const _ResultCtas(
        primaryLabel: 'Retake assessment',
        primaryRetake: true,
        secondaryLabel: 'Back to dashboard',
        secondaryRetake: false,
      );
    }

    switch (statusLabel.trim().toLowerCase()) {
      case 'stable':
        return const _ResultCtas(
          primaryLabel: 'Back to dashboard',
          primaryRetake: false,
          secondaryLabel: 'Retake assessment',
          secondaryRetake: true,
        );
      case 'low focus':
        return const _ResultCtas(
          primaryLabel: 'Back to dashboard',
          primaryRetake: false,
          secondaryLabel: 'Retake assessment',
          secondaryRetake: true,
        );
      case 'high risk':
        return const _ResultCtas(
          primaryLabel: 'Back to dashboard',
          primaryRetake: false,
        );
      default:
        return const _ResultCtas(
          primaryLabel: 'Back to dashboard',
          primaryRetake: false,
        );
    }
  }

  int _processingIndex() {
    switch (_loadingMessage) {
      case 'Uploading scan media':
        return 0;
      case 'Preparing analysis':
        return 1;
      case 'Analysis in progress':
        return 2;
      case 'Finalizing assessment':
        return 3;
      case 'Almost ready':
        return 4;
      default:
        return 1;
    }
  }
}

class _ResultSummaryCard extends StatelessWidget {
  final String statusLabel;
  final Color statusColor;
  final String conclusion;
  final String completionTime;
  final bool retakeRequired;
  final String scoreLabel;
  final String secondaryInfoLabel;

  const _ResultSummaryCard({
    required this.statusLabel,
    required this.statusColor,
    required this.conclusion,
    required this.completionTime,
    required this.retakeRequired,
    required this.scoreLabel,
    this.secondaryInfoLabel = 'Readiness score',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            statusColor.withValues(alpha: 0.14),
            const Color(0xFF111826),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.28),
                  ),
                ),
                child: Icon(
                  retakeRequired
                      ? Icons.warning_amber_rounded
                      : Icons.verified_outlined,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusPill(
                      label: retakeRequired ? 'Action required' : 'Completed',
                      color: statusColor,
                      icon: retakeRequired
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      statusLabel,
                      style: GoogleFonts.spaceGrotesk(
                        color: ScanTheme.textPrimary,
                        fontSize: 30,
                        height: 1.0,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conclusion,
                      style: GoogleFonts.inter(
                        color: ScanTheme.textPrimary,
                        fontSize: 14,
                        height: 1.55,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _ResultInlineInfo(
                            icon: Icons.schedule_rounded,
                            label: 'Completed',
                            value: completionTime,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ResultInlineInfo(
                            icon: Icons.assessment_outlined,
                            label: secondaryInfoLabel,
                            value: scoreLabel,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultCtas {
  final String primaryLabel;
  final bool primaryRetake;
  final String? secondaryLabel;
  final bool secondaryRetake;

  const _ResultCtas({
    required this.primaryLabel,
    required this.primaryRetake,
    this.secondaryLabel,
    this.secondaryRetake = false,
  });
}

class _SummaryInfoTile extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _SummaryInfoTile({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: ScanTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              color: accent,
              fontSize: 24,
              height: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultMetricsCard extends StatelessWidget {
  final String scoreLabel;
  final String riskLabel;
  final String? confidenceLabel;
  final String? cameraLabel;
  final String? voiceLabel;
  final String? taskLabel;

  const _ResultMetricsCard({
    required this.scoreLabel,
    required this.riskLabel,
    required this.confidenceLabel,
    required this.cameraLabel,
    required this.voiceLabel,
    required this.taskLabel,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <ResponsiveCardGridItem>[
      ResponsiveCardGridItem(
        child: _ResultMetricTile(
          label: 'Readiness score',
          value: scoreLabel,
          icon: Icons.pie_chart_outline_rounded,
          accent: ScanTheme.cyan,
        ),
      ),
      ResponsiveCardGridItem(
        child: _ResultMetricTile(
          label: 'Risk level',
          value: riskLabel,
          icon: Icons.shield_outlined,
          accent: ScanTheme.warning,
        ),
      ),
      if (confidenceLabel != null)
        ResponsiveCardGridItem(
          child: _ResultMetricTile(
            label: 'Overall confidence',
            value: confidenceLabel!,
            icon: Icons.insights_rounded,
            accent: ScanTheme.primaryBlue,
          ),
        ),
      if (cameraLabel != null)
        ResponsiveCardGridItem(
          child: _ResultMetricTile(
            label: 'Camera confidence',
            value: cameraLabel!,
            icon: Icons.videocam_outlined,
            accent: ScanTheme.teal,
          ),
        ),
      if (voiceLabel != null)
        ResponsiveCardGridItem(
          child: _ResultMetricTile(
            label: 'Voice confidence',
            value: voiceLabel!,
            icon: Icons.mic_none_rounded,
            accent: ScanTheme.cyan,
          ),
        ),
      if (taskLabel != null)
        ResponsiveCardGridItem(
          child: _ResultMetricTile(
            label: 'Task performance',
            value: taskLabel!,
            icon: Icons.bolt_rounded,
            accent: ScanTheme.warning,
          ),
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF111826),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Key metrics',
            style: GoogleFonts.spaceGrotesk(
              color: ScanTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'The most important readiness signals at a glance.',
            style: GoogleFonts.inter(
              color: ScanTheme.textSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          ResponsiveCardGrid(spacing: 10, runSpacing: 10, children: tiles),
        ],
      ),
    );
  }
}

class _ResultMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  const _ResultMetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0.025),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: accent, size: 18)]),
          const SizedBox(height: 14),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceGrotesk(
              color: ScanTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: ScanTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultInlineInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ResultInlineInfo({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: ScanTheme.textSecondary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: ScanTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: ScanTheme.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssessmentDetailsCard extends StatelessWidget {
  final List<ScanAssessmentDetail> details;

  const _AssessmentDetailsCard({required this.details});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111826),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assessment details',
            style: GoogleFonts.spaceGrotesk(
              color: ScanTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          ...details
              .map(
                (detail) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AssessmentDetailRow(detail: detail),
                ),
              )
              .toList(),
        ],
      ),
    );
  }
}

class _AssessmentDetailRow extends StatelessWidget {
  final ScanAssessmentDetail detail;

  const _AssessmentDetailRow({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              detail.label,
              style: GoogleFonts.inter(
                color: ScanTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            detail.value,
            style: GoogleFonts.inter(
              color: ScanTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlainSectionCard extends StatelessWidget {
  final String title;
  final String body;
  final Color accent;
  final Widget? footer;

  const _PlainSectionCard({
    required this.title,
    required this.body,
    required this.accent,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111826),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: GoogleFonts.spaceGrotesk(
                  color: ScanTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (body.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              body,
              style: GoogleFonts.inter(
                color: ScanTheme.textSecondary,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ],
          if (footer != null) ...[const SizedBox(height: 14), footer!],
        ],
      ),
    );
  }
}

class _V2EvidenceSection extends StatelessWidget {
  final bool isArabic;
  final Color statusColor;
  final String? visibleStatus;
  final String? vigilanceStatus;
  final List<ScanResultMetricDisplay> measurements;
  final List<String> unavailableReasons;
  final bool predictionDisabled;
  final bool unverifiedReactionTask;

  const _V2EvidenceSection({
    required this.isArabic,
    required this.statusColor,
    required this.visibleStatus,
    required this.vigilanceStatus,
    required this.measurements,
    required this.unavailableReasons,
    required this.predictionDisabled,
    required this.unverifiedReactionTask,
  });

  String _statusLabel(String? status) => switch (status) {
    'observed' => isArabic ? 'ملاحظات متاحة' : 'Observations available',
    'partial_evidence' => isArabic ? 'ملاحظات جزئية' : 'Partial observations',
    'insufficient_evidence' => isArabic ? 'بيانات غير كافية' : 'Insufficient data',
    'not_provided' => isArabic ? 'غير متاح' : 'Not provided',
    _ => isArabic ? 'غير متاح' : 'Unavailable',
  };

  @override
  Widget build(BuildContext context) {
    final title = isArabic ? 'الملاحظات والقياسات' : 'Observations & measurements';
    final emptyCopy = isArabic
        ? 'مافيش قياسات مدعومة متاحة للعرض في النتيجة دي.'
        : 'No supported measurements are available in this result.';
    final caveat = isArabic
        ? 'دي ملاحظات وصفية فقط، ومش درجة إرهاق أو تشخيص.'
        : 'These are descriptive observations, not a fatigue score or diagnosis.';
    final predictionCopy = isArabic
        ? 'التنبؤ المعتمد بالجاهزية غير مفعّل حاليًا؛ ده مش معناه إن الفحص فشل.'
        : 'Validated readiness prediction is disabled; this does not mean the scan failed.';
    final reactionCopy = isArabic
        ? 'توقيتات الاستجابة مُبلّغ عنها من الجهاز وغير متحقق منها، ومش اختبار يقظة معتمد.'
        : 'Reaction times are client-reported and unverified; this is not a validated vigilance test.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ScanTheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.insights_rounded, color: statusColor, size: 19),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.spaceGrotesk(
                    color: ScanTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _EvidenceStatusChip(
                label: isArabic ? 'المؤشرات الظاهرة' : 'Visible indicators',
                value: _statusLabel(visibleStatus),
              ),
              _EvidenceStatusChip(
                label: isArabic ? 'اليقظة' : 'Vigilance',
                value: _statusLabel(vigilanceStatus),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (measurements.isEmpty)
            Text(
              emptyCopy,
              style: GoogleFonts.inter(
                color: ScanTheme.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            )
          else ...[
            for (var index = 0; index < measurements.length; index++) ...[
              if (index > 0)
                Divider(
                  height: 16,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              _EvidenceMeasurementRow(metric: measurements[index]),
            ],
          ],
          if (unavailableReasons.isNotEmpty) ...[
            const SizedBox(height: 13),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.07)),
            const SizedBox(height: 10),
            for (final reason in unavailableReasons.toSet())
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: ScanTheme.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reason,
                        style: GoogleFonts.inter(
                          color: ScanTheme.textSecondary,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text(
            caveat,
            style: GoogleFonts.inter(
              color: ScanTheme.textSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          if (unverifiedReactionTask) ...[
            const SizedBox(height: 9),
            Text(
              reactionCopy,
              style: GoogleFonts.inter(
                color: ScanTheme.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
          if (predictionDisabled) ...[
            const SizedBox(height: 9),
            Text(
              predictionCopy,
              style: GoogleFonts.inter(
                color: ScanTheme.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EvidenceStatusChip extends StatelessWidget {
  final String label;
  final String value;

  const _EvidenceStatusChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 260),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.035),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(color: ScanTheme.textSecondary, fontSize: 10)),
        const SizedBox(height: 3),
        Text(
          value,
          softWrap: true,
          style: GoogleFonts.inter(
            color: ScanTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _EvidenceMeasurementRow extends StatelessWidget {
  final ScanResultMetricDisplay metric;

  const _EvidenceMeasurementRow({required this.metric});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          metric.label,
          softWrap: true,
          style: GoogleFonts.inter(color: ScanTheme.textSecondary, fontSize: 13),
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          metric.value,
          textAlign: TextAlign.end,
          softWrap: true,
          style: GoogleFonts.inter(
            color: ScanTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _ResultBulletChip extends StatelessWidget {
  final String text;

  const _ResultBulletChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: ScanTheme.textSecondary,
          fontSize: 12,
          height: 1.45,
        ),
      ),
    );
  }
}

class _WhyResultBullet extends StatelessWidget {
  final String text;

  const _WhyResultBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: ScanTheme.primaryBlue,
              shape: BoxShape.circle,
            ),
          ),
        ),
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
    );
  }
}

class _ResultSectionCard extends StatelessWidget {
  final String title;
  final String body;
  final Color accent;

  const _ResultSectionCard({
    required this.title,
    required this.body,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: GoogleFonts.spaceGrotesk(
                  color: ScanTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: GoogleFonts.inter(
              color: ScanTheme.textSecondary,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultActionCard extends StatelessWidget {
  final String title;
  final String body;
  final Color accent;

  const _ResultActionCard({
    required this.title,
    required this.body,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.14),
              Colors.white.withValues(alpha: 0.03),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.spaceGrotesk(
                color: ScanTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: GoogleFonts.inter(
                color: ScanTheme.textSecondary,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalsCard extends StatelessWidget {
  final String cameraConfidence;
  final double cameraProgress;
  final String voiceConfidence;
  final double voiceProgress;
  final String focusTaskLabel;
  final double focusTaskProgress;
  final bool focusTaskMeasured;
  final String confidenceDrift;
  final double confidenceDriftProgress;

  const _SignalsCard({
    required this.cameraConfidence,
    required this.cameraProgress,
    required this.voiceConfidence,
    required this.voiceProgress,
    required this.focusTaskLabel,
    required this.focusTaskProgress,
    required this.focusTaskMeasured,
    required this.confidenceDrift,
    required this.confidenceDriftProgress,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Signals',
            style: GoogleFonts.spaceGrotesk(
              color: ScanTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'These signals help explain the readiness result.',
            style: GoogleFonts.inter(
              color: ScanTheme.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          _SignalMetricRow(
            label: 'Camera confidence',
            value: cameraConfidence,
            color: ScanTheme.primaryBlue,
            progress: cameraProgress,
            measured: cameraConfidence.trim().isNotEmpty,
          ),
          const SizedBox(height: 12),
          _SignalMetricRow(
            label: 'Voice confidence',
            value: voiceConfidence,
            color: ScanTheme.teal,
            progress: voiceProgress,
            measured: voiceConfidence.trim().isNotEmpty,
          ),
          const SizedBox(height: 12),
          _SignalMetricRow(
            label: 'Focus task',
            value: focusTaskLabel,
            color: ScanTheme.warning,
            progress: focusTaskProgress,
            measured: focusTaskMeasured,
          ),
          const SizedBox(height: 12),
          _SignalMetricRow(
            label: 'Confidence drift',
            value: confidenceDrift,
            color: ScanTheme.danger,
            progress: confidenceDriftProgress,
            measured: confidenceDrift.trim().isNotEmpty,
          ),
        ],
      ),
    );
  }
}

class _UserFacingDetailsCard extends StatelessWidget {
  final String confidence;
  final String confidenceDrift;
  final String? aiModelVersion;
  final String baselineUsed;
  final String scanTime;
  final String status;

  const _UserFacingDetailsCard({
    required this.confidence,
    required this.confidenceDrift,
    required this.aiModelVersion,
    required this.baselineUsed,
    required this.scanTime,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Details',
            style: GoogleFonts.spaceGrotesk(
              color: ScanTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _DetailRow(label: 'Status', value: status),
          const SizedBox(height: 8),
          _DetailRow(label: 'Confidence', value: confidence),
          const SizedBox(height: 8),
          _DetailRow(label: 'Confidence drift', value: confidenceDrift),
          if (aiModelVersion?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            _DetailRow(label: 'Model', value: aiModelVersion!.trim()),
          ],
          const SizedBox(height: 8),
          _DetailRow(label: 'Baseline used', value: baselineUsed),
          const SizedBox(height: 8),
          _DetailRow(label: 'Scan time', value: scanTime),
        ],
      ),
    );
  }
}

class _SupportDetailsCard extends StatelessWidget {
  final String scanId;
  final String resultId;
  final String state;

  const _SupportDetailsCard({
    required this.scanId,
    required this.resultId,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          iconColor: ScanTheme.textSecondary,
          collapsedIconColor: ScanTheme.textSecondary,
          title: Text(
            'Support details',
            style: GoogleFonts.inter(
              color: ScanTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            'Collapsed diagnostic context',
            style: GoogleFonts.inter(
              color: ScanTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          children: [
            _DetailRow(label: 'State', value: state),
            const SizedBox(height: 10),
            _DetailRow(label: 'Scan ID', value: scanId),
            const SizedBox(height: 10),
            _DetailRow(label: 'Result ID', value: resultId),
          ],
        ),
      ),
    );
  }
}

class _TechnicalDetailsCard extends StatelessWidget {
  final String scoreLabel;
  final String? confidenceLabel;
  final String completionTime;
  final List<ScanResultMetricDisplay> metrics;
  final List<ScanAssessmentDetail> details;
  final String? aiModelVersion;

  const _TechnicalDetailsCard({
    required this.scoreLabel,
    required this.confidenceLabel,
    required this.completionTime,
    required this.metrics,
    required this.details,
    required this.aiModelVersion,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF111826),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          iconColor: ScanTheme.textSecondary,
          collapsedIconColor: ScanTheme.textSecondary,
          title: Text(
            'Technical details',
            style: GoogleFonts.spaceGrotesk(
              color: ScanTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            'Optional technical summary',
            style: GoogleFonts.inter(
              color: ScanTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          children: [
            _DetailRow(label: 'Readiness score', value: scoreLabel),
            if (confidenceLabel != null) ...[
              const SizedBox(height: 8),
              _DetailRow(label: 'Confidence', value: confidenceLabel!),
            ],
            const SizedBox(height: 8),
            _DetailRow(label: 'Completed', value: completionTime),
            if (aiModelVersion?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              _DetailRow(label: 'Model version', value: aiModelVersion!.trim()),
            ],
            for (final detail in details) ...[
              const SizedBox(height: 8),
              _DetailRow(label: detail.label, value: detail.value),
            ],
            for (final metric in metrics) ...[
              const SizedBox(height: 8),
              _DetailRow(label: metric.label, value: metric.value),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: ScanTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              color: ScanTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SignalMetricRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final double progress;
  final bool measured;

  const _SignalMetricRow({
    required this.label,
    required this.value,
    required this.color,
    required this.progress,
    required this.measured,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  color: ScanTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              value,
              style: GoogleFonts.inter(
                color: measured ? color : ScanTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (measured)
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            tween: Tween<double>(begin: 0, end: progress.clamp(0, 1)),
            builder: (context, value, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: value,
                  backgroundColor: Colors.white.withValues(alpha: 0.04),
                  color: color,
                ),
              );
            },
          )
        else
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: ScanTheme.border),
            ),
          ),
      ],
    );
  }
}

class _FocusTaskScoreDisplay {
  final String label;
  final String source;
  final double? score;
  final String logValue;

  const _FocusTaskScoreDisplay({
    required this.label,
    required this.source,
    required this.score,
    required this.logValue,
  });

  bool get hasScore => score != null;
  double get progress => (score ?? 0) / 100;
}

class _ResultHeroCard extends StatelessWidget {
  final String percent;
  final String state;
  final String statusLabel;
  final String statusCopy;
  final Color color;
  final String confidenceLabel;
  final String completionTime;

  const _ResultHeroCard({
    required this.percent,
    required this.state,
    required this.statusLabel,
    required this.statusCopy,
    required this.color,
    required this.confidenceLabel,
    required this.completionTime,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.24),
              ScanTheme.backgroundSoft.withValues(alpha: 0.94),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                StatusPill(label: statusLabel, color: color),
                StatusPill(
                  label: 'Confidence $confidenceLabel',
                  color: ScanTheme.primaryBlue,
                ),
                const StatusPill(
                  label: 'Secure check',
                  color: ScanTheme.cyan,
                  icon: Icons.verified_user_outlined,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        percent,
                        style: GoogleFonts.spaceGrotesk(
                          color: ScanTheme.textPrimary,
                          fontSize: 54,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        state,
                        style: GoogleFonts.spaceGrotesk(
                          color: color,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        statusCopy,
                        style: GoogleFonts.inter(
                          color: ScanTheme.textPrimary,
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                    border: Border.all(
                      color: color.withValues(alpha: 0.35),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.18),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_rounded, color: color, size: 22),
                      const SizedBox(height: 8),
                      Text(
                        percent,
                        style: GoogleFonts.spaceGrotesk(
                          color: ScanTheme.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Score',
                        style: GoogleFonts.inter(
                          color: ScanTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    color: ScanTheme.textSecondary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Completed $completionTime',
                      style: GoogleFonts.inter(
                        color: ScanTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
