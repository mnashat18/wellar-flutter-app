import 'package:flutter/material.dart';
import '../../models/audit_log.dart';
import '../../services/audit_log_service.dart';
import '../../state/session.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_cards.dart';

class AuditLogsView extends StatelessWidget {
  const AuditLogsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const _AuditLogsView();
  }
}

class _AuditLogsView extends StatefulWidget {
  const _AuditLogsView();

  @override
  State<_AuditLogsView> createState() => _AuditLogsViewState();
}

class _AuditLogsViewState extends State<_AuditLogsView> {
  final _typeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _metadataController = TextEditingController();
  final _emailController = TextEditingController();

  Future<List<AuditLog>>? _logsFuture;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController.text = Session.instance.userEmail ?? '';
    _logsFuture = AuditLogService.instance.fetchLogs();
  }

  @override
  void dispose() {
    _typeController.dispose();
    _descriptionController.dispose();
    _metadataController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_typeController.text.trim().isEmpty ||
        _descriptionController.text.trim().isEmpty) {
      setState(() => _error = 'Please fill type and description.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await AuditLogService.instance.createLog(
        type: _typeController.text.trim(),
        description: _descriptionController.text.trim(),
        metadataJson: _metadataController.text.trim().isEmpty
            ? null
            : _metadataController.text.trim(),
      );
      _typeController.clear();
      _descriptionController.clear();
      _metadataController.clear();
      await _refreshLogs();
      _showSuccessSnack();
    } on FormatException {
      setState(() {
        _error = 'Metadata must be valid JSON.';
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to submit log.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _refreshLogs() async {
    final next = AuditLogService.instance.fetchLogs();
    if (mounted) {
      setState(() {
        _logsFuture = next;
      });
    }
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          color: AppColors.primarySoft,
          onRefresh: _refreshLogs,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Audit Logs',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Report pre-shift safety issues and compliance observations',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 640;
                    final form = _AuditFormCard(
                      emailController: _emailController,
                      typeController: _typeController,
                      descriptionController: _descriptionController,
                      metadataController: _metadataController,
                      error: _error,
                      submitting: _submitting,
                      onSubmit: _submit,
                    );
                    final meta = _AuditMetaCard(
                      logsFuture: _logsFuture,
                      onRefresh: () {
                        _refreshLogs();
                      },
                    );
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: form),
                          const SizedBox(width: 16),
                          Expanded(child: meta),
                        ],
                      );
                    }
                    return Column(
                      children: [form, const SizedBox(height: 16), meta],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showSuccessSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Audit log submitted'),
        backgroundColor: AppColors.stable,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _AuditFormCard extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController typeController;
  final TextEditingController descriptionController;
  final TextEditingController metadataController;
  final String? error;
  final bool submitting;
  final VoidCallback onSubmit;

  const _AuditFormCard({
    required this.emailController,
    required this.typeController,
    required this.descriptionController,
    required this.metadataController,
    required this.error,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create Audit Log',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Attach as much context as possible.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          _AuditField(
            label: 'Email',
            hint: 'nash@example.com',
            helper:
                'Your email is locked to protect privacy. Logs are visible only to admins.',
            enabled: false,
            controller: emailController,
          ),
          const SizedBox(height: 12),
          _AuditField(
            label: 'Type',
            hint: 'Fatigue / Focus / Risk / Other',
            controller: typeController,
          ),
          const SizedBox(height: 12),
          _AuditField(
            label: 'Description',
            hint: 'Describe the issue clearly...',
            maxLines: 4,
            controller: descriptionController,
          ),
          const SizedBox(height: 12),
          _AuditField(
            label: 'Metadata (JSON)',
            hint: '{ "sleep_hours": 4, "stress": "high" }',
            maxLines: 3,
            monospace: true,
            controller: metadataController,
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: const TextStyle(
                color: AppColors.highRisk,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          PrimaryButton(
            text: 'Submit Log',
            icon: Icons.send,
            isLoading: submitting,
            onPressed: submitting ? null : onSubmit,
          ),
        ],
      ),
    );
  }
}

class _AuditMetaCard extends StatelessWidget {
  final Future<List<AuditLog>>? logsFuture;
  final VoidCallback onRefresh;

