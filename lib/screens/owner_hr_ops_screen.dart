import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hr_compliance_screen.dart';
import 'hr_workforce_screen.dart';
import 'owner_company_screen.dart';
import 'owner_workforce_screen.dart';
import '../widgets/animated_wellar_screen.dart';

enum OwnerHrOpsTab { compliance, workforce }

class OwnerHrOpsScreen extends ConsumerStatefulWidget {
  final String role;
  final OwnerHrOpsTab initialTab;

  const OwnerHrOpsScreen({
    super.key,
    required this.role,
    this.initialTab = OwnerHrOpsTab.compliance,
  });

  @override
  ConsumerState<OwnerHrOpsScreen> createState() => _OwnerHrOpsScreenState();
}

class _OwnerHrOpsScreenState extends ConsumerState<OwnerHrOpsScreen> {
  bool get _isHr => widget.role.trim().toLowerCase() == 'hr';

  @override
  Widget build(BuildContext context) {
    final page = _isHr
        ? (widget.initialTab == OwnerHrOpsTab.compliance
              ? const HrComplianceScreen()
              : const HrWorkforceScreen())
        : (widget.initialTab == OwnerHrOpsTab.compliance
              ? const OwnerCompanyScreen()
              : const OwnerWorkforceScreen());
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        padding: EdgeInsets.zero,
        child: page,
      ),
    );
  }
}
