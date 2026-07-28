import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/push_notification_service.dart';
import '../utils/app_colors.dart';

class PushDiagnosticsScreen extends StatefulWidget {
  const PushDiagnosticsScreen({super.key});

  @override
  State<PushDiagnosticsScreen> createState() => _PushDiagnosticsScreenState();
}

class _PushDiagnosticsScreenState extends State<PushDiagnosticsScreen> {
  bool _busy = false;

  Future<void> _refreshRegistration() async {
    setState(() => _busy = true);
    try {
      await PushNotificationService.instance.registerCurrentDevice(
        trigger: 'debug_refresh',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'Never';
    final local = value.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final service = PushNotificationService.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF050A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050A12),
        foregroundColor: Colors.white,
        title: const Text(
          'Push diagnostics',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            const Text(
              'Debug-only runtime state',
              style: TextStyle(
                color: AppColors.primarySoft,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.24,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'This screen shows push registration state without exposing the raw FCM token.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.08,
                letterSpacing: -0.35,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use Refresh push registration after sign-in or workspace changes when you need to verify backend sync status.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            _InfoCard(
              children: [
                _InfoRow(
                  label: 'Firebase initialized',
                  value: service.firebaseInitialized ? 'Yes' : 'No',
                ),
                _InfoRow(
                  label: 'Current permission status',
                  value: service.permissionStatusLabel,
                ),
                _InfoRow(
                  label: 'Current token status',
                  value: service.currentTokenStatus,
                ),
                _InfoRow(
                  label: 'Last successful backend sync',
                  value:
                      '${service.lastSuccessfulSyncStatus} · ${_formatDateTime(service.lastSuccessfulSyncAt)}',
                ),
                _InfoRow(
                  label: 'App lifecycle sync status',
                  value: service.lastLifecycleSyncStatus,
                ),
                _InfoRow(
                  label: 'Foreground handler registered',
                  value: service.foregroundHandlerRegistered ? 'Yes' : 'No',
                ),
                _InfoRow(
                  label: 'Background handler registered',
                  value: service.backgroundHandlerRegistered ? 'Yes' : 'No',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ActionButton(
              text: _busy ? 'Refreshing...' : 'Refresh push registration',
              onPressed: _busy ? null : _refreshRegistration,
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 14),
              const Text(
                'Reach this page from the Profile tab, then tap Push diagnostics in the developer section. Token values are never shown here.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1522),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF223145)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: Color(0xFF223145)),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 166,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.66),
              fontSize: 12.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool primary;

  const _ActionButton({required this.text, required this.onPressed})
    : primary = true;

  const _ActionButton.secondary({required this.text, required this.onPressed})
    : primary = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = primary
        ? AppColors.primarySoft
        : const Color(0xFF0A111D);
    final foregroundColor = primary ? const Color(0xFF08111F) : Colors.white;
    final borderColor = primary ? Colors.transparent : const Color(0xFF314056);

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14.5,
            color: foregroundColor,
          ),
        ),
      ),
    );
  }
}
