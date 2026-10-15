import 'package:flutter/material.dart';

class AppFeedback {
  AppFeedback._();

  static void showOffline(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    showError(
      context,
      isArabic
          ? 'لا يوجد اتصال بالإنترنت. يُرجى التحقق من اتصالك والمحاولة مرة أخرى.'
          : 'No internet connection. Connect to the internet to continue.',
    );
  }

  static void showError(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    showErrorOnMessenger(messenger, Theme.of(context).colorScheme, message);
  }

  static void showErrorOnMessenger(
    ScaffoldMessengerState messenger,
    ColorScheme colors,
    String message,
  ) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: colors.onErrorContainer),
        ),
        backgroundColor: colors.errorContainer,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
