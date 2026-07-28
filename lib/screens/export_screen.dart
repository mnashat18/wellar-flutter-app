import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/scan_result.dart';
import '../services/report_service.dart';
import '../services/scan_service.dart';
import '../state/app_providers.dart';
import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import '../widgets/lux_header.dart';
import '../widgets/state_views.dart';
import 'pricing_screen.dart';
import 'subscription_paywall_screen.dart';

enum _ExportTemplate { executive, compliance, full }

enum _TimeRange { week, month, quarter, all }

enum _StateFilter { all, stable, low, elevated, high }

extension _TemplateMeta on _ExportTemplate {
  String get label {
    switch (this) {
      case _ExportTemplate.executive:
        return 'Executive';
      case _ExportTemplate.compliance:
        return 'Compliance';
      case _ExportTemplate.full:
        return 'Full Data';
    }
  }
}

extension _TimeRangeMeta on _TimeRange {
  String get label {
    switch (this) {
      case _TimeRange.week:
        return '7D';
      case _TimeRange.month:
        return '30D';
      case _TimeRange.quarter:
        return '90D';
      case _TimeRange.all:
        return 'All';
    }
  }

  int? get days {
    switch (this) {
      case _TimeRange.week:
        return 7;
      case _TimeRange.month:
        return 30;
      case _TimeRange.quarter:
        return 90;
      case _TimeRange.all:
        return null;
    }
  }
}