  const _AuditMetaCard({
    required this.logsFuture,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'My Logs',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white70),
                onPressed: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Synced from backend audit logs collection.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<AuditLog>>(
            future: logsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }
              if (snapshot.hasError) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    snapshot.error.toString(),
                    style: const TextStyle(
                      color: AppColors.highRisk,
                      fontSize: 12,
                    ),
                  ),
                );
              }
              final logs = snapshot.data ?? [];
              if (logs.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Text(
                    'No logs yet.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                );
              }
              return Column(
                children: logs
                    .map(
                      (log) => _AuditLogRow(
                        log: log,
                        onTap: () => _showLogDetails(context, log),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showLogDetails(BuildContext context, AuditLog log) {
    showDialog<bool>(
      context: context,
      builder: (_) => _AuditLogDetailsDialog(log: log, isAdmin: false),
    ).then((updated) {
      if (updated == true) {
        onRefresh();
      }
    });
  }
}

class _AuditField extends StatelessWidget {
  final String label;
  final String hint;
  final String? helper;
  final int maxLines;
  final bool enabled;
  final bool monospace;
  final TextEditingController? controller;

  const _AuditField({
    required this.label,
    required this.hint,
    this.helper,
    this.maxLines = 1,
    this.enabled = true,
    this.monospace = false,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          maxLines: maxLines,
          style: TextStyle(
            color: Colors.white,
            fontFamily: monospace ? 'monospace' : null,
            fontSize: 13,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.backgroundAlt,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.white10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primarySoft),
            ),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 6),
          Text(
            helper!,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

class AuditField extends StatelessWidget {
  final String label;
  final String hint;
  final String? helper;
  final int maxLines;
  final bool enabled;
  final bool monospace;
  final TextEditingController? controller;

  const AuditField({
    super.key,
    required this.label,
    required this.hint,
    this.helper,
    this.maxLines = 1,
    this.enabled = true,
    this.monospace = false,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return _AuditField(
      label: label,
      hint: hint,
      helper: helper,
      maxLines: maxLines,
      enabled: enabled,
      monospace: monospace,
      controller: controller,
    );
  }
}

class _AuditLogRow extends StatelessWidget {
  final AuditLog log;
  final VoidCallback onTap;

  const _AuditLogRow({
    required this.log,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = _formatDate(log.timestamp);
    final hasReply =
        log.metadata?['admin_reply']?.toString().trim().isNotEmpty ?? false;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    log.type,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  date,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              log.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MiniChip(
                  text: hasReply ? 'Replied' : 'Pending',
                  color: hasReply ? AppColors.stable : AppColors.elevated,
                ),
                const Spacer(),
                const Icon(
                  Icons.visibility,
                  size: 14,
                  color: AppColors.primarySoft,
                ),
                const SizedBox(width: 6),
                const Text(
                  'View details',
                  style: TextStyle(
                    color: AppColors.primarySoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final d = date.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
  }
}

class _MiniChip extends StatelessWidget {
  final String text;
  final Color color;

  const _MiniChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class MiniChip extends StatelessWidget {
  final String text;
  final Color color;

  const MiniChip({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return _MiniChip(text: text, color: color);
  }
}

class _AuditLogDetailsDialog extends StatefulWidget {
  final AuditLog log;
  final bool isAdmin;

  const _AuditLogDetailsDialog({required this.log, required this.isAdmin});

  @override
  State<_AuditLogDetailsDialog> createState() => _AuditLogDetailsDialogState();
}

class _AuditLogDetailsDialogState extends State<_AuditLogDetailsDialog> {
  final _replyController = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final reply = widget.log.metadata?['admin_reply']?.toString();
    if (reply != null) {
      _replyController.text = reply;
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.log.userEmail ?? Session.instance.userEmail ?? '-';
    return Dialog(
      backgroundColor: AppColors.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Audit Log Details',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Email: $email',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                'Type: ${widget.log.type}',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                'Date: ${_formatDate(widget.log.timestamp)}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              const Text(
                'Description',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.log.description,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              if (widget.isAdmin) ...[
                const Text(
                  'Admin Reply',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _replyController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Write a reply...',
                    hintStyle: const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.backgroundAlt,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.primarySoft,
                      ),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.highRisk,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                PrimaryButton(
                  text: 'Send Reply',
                  icon: Icons.send,
                  isLoading: _sending,
                  onPressed: _sending ? null : _sendReply,
                ),
              ] else ...[
                const Text(
                  'Admin Reply',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.log.metadata?['admin_reply']?.toString() ??
                      'No reply yet.',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendReply() async {
    if (_replyController.text.trim().isEmpty) {
      setState(() => _error = 'Reply cannot be empty.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await AuditLogService.instance.replyToLog(
        log: widget.log,
        reply: _replyController.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to send reply.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final d = date.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
  }
}
