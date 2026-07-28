import 'dart:async';

import 'package:flutter/material.dart';

import '../services/organization_service.dart';
import '../state/session.dart';
import '../utils/app_colors.dart';
import '../utils/page_transition.dart';

class AuthWelcomeScreen extends StatefulWidget {
  final ActiveWorkspaceContext? workspace;
  final String headline;
  final String body;
  final String primaryLabel;
  final Widget nextScreen;
  final bool autoContinue;
  final Duration autoContinueDelay;

  const AuthWelcomeScreen({
    super.key,
    required this.headline,
    required this.body,
    required this.primaryLabel,
    required this.nextScreen,
    this.workspace,
    this.autoContinue = true,
    this.autoContinueDelay = const Duration(milliseconds: 900),
  });

  @override
  State<AuthWelcomeScreen> createState() => _AuthWelcomeScreenState();
}

class _AuthWelcomeScreenState extends State<AuthWelcomeScreen> {
  Timer? _timer;
  bool _continued = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoContinue) {
      _timer = Timer(widget.autoContinueDelay, _continue);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _continue() {
    if (_continued) return;
    _continued = true;
    _timer?.cancel();
    Navigator.pushReplacement(context, fadeSlideRoute(widget.nextScreen));
  }

  @override
  Widget build(BuildContext context) {
    final workspace = widget.workspace;
    final email = (Session.instance.userEmail ?? '').trim();
    final userName = (Session.instance.userName ?? '').trim();

    return Scaffold(
      backgroundColor: const Color(0xFF050A12),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1320),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF243247)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF101A2A),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF273247)),
                      ),
                      child: const Text(
                        'W',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.headline,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.06,
                        letterSpacing: -0.45,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.body,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13.8,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _FactRow(
                      label: 'Account',
                      value: userName.isNotEmpty
                          ? userName
                          : (email.isNotEmpty ? email : 'Signed in'),
                    ),
                    if (workspace != null) ...[
                      const SizedBox(height: 10),
                      _FactRow(
                        label: 'Organization',
                        value: workspace.businessProfileName,
                      ),
                      const SizedBox(height: 10),
                      _FactRow(
                        label: 'Role',
                        value: _roleLabel(workspace.finalEffectiveRole),
                      ),
                      if ((workspace.departmentName ?? '')
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _FactRow(
                          label: 'Department',
                          value: workspace.departmentName!.trim(),
                        ),
                      ],
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _continue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF0BD5F),
                          foregroundColor: const Color(0xFF08111F),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          widget.primaryLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (widget.autoContinue)
                      Text(
                        'Opening automatically in a moment...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    final normalized = role.trim().toLowerCase();
    if (normalized == 'owner') return 'Owner';
    if (normalized == 'hr') return 'HR';
    if (normalized == 'manager' || normalized == 'manger') return 'Manager';
    if (normalized == 'employee') return 'Employee';
    return 'User';
  }
}

class _FactRow extends StatelessWidget {
  final String label;
  final String value;

  const _FactRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A111D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF233145)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 12,
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
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