extension _StateFilterMeta on _StateFilter {
  String get label {
    switch (this) {
      case _StateFilter.all:
        return 'All';
      case _StateFilter.stable:
        return 'Stable';
      case _StateFilter.low:
        return 'Attention Needed';
      case _StateFilter.elevated:
        return 'Readiness Concern';
      case _StateFilter.high:
        return 'Action Required';
    }
  }
}

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  bool _showPreview = true;
  bool _requesting = false;
  String _format = 'csv';
  _ExportTemplate _template = _ExportTemplate.executive;
  _TimeRange _timeRange = _TimeRange.month;
  _StateFilter _stateFilter = _StateFilter.all;

  @override
  Widget build(BuildContext context) {
    final subscriptionAsync = ref.watch(activeSubscriptionProvider);
    final access = subscriptionAsync.maybeWhen(
      data: (sub) =>
          ref.read(subscriptionServiceProvider).accessForSubscription(sub),
      orElse: () =>
          ref.read(subscriptionServiceProvider).accessForSubscription(null),
    );

    if (subscriptionAsync.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primarySoft),
        ),
      );
    }

    if (access.isExpired) {
      return const SubscriptionPaywallScreen(title: 'Exports locked');
    }

    if (!access.canExportReports) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            const AnimatedSpaceBackground(),
            SafeArea(
              child: Center(
                child: _UpgradeGate(
                  title: 'Exports locked',
                  message: 'Upgrade to Business to export reports.',
                  onUpgrade: () {
                    Navigator.push(
                      context,
                      fadeSlideRoute(const PricingScreen()),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );
    }

    final historyAsync = ref.watch(historyProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: historyAsync.when(
              loading: () => const SkeletonList(),
              error: (error, _) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [
                  const SizedBox(height: 80),
                  StatusCard(
                    title: 'Failed to load history',
                    message: error.toString(),
                    icon: Icons.warning_amber_rounded,
                    iconColor: AppColors.highRisk,
                    actionText: 'Retry',
                    onAction: () {},
                  ),
                ],
              ),
              data: (history) => RefreshIndicator(
                color: AppColors.primarySoft,
                onRefresh: () async {},
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  child: FadeSlideIn(child: _buildContent(context, history)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<ScanResult> history) {
    final filtered = _applyFilters(history);
    final csv = _buildCsv(filtered);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Fleet Reporting Summary',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Total shift checks: ${filtered.length}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Template: ${_template.label} • Range: ${_timeRange.label} • State: ${_stateFilter.label}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildTemplateCard(),
        const SizedBox(height: 16),
        _buildFilterCard(),
        const SizedBox(height: 16),
        PrimaryButton(
          text: _requesting ? 'Requesting...' : 'Request Export',
          icon: Icons.cloud_upload_outlined,
          isLoading: _requesting,
          onPressed: _requesting ? null : () => _requestExport(filtered),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                text: 'Copy CSV Report',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: csv));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('CSV copied to clipboard'),
                      backgroundColor: AppColors.stable,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SecondaryButton(
                text: _showPreview ? 'Hide Preview' : 'Show Preview',
                onPressed: () => setState(() => _showPreview = !_showPreview),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildFormatCard(),
        const SizedBox(height: 16),
        if (_showPreview)
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CSV Preview',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _previewLines(csv, 8),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return LuxHeader(
      title: 'Export and Reporting',
      subtitle: 'Generate fleet compliance and readiness reports',
      icon: Icons.cloud_download_outlined,
      onBack: () => Navigator.pop(context),
    );
  }

  Widget _buildFormatCard() {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Export Format',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: [
              _FormatChip(
                label: 'CSV',
                selected: _format == 'csv',
                onTap: () => setState(() => _format = 'csv'),
              ),
              _FormatChip(
                label: 'PDF',
                selected: _format == 'pdf',
                onTap: () => setState(() => _format = 'pdf'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _format == 'pdf'
                ? 'PDF export is generated instantly for download.'
                : 'CSV export is ready instantly and can be copied now.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateCard() {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Export Template',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _ExportTemplate.values.map((template) {
              final selected = template == _template;
              return _FormatChip(
                label: template.label,
                selected: selected,
                onTap: () => setState(() => _template = template),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            _template == _ExportTemplate.executive
                ? 'Executive fleet view with depot KPIs, summaries, and highlights.'
                : _template == _ExportTemplate.compliance
                ? 'Depot compliance report with readiness risk ratios.'
                : 'Full data export with every shift-check row.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterCard() {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filters',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _TimeRange.values
                .map(
                  (range) => _FormatChip(
                    label: range.label,
                    selected: range == _timeRange,
                    onTap: () => setState(() => _timeRange = range),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _StateFilter.values
                .map(
                  (filter) => _FormatChip(
                    label: filter.label,
                    selected: filter == _stateFilter,
                    onTap: () => setState(() => _stateFilter = filter),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _requestExport(List<ScanResult> history) async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final reportService = ref.read(reportServiceProvider);
      final exportId = await reportService.createExport(
        format: _format,
        filters: {
          'template': _template.label,
          'range': _timeRange.label,
          'state': _stateFilter.label,
        },
      );
      if (_format == 'csv') {
        final csv = _buildCsv(history);
        final bytes = utf8.encode(csv);
        final fileId = await reportService.uploadFileBytes(
          bytes: bytes,
          filename:
              'waller_export_${DateTime.now().millisecondsSinceEpoch}.csv',
        );
        await reportService.finalizeExport(
          exportId: exportId,
          status: 'ready',
          fileId: fileId,
        );
        await _openFile(fileId);
      } else {
        final bytes = await _buildPdfBytes(history, template: _template);
        final fileId = await reportService.uploadFileBytes(
          bytes: bytes,
          filename:
              'waller_export_${DateTime.now().millisecondsSinceEpoch}.pdf',
        );
        await reportService.finalizeExport(
          exportId: exportId,
          status: 'ready',
          fileId: fileId,
        );
        await _openFile(fileId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _format == 'csv'
                ? 'CSV export ready, download started'
                : 'PDF export ready, download started',
          ),
          backgroundColor: AppColors.stable,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to request export: $e'),
          backgroundColor: AppColors.highRisk,
        ),
      );
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  List<ScanResult> _applyFilters(List<ScanResult> history) {
    var results = List<ScanResult>.from(history);
    final days = _timeRange.days;
    if (days != null) {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      results = results
          .where((r) => r.dateCreated != null && r.dateCreated!.isAfter(cutoff))
          .toList();
    }
    if (_stateFilter != _StateFilter.all) {
      final key = _stateFilter.label.toLowerCase().split(' ').first;
      results = results.where((r) {
        final state = r.overallState.toLowerCase();
        return state.contains(key);
      }).toList();
    }
    return results;
  }

  Future<void> _openFile(String fileId) async {
    try {
      await ref.read(reportServiceProvider).openPrivateFile(fileId);
    } on UnauthenticatedException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.highRisk,
        ),
      );
    } on ReportFileOpenException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.highRisk,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open export file'),
          backgroundColor: AppColors.highRisk,
        ),
      );
    }
  }

  Future<Uint8List> _buildPdfBytes(
    List<ScanResult> history, {
    required _ExportTemplate template,
  }) async {
    final doc = pw.Document();
    final generatedAt = _formatDate(DateTime.now(), includeTime: true);
    final summary = _buildSummaryMetrics(history);

    doc.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(margin: pw.EdgeInsets.all(24)),
        build: (context) => [
          pw.Text(
            'Waller Export',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Generated: $generatedAt',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Template: ${template.label}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Text(
            'Total shift checks: ${history.length}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Depot Compliance: ${summary.compliance}%  •  Assignment Risk Index: ${summary.riskIndex}%',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 10),
          if (template == _ExportTemplate.executive) ...[
            pw.Text(
              'Executive Summary',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Stable: ${summary.stable}  •  Attention Needed: ${summary.lowFocus}  •  Readiness Concern: ${summary.elevated}  •  Action Required: ${summary.highRisk}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Recent Dispatch Highlights',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
            pw.SizedBox(height: 6),
            _buildPdfTable(history.take(12).toList()),
          ] else if (template == _ExportTemplate.compliance) ...[
            pw.Text(
              'Depot Compliance Detail',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Compliance rate is calculated from stable pre-shift checks over total checks.',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
            _buildPdfTable(
              history
                  .where((r) {
                    final state = r.overallState.toLowerCase();
                    return state.contains('high') || state.contains('elevated');
                  })
                  .take(12)
                  .toList(),
            ),
          ] else ...[
            _buildPdfTable(history),
          ],
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _buildPdfTable(List<ScanResult> history) {
    if (history.isEmpty) {
      return pw.Text(
        'No shift-check data available.',
        style: const pw.TextStyle(fontSize: 9),
      );
    }
    return pw.Table.fromTextArray(
      headers: const [
        'Date',
        'Scan ID',
        'State',
        'Confidence',
        'Camera',
        'Voice',
        'Task',
        'Drift',
      ],
      data: history
          .map(
            (r) => [
              _formatDate(r.dateCreated, includeTime: true),
              r.scanId,
              r.overallState,
              _formatNumber(r.confidence),
              _formatNumber(r.cameraConfidence),
              _formatNumber(r.voiceConfidence),
              _formatNumber(r.taskPerformanceScore),
              _formatNumber(r.confidenceDrift),
            ],
          )
          .toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignment: pw.Alignment.centerLeft,
      columnWidths: const {
        0: pw.FlexColumnWidth(1.3),
        1: pw.FlexColumnWidth(1.5),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1),
        4: pw.FlexColumnWidth(1),
        5: pw.FlexColumnWidth(1),
        6: pw.FlexColumnWidth(1),
        7: pw.FlexColumnWidth(1),
      },
    );
  }

  _SummaryMetrics _buildSummaryMetrics(List<ScanResult> history) {
    final total = history.length;
    var stable = 0;
    var lowFocus = 0;
    var elevated = 0;
    var highRisk = 0;
    for (final r in history) {
      final state = r.overallState.toLowerCase();
      if (state.contains('stable')) {
        stable++;
      } else if (state.contains('low')) {
        lowFocus++;
      } else if (state.contains('elevated')) {
        elevated++;
      } else if (state.contains('high')) {
        highRisk++;
      }
    }
    final compliance = total == 0 ? 0 : ((stable / total) * 100).round();
    final riskIndex = total == 0 ? 0 : ((highRisk / total) * 100).round();
    return _SummaryMetrics(
      total: total,
      stable: stable,
      lowFocus: lowFocus,
      elevated: elevated,
      highRisk: highRisk,
      compliance: compliance,
      riskIndex: riskIndex,
    );
  }

  String _buildCsv(List<ScanResult> history) {
    if (_template == _ExportTemplate.full) {
      final buffer = StringBuffer();
      buffer.writeln(
        'date_created,scan_id,overall_state,confidence,camera_confidence,voice_confidence,task_performance,confidence_drift',
      );
      for (final r in history) {
        buffer.writeln(
          [
            _formatDate(r.dateCreated, includeTime: true),
            _escapeCsv(r.scanId),
            _escapeCsv(r.overallState),
            _formatNumber(r.confidence),
            _formatNumber(r.cameraConfidence),
            _formatNumber(r.voiceConfidence),
            _formatNumber(r.taskPerformanceScore),
            _formatNumber(r.confidenceDrift),
          ].join(','),
        );
      }
      return buffer.toString();
    }

    final summary = _buildSummaryMetrics(history);
    final buffer = StringBuffer();
    buffer.writeln('metric,value');
    buffer.writeln('template,${_escapeCsv(_template.label)}');
    buffer.writeln('total_scans,${summary.total}');
    buffer.writeln('compliance_percent,${summary.compliance}');
    buffer.writeln('risk_index_percent,${summary.riskIndex}');
    buffer.writeln('stable,${summary.stable}');
    buffer.writeln('low_focus,${summary.lowFocus}');
    buffer.writeln('elevated_fatigue,${summary.elevated}');
    buffer.writeln('high_risk,${summary.highRisk}');
    buffer.writeln('');
    buffer.writeln('recent_scans');
    buffer.writeln('date_created,scan_id,overall_state,confidence');
    for (final r in history.take(12)) {
      buffer.writeln(
        [
          _formatDate(r.dateCreated, includeTime: true),
          _escapeCsv(r.scanId),
          _escapeCsv(r.overallState),
          _formatNumber(r.confidence),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  String _formatNumber(double? value) {
    if (value == null) return '';
    return value.toStringAsFixed(3);
  }

  String _escapeCsv(String? value) {
    if (value == null) return '';
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _previewLines(String csv, int lines) {
    final parts = csv.trim().split('\n');
    if (parts.length <= lines) return csv.trim();
    return parts.take(lines).join('\n');
  }

  String _formatDate(DateTime? date, {bool includeTime = false}) {
    if (date == null) return '-';
    final d = date.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    if (!includeTime) return '$dd/$mm/$yyyy';
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
  }
}

class _SummaryMetrics {
  final int total;
  final int stable;
  final int lowFocus;
  final int elevated;
  final int highRisk;
  final int compliance;
  final int riskIndex;

  const _SummaryMetrics({
    required this.total,
    required this.stable,
    required this.lowFocus,
    required this.elevated,
    required this.highRisk,
    required this.compliance,
    required this.riskIndex,
  });
}

class _UpgradeGate extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onUpgrade;

  const _UpgradeGate({
    required this.title,
    required this.message,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline,
              color: AppColors.primarySoft,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              text: 'View Plans',
              icon: Icons.upgrade_rounded,
              onPressed: onUpgrade,
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FormatChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primarySoft : Colors.white24;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft.withOpacity(0.2) : null,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
