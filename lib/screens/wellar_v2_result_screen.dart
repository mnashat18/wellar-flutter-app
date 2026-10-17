import 'package:flutter/material.dart';

import '../models/wellar_v2_result.dart';
import 'scan_details_screen.dart';

/// Routes V2 output through the established scan details layout and theme.
class WellarV2ResultScreen extends StatelessWidget {
  const WellarV2ResultScreen({super.key, required this.result});

  final WellarV2Result result;

  @override
  Widget build(BuildContext context) => ScanDetailsScreen(v2Result: result);
}
