import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class NotificationBellButton extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;

  const NotificationBellButton({
    super.key,
    required this.unreadCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final clampedCount = unreadCount.clamp(0, 99);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xAA13233C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WellarTheme.border),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Center(
              child: Icon(
                Icons.notifications_none_rounded,
                color: WellarTheme.text,
                size: 20,
              ),
            ),
            if (clampedCount > 0)
              Positioned(
                top: 1,
                right: 1,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9B54A),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFFBE1A7)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    clampedCount == 99 ? '99+' : '$clampedCount',
                    style: const TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
