import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../state/app_providers.dart';

class ConnectivityStatusBanner extends ConsumerWidget {
  const ConnectivityStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(connectivityStatusProvider);
    if (!connection.hasValue || connection.value != false) {
      return const SizedBox.shrink();
    }

    final language = ref.watch(appLanguageControllerProvider).language;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: SizedBox(
        height: 32,
        width: double.infinity,
        child: Center(
          child: Text(
            Tr.t(language, 'no_internet_connection'),
            style: TextStyle(
              color: colors.onErrorContainer,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
