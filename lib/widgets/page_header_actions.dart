import 'package:flutter/material.dart';

import '../screens/notifications_screen.dart';
import '../screens/profile_screen.dart';
import '../theme/app_theme.dart';
import '../utils/page_transition.dart';
import 'notification_bell_button.dart';

class PageHeaderActions extends StatelessWidget {
  final int unreadCount;
  final bool showAlertsTab;

  const PageHeaderActions({
    super.key,
    required this.unreadCount,
    required this.showAlertsTab,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NotificationBellButton(
          unreadCount: unreadCount,
          onTap: () => Navigator.push(
            context,
            fadeSlideRoute(NotificationsScreen(showAlertsTab: showAlertsTab)),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Account',
          onPressed: () =>
              Navigator.push(context, fadeSlideRoute(const ProfileScreen())),
          icon: const Icon(
            Icons.account_circle_outlined,
            color: WellarTheme.text,
          ),
        ),
      ],
    );
  }
}
