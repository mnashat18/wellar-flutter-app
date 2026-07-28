import 'package:flutter/material.dart';

import '../models/alert_item.dart';
import '../models/scan_result.dart';
import '../services/scan_service.dart';
import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import '../utils/scan_result_display.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import '../widgets/state_views.dart';
import 'request_details_screen.dart';
import 'scan_details_screen.dart';

class AlertDetailScreen extends StatefulWidget {
  final AlertItem item;

  const AlertDetailScreen({super.key, required this.item});

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  late final Future<ScanResult?> _scanFuture;

  @override
  void initState() {
    super.initState();
    final scanId = widget.item.relatedScanId?.trim() ?? '';
    _scanFuture = scanId.isEmpty
        ? Future.value(null)
        : ScanService.instance.fetchScanResultForScan(scanId);
  }

  @override
  Widget build(BuildContext context) {
    final scanId = widget.item.relatedScanId?.trim() ?? '';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: FutureBuilder<ScanResult?>(
              future: _scanFuture,
              builder: (context, snap) {
                final result = snap.data;
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  children: [
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Alert detail',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.item.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      widget.item.summary,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  StatusChip(
                                    text: widget.item.status,
                                    color: AppColors.primarySoft,
                                  ),
                                  if ((widget.item.severity ?? '')
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    StatusChip(
                                      text: 'Severity ${widget.item.severity!}',
                                      color: AppColors.accentGold,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          if ((widget.item.actionType ?? '')
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Recommended action: ${widget.item.actionType}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Employee context',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _DetailRow(
                            label: 'Name',
                            value: widget.item.employeeName ?? '-',
                          ),
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: 'Email',
                            value: widget.item.employeeEmail ?? '-',
                          ),
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: 'Role',
                            value: widget.item.employeeRole ?? '-',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Scan outcome',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _DetailRow(
                            label: 'Scan status',
                            value: widget.item.scanState ??
                                'Processing assessment',
                          ),
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: 'Outcome',
                            value: result != null
                                ? displayRiskLevelLabel(
                                    result.riskLevel ?? result.overallState,
                                  )
                                : 'Processing assessment',
                          ),
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: 'Readiness score',
                            value: _scoreLabel(result?.readinessScore),
                          ),
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: 'Completed',
                            value: _formatDate(
                              result?.completedAt ??
                                  widget.item.scanCompletedAt ??
                                  widget.item.createdAt,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (result != null) ...[
                      const SizedBox(height: 14),
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Open result',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Open the linked readiness result for the full breakdown.',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SolidButton(
                              text: 'Open scan result',
                              color: AppColors.primarySoft,
                              onPressed: () {
                                Navigator.of(context).push(
                                  fadeSlideRoute(
                                    ScanDetailsScreen(scanId: scanId),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    if ((widget.item.relatedRequestId ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Related request',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Open the original scan request for assignment context.',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SolidButton(
                              text: 'Open request',
                              color: AppColors.primarySoft,
                              onPressed: () {
                                Navigator.of(context).push(
                                  fadeSlideRoute(
                                    RequestDetailsScreen(
                                      requestId: widget.item.relatedRequestId!,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: _FutureSection(
                        isLoading:
                            snap.connectionState == ConnectionState.waiting &&
                            scanId.isNotEmpty,
                        hasResult: result != null,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _scoreLabel(double? value) {
    if (value == null) return 'Processing assessment';
    final normalized = value <= 1 ? (value * 100).round() : value.round();
    return '$normalized%';
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Processing assessment';
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _FutureSection extends StatelessWidget {
  final bool isLoading;
  final bool hasResult;

  const _FutureSection({
    required this.isLoading,
    required this.hasResult,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Loading linked scan result...',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      );
    }
    return Text(
      hasResult
          ? 'Linked scan details are available above.'
          : 'This alert currently shows the facts available in the alert record.',
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        height: 1.4,
      ),
    );
  }
}
