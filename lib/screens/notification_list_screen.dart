import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';

/// 通知一覧画面
class NotificationListScreen extends StatefulWidget {
  const NotificationListScreen({super.key});

  @override
  State<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends State<NotificationListScreen> {
  final NotificationService _notificationService = NotificationService();
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    final currentUserId = _authService.currentUser?.uid ?? '';

    if (currentUserId.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              const Expanded(
                child: Center(
                  child: Text(
                    'ログインしてください',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0x80FFFFFF),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: StreamBuilder<List<NotificationModel>>(
                stream: _notificationService.getNotificationsStream(currentUserId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'エラーが発生しました',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0x80FFFFFF),
                        ),
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return _buildEmptyState();
                  }

                  final notifications = snapshot.data!;
                  return RefreshIndicator(
                    onRefresh: () async {
                      setState(() {}); // Force rebuild
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      itemCount: notifications.length,
                      itemBuilder: (context, index) {
                        return _buildNotificationCell(notifications[index]);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              '通知',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          // すべて既読ボタン
          TextButton(
            onPressed: () async {
              final userId = _authService.currentUser?.uid ?? '';
              await _notificationService.markAllAsRead(userId);
            },
            child: const Text(
              'すべて既読',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF5D8FFF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCell(NotificationModel notification) {
    return GestureDetector(
      onTap: () => _handleNotificationTap(notification),
      child: Container(
        decoration: BoxDecoration(
          color: notification.isRead
              ? Colors.transparent
              : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        margin: const EdgeInsets.only(bottom: 8),
        child: _buildNotificationContent(notification),
      ),
    );
  }

  Widget _buildNotificationContent(NotificationModel notification) {
    switch (notification.type) {
      case NotificationType.follow:
        return _buildFollowNotification(notification);
      case NotificationType.like:
        return _buildLikeNotification(notification);
      case NotificationType.comment:
        return _buildCommentNotification(notification);
      case NotificationType.official:
        return _buildOfficialNotification(notification);
      case NotificationType.post:
        return _buildPostNotification(notification);
      case NotificationType.vibe:
        return _buildVibeNotification(notification);
    }
  }

  Widget _buildFollowNotification(NotificationModel notification) {
    return SizedBox(
      height: 59,
      child: Row(
        children: [
          _buildUserIcon(notification.senderIconUrl),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      notification.senderUsername,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      notification.getRelativeTime(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0x80FFFFFF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  notification.getMessage(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0x80FFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostNotification(NotificationModel notification) {
    // バッチ通知（system）の場合はアプリアイコン、個別通知はユーザーアイコン
    final isSystemNotification = notification.senderId == 'system';

    return SizedBox(
      height: 59,
      child: Row(
        children: [
          if (isSystemNotification)
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF2D2D2D),
              ),
              child: const Icon(
                Icons.group,
                color: Color(0xFF5D8FFF),
                size: 24,
              ),
            )
          else
            _buildUserIcon(notification.senderIconUrl),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      isSystemNotification ? '15s' : notification.senderUsername,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      notification.getRelativeTime(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0x80FFFFFF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  notification.getMessage(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0x80FFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVibeNotification(NotificationModel notification) {
    return SizedBox(
      height: 59,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF2D2D2D),
            ),
            child: const Icon(
              Icons.local_fire_department,
              color: Color(0xFFFF6B35),
              size: 24,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      notification.title ?? 'Vibe',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      notification.getRelativeTime(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0x80FFFFFF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  notification.getMessage(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0x80FFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLikeNotification(NotificationModel notification) {
    return SizedBox(
      height: 59,
      child: Row(
        children: [
          _buildUserIcon(notification.senderIconUrl),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      notification.senderUsername,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      notification.getRelativeTime(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0x80FFFFFF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  notification.getMessage(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0x80FFFFFF),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (notification.albumArtUrl != null)
            _buildAlbumArt(notification.albumArtUrl!),
        ],
      ),
    );
  }

  Widget _buildCommentNotification(NotificationModel notification) {
    return SizedBox(
      height: 81,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: _buildUserIcon(notification.senderIconUrl),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        notification.senderUsername,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        notification.getRelativeTime(),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0x80FFFFFF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notification.getMessage(),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0x80FFFFFF),
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (notification.commentText != null)
                    Row(
                      children: [
                        Container(
                          width: 3,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD9D9D9),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            notification.commentText!,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          if (notification.albumArtUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: _buildAlbumArt(notification.albumArtUrl!),
            ),
        ],
      ),
    );
  }

  Widget _buildOfficialNotification(NotificationModel notification) {
    return Container(
      decoration: BoxDecoration(
        color: notification.isRead ? Colors.transparent : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF5D8FFF), width: 1),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign, color: Color(0xFF5D8FFF), size: 20),
              const SizedBox(width: 8),
              Text(
                notification.senderUsername,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5D8FFF),
                ),
              ),
              const Spacer(),
              Text(
                notification.getRelativeTime(),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0x80FFFFFF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (notification.title != null)
            Text(
              notification.title!,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          const SizedBox(height: 4),
          if (notification.body != null)
            Text(
              notification.body!,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xCCFFFFFF),
              ),
            ),
          if (notification.imageUrl != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: notification.imageUrl!,
                fit: BoxFit.cover,
                height: 120,
                width: double.infinity,
                errorWidget: (context, url, error) {
                  return Container(
                    height: 120,
                    color: const Color(0xFF2D2D2D),
                    child: const Center(
                      child: Icon(Icons.broken_image, color: Color(0x40FFFFFF)),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUserIcon(String? imageUrl) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2D2D2D),
        image: imageUrl != null && imageUrl.isNotEmpty
            ? DecorationImage(
                image: CachedNetworkImageProvider(imageUrl),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: imageUrl == null || imageUrl.isEmpty
          ? const Icon(
              Icons.person,
              color: Color(0x40FFFFFF),
              size: 24,
            )
          : null,
    );
  }

  Widget _buildAlbumArt(String imageUrl) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF2D2D2D),
        image: DecorationImage(
          image: CachedNetworkImageProvider(imageUrl),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 80,
            color: Color(0x40FFFFFF),
          ),
          SizedBox(height: 16),
          Text(
            '通知はありません',
            style: TextStyle(
              fontSize: 16,
              color: Color(0x80FFFFFF),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNotificationTap(NotificationModel notification) async {
    // 既読にする
    if (!notification.isRead) {
      await _notificationService.markAsRead(notification.notificationId);
    }

    // TODO: 通知タイプに応じて画面遷移
    // 現時点では画面遷移を実装しない（後のフェーズで実装可能）
    // switch (notification.type) {
    //   case NotificationType.follow:
    //     // プロフィール画面に遷移
    //     break;
    //   case NotificationType.like:
    //   case NotificationType.comment:
    //     // 投稿詳細画面に遷移
    //     break;
    //   case NotificationType.official:
    //     // actionUrlがあれば遷移
    //     break;
    // }
  }
}
