import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';

/// 通知バッジウィジェット
/// 未読通知数を赤い丸バッジで表示する
class NotificationBadge extends StatelessWidget {
  final Widget child;

  const NotificationBadge({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final notificationService = NotificationService();
    final authService = AuthService();
    final userId = authService.currentUser?.uid ?? '';

    if (userId.isEmpty) {
      return child;
    }

    return StreamBuilder<int>(
      stream: notificationService.getUnreadCountStream(userId),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            if (unreadCount > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
