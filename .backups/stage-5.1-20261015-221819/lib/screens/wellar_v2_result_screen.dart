import 'package:flutter/material.dart';

import '../models/wellar_v2_result.dart';

class WellarV2ResultScreen extends StatelessWidget {
  const WellarV2ResultScreen({super.key, required this.result});

  final WellarV2Result result;

  @override
  Widget build(BuildContext context) {
    final insufficient = result.status == 'insufficient_evidence';
    return Scaffold(
      appBar: AppBar(title: const Text('V2 research result')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              insufficient ? Icons.info_outline : Icons.error_outline,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              insufficient ? 'Insufficient evidence' : result.status,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(result.message),
            const SizedBox(height: 20),
            const Text(
              'Wellar AI V2 does not provide a validated fatigue or vigilance prediction. No readiness score or risk category is available.',
            ),
            const SizedBox(height: 20),
            for (final entry in result.targets.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.key.replaceAll('_', ' ')),
                subtitle: Text(
                  entry.value.value == null
                      ? 'Unavailable${entry.value.reason == null ? '' : ' · ${entry.value.reason}'}'
                      : entry.value.value.toString(),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'V2 scan reference: ${result.scanId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
