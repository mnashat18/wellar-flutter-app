import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/request_item.dart';
import '../services/organization_service.dart';
import '../services/request_service.dart';
import '../state/app_providers.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/wellar_button.dart';
import '../widgets/wellar_card.dart';
import 'employee_requests_screen.dart';
import 'scan_request_details_screen.dart';

class ScanRequestOpenScreen extends ConsumerStatefulWidget {
  final String scanRequestId;

  const ScanRequestOpenScreen({super.key, required this.scanRequestId});

  @override
  ConsumerState<ScanRequestOpenScreen> createState() =>
      _ScanRequestOpenScreenState();
}

class _ScanRequestOpenScreenState extends ConsumerState<ScanRequestOpenScreen> {
  late Future<_OpenResult> _future;
  bool _openedDetails = false;
  ProviderSubscription<int>? _refreshSubscription;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _refreshSubscription = ref.listenManual<int>(refreshTickProvider, (_, __) {
      if (!mounted) return;
      setState(() {
        _openedDetails = false;
        _future = _load();
      });
    });
  }

  @override
  void dispose() {
    _refreshSubscription?.close();
    super.dispose();
  }

  Future<_OpenResult> _load() async {
    final requestId = widget.scanRequestId.trim();
    if (requestId.isEmpty) {
      return const _OpenResult.blocked(
        title: 'Scan request unavailable',
        message: 'The notification did not include a valid scan request.',
      );
    }

    final item = await RequestService.instance.fetchRequestById(requestId);
    if (item == null || item.id.trim().isEmpty) {
      return const _OpenResult.blocked(
        title: 'Scan request not found',
        message:
            'This request is no longer available, or your account does not have access to it.',
      );
    }

    final status = item.displayStatus.trim().toLowerCase();
    final completedScan = item.scanId?.trim() ?? '';
    if (completedScan.isNotEmpty || status == 'completed') {
      return const _OpenResult.blocked(
        title: 'Scan request already completed',
        message: 'This scan request has already been completed.',
      );
    }

    const startableStatuses = {'pending', 'requested', 'assigned'};
    if (status.isNotEmpty && !startableStatuses.contains(status)) {
      return _OpenResult.blocked(
        title: 'Scan request is not startable',
        message: 'This request has status "$status" and cannot be started.',
      );
    }

    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    if (workspace != null) {
      final activeProfileId = workspace.businessProfileId.trim();
      final requestProfileId = item.businessProfileId?.trim() ?? '';
      if (requestProfileId.isNotEmpty &&
          activeProfileId.isNotEmpty &&
          requestProfileId != activeProfileId) {
        return const _OpenResult.blocked(
          title: 'Scan request unavailable',
          message:
              'This request does not belong to your current workspace. Switch workspace or ask your administrator.',
        );
      }
      final assignedToCurrentUser = item.isAssignedToCurrentUser(
        currentUserId: Session.instance.userId,
        currentMembershipId: workspace.membershipId,
      );
      if (!assignedToCurrentUser) {
        return const _OpenResult.blocked(
          title: 'Scan request unavailable',
          message: 'This request is assigned to a different workspace member.',
        );
      }
    }

    return _OpenResult.open(item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WellarTheme.bg,
      body: AnimatedWellarScreen(
        child: FutureBuilder<_OpenResult>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _LoadingState();
            }
            if (snapshot.hasError) {
              return _BlockedState(
                title: 'Unable to open scan request',
                message:
                    'The request could not be loaded right now. Please try from Assigned Requests.',
                onRetry: _retry,
                onOpenRequests: _openRequests,
              );
            }

            final result = snapshot.data;
            final item = result?.item;
            if (item != null) {
              _openDetails(item);
              return const _LoadingState();
            }

            return _BlockedState(
              title: result?.title ?? 'Scan request unavailable',
              message:
                  result?.message ??
                  'This request cannot be opened from the notification.',
              onRetry: _retry,
              onOpenRequests: _openRequests,
            );
          },
        ),
      ),
    );
  }

  void _openDetails(RequestItem item) {
    if (_openedDetails) return;
    _openedDetails = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        fadeSlideRoute(
          ScanRequestDetailsScreen(item: item, canStartScan: true),
        ),
      );
    });
  }

  void _retry() {
    setState(() {
      _openedDetails = false;
      _future = _load();
    });
  }

  void _openRequests() {
    Navigator.pushReplacement(
      context,
      fadeSlideRoute(const EmployeeRequestsScreen()),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: WellarTheme.primary),
    );
  }
}

class _BlockedState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onOpenRequests;

  const _BlockedState({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onOpenRequests,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back, color: WellarTheme.text),
            ),
            const Expanded(
              child: Text(
                'Scan Request',
                style: TextStyle(
                  color: WellarTheme.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        WellarCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.assignment_late_outlined,
                color: WellarTheme.warning,
                size: 34,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: WellarTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                  color: WellarTheme.textMuted,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              WellarButton.primary(
                text: 'Assigned Requests',
                onPressed: onOpenRequests,
              ),
              const SizedBox(height: 10),
              WellarButton.secondary(text: 'Retry', onPressed: onRetry),
            ],
          ),
        ),
      ],
    );
  }
}

class _OpenResult {
  final RequestItem? item;
  final String? title;
  final String? message;

  const _OpenResult.open(this.item) : title = null, message = null;

  const _OpenResult.blocked({required this.title, required this.message})
    : item = null;
}
