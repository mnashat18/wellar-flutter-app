import 'package:flutter/material.dart';

import '../models/request_item.dart';

enum ScanRequestCardScope { personal, organization, team }

class ScanRequestActionCard extends StatefulWidget {
  final RequestItem item;
  final ScanRequestCardScope scope;
  final bool canStartScan;
  final Future<void> Function()? onStartScan;
  final VoidCallback onViewDetails;

  const ScanRequestActionCard({
    super.key,
    required this.item,
    required this.scope,
    required this.canStartScan,
    required this.onViewDetails,
    this.onStartScan,
  });

  @override
  State<ScanRequestActionCard> createState() => _ScanRequestActionCardState();
}

class _ScanRequestActionCardState extends State<ScanRequestActionCard>
    with SingleTickerProviderStateMixin {
  static const Color _gold = Color(0xFFF1C16B);
  static const Color _goldSoft = Color(0xFFB68A2A);
  static const Color _surface = Color(0xFF101722);
  static const Color _surfaceAlt = Color(0xFF182231);
  static const Color _border = Color(0xFF2A3647);

  late final AnimationController _controller;
  bool _startingScan = false;
  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (disableAnimations != _disableAnimations) {
      _disableAnimations = disableAnimations;
    }
    _syncAnimationState();
  }

  @override
  void didUpdateWidget(covariant ScanRequestActionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimationState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _shouldAnimate {
    return widget.scope == ScanRequestCardScope.personal &&
        widget.canStartScan &&
        widget.item.isActionableCanonical &&
        !widget.item.isCompletedCanonical &&
        !_disableAnimations;
  }

  void _syncAnimationState() {
    if (_shouldAnimate) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else if (_controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  bool get _isPersonalPending {
    return widget.scope == ScanRequestCardScope.personal &&
        widget.item.isActionableCanonical &&
        !widget.item.isCompletedCanonical;
  }

  String get _scopeLabel {
    return switch (widget.scope) {
      ScanRequestCardScope.personal => 'Assigned to you',
      ScanRequestCardScope.organization => 'Organization request',
      ScanRequestCardScope.team => 'Team request',
    };
  }

  String get _scopeDescription {
    return switch (widget.scope) {
      ScanRequestCardScope.personal => 'Directly assigned to your account.',
      ScanRequestCardScope.organization =>
        'Visible within the active workspace.',
      ScanRequestCardScope.team => 'Request for your team scope.',
    };
  }

  Future<void> _handleStartScan() async {
    if (_startingScan || widget.onStartScan == null) return;
    setState(() => _startingScan = true);
    try {
      await widget.onStartScan!();
    } finally {
      if (mounted) {
        setState(() => _startingScan = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final emphatic = _isPersonalPending;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _shouldAnimate
            ? Curves.easeInOut.transform(_controller.value)
            : 0.0;
        final borderColor = emphatic
            ? Color.lerp(_goldSoft, _gold, t)!
            : _border;
        final glowAlpha = emphatic
            ? (0.08 + (0.08 * (1 - (t - 0.5).abs() * 2)))
            : 0.0;
        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_surface, _surfaceAlt],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: emphatic ? borderColor : _border,
              width: emphatic ? 1.5 : 1,
            ),
            boxShadow: emphatic
                ? [
                    BoxShadow(
                      color: _gold.withValues(alpha: glowAlpha),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _scopeLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _badge(_scopeLabel, emphatic ? _gold : const Color(0xFF7EA6D8)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _scopeDescription,
              style: const TextStyle(color: Color(0xFFB5C1D1), fontSize: 12),
            ),
            const SizedBox(height: 10),
            _line('Status', _prettyStatus(widget.item.displayStatus)),
            const SizedBox(height: 4),
            _line('Recipient', widget.item.displayUser),
            if ((widget.item.requestedForEmail ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              _line('Email', widget.item.requestedForEmail!.trim()),
            ],
            const SizedBox(height: 4),
            _line(
              'Requested by',
              widget.item.requestedByUserName ?? 'Workspace admin',
            ),
            const SizedBox(height: 4),
            _line('Due at', _formatDateTime(widget.item.dueAt)),
            if (widget.item.completedAt != null) ...[
              const SizedBox(height: 4),
              _line('Completed at', _formatDateTime(widget.item.completedAt)),
            ],
            if (widget.canStartScan && widget.onStartScan != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _startingScan ? null : _handleStartScan,
                      style: FilledButton.styleFrom(
                        backgroundColor: _goldSoft,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: Text(_startingScan ? 'Starting...' : 'Start Scan'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _startingScan ? null : widget.onViewDetails,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: _gold),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('View Details'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: widget.onViewDetails,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: _border),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('View Details'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            '$label:',
            style: const TextStyle(color: Color(0xFF8D9AAF), fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _prettyStatus(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return 'Pending';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }
}
