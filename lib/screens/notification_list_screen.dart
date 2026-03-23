import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../services/user_service.dart';
import 'other_user_profile_screen.dart';
import 'post_detail_screen.dart';

/// 通知一覧画面
class NotificationListScreen extends StatefulWidget {
  const NotificationListScreen({super.key});

  @override
  State<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends State<NotificationListScreen> {
  final NotificationService _notificationService = NotificationService();
  final AuthService _authService = AuthService();
  final PostService _postService = PostService();
  final UserService _userService = UserService();

  String _currentUserId = '';
  String _currentUsername = '';

  // senderId → 最新アイコンURL のキャッシュ
  final Map<String, String?> _freshIconUrls = {};
  List<NotificationModel> _latestNotifications = [];
  Timer? _iconRefreshTimer;
  Timer? _markAsReadTimer;
  bool _isNavigating = false;
  bool _hasMarkedAsRead = false;
  // 3秒後に視覚的に既読化するためのローカルフラグ
  bool _visuallyRead = false;
  // StreamBuilderが再サブスクライブしないようにキャッシュ
  Stream<List<NotificationModel>>? _notificationsStream;

  @override
  void initState() {
    super.initState();
    _currentUserId = _authService.currentUser?.uid ?? '';
    if (_currentUserId.isNotEmpty) {
      _notificationsStream = _notificationService.getNotificationsStream(_currentUserId);
    }
    _loadCurrentUsername();
    // 5分ごとにアイコンURLを再取得
    _iconRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _refreshIcons(),
    );
    // 3秒後に既読化（視覚的にもグレー化）
    _markAsReadTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() { _visuallyRead = true; });
      if (_currentUserId.isNotEmpty) {
        _notificationService.markAllAsRead(_currentUserId).catchError((_) {});
      }
    });
  }

  Future<void> _loadCurrentUsername() async {
    if (_currentUserId.isEmpty) return;
    final user = await _userService.getUser(_currentUserId);
    if (mounted) {
      setState(() => _currentUsername = user?.username ?? '');
    }
  }

  @override
  void dispose() {
    _iconRefreshTimer?.cancel();
    _markAsReadTimer?.cancel();
    super.dispose();
  }

  /// 通知送信者の最新アイコンURLをまとめて取得（並列・未取得分のみ）
  Future<void> _refreshIcons() async {
    if (_latestNotifications.isEmpty) return;

    // system など固定送信者を除外し、キャッシュ済みのIDはスキップ
    final senderIds = _latestNotifications
        .map((n) => n.senderId)
        .where((id) => id.isNotEmpty && id != 'system' && !_freshIconUrls.containsKey(id))
        .toSet()
        .toList();

    if (senderIds.isEmpty) return;

    final results = await Future.wait(
      senderIds.map((id) async {
        final user = await _userService.getUser(id);
        return MapEntry(id, user?.profileImageUrl);
      }),
    );

    if (mounted) {
      setState(() {
        for (final entry in results) {
          _freshIconUrls[entry.key] = entry.value;
        }
      });
    }
  }

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
                stream: _notificationsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
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

                  // 通知リストが変わったらアイコンを更新
                  if (_latestNotifications.length != notifications.length ||
                      _latestNotifications.isEmpty) {
                    _latestNotifications = notifications;
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _refreshIcons(),
                    );
                  }

                  // 既読化はTimerで3秒後に行う（initStateで設定済み）

                  return RefreshIndicator(
                    onRefresh: () async {
                      await _refreshIcons();
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
          Text(
            _currentUsername,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCell(NotificationModel notification) {
    final isRead = notification.isRead || _visuallyRead;
    return GestureDetector(
      onTap: () => _handleNotificationTap(notification),
      child: Container(
        decoration: BoxDecoration(
          color: isRead
              ? Colors.transparent
              : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
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
          _buildUserIcon(notification.senderIconUrl, senderId: notification.senderId),
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
          const SizedBox(width: 12),
          _buildFollowButton(notification.senderId),
        ],
      ),
    );
  }

  /// フォローボタン（フォロー状態を FutureBuilder で判定）
  Widget _buildFollowButton(String senderId) {
    if (senderId.isEmpty || senderId == 'system' || senderId == _currentUserId) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<bool>(
      future: _isFollowing(senderId),
      builder: (context, snapshot) {
        final isFollowing = snapshot.data ?? false;
        return GestureDetector(
          onTap: () async {
            try {
              if (isFollowing) {
                await _userService.unfollowUser(
                  currentUserId: _currentUserId,
                  targetUserId: senderId,
                );
              } else {
                await _userService.followUser(
                  currentUserId: _currentUserId,
                  targetUserId: senderId,
                );
              }
              if (mounted) setState(() {});
            } catch (_) {}
          },
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isFollowing ? Colors.transparent : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: isFollowing
                  ? Border.all(color: Colors.white54)
                  : null,
            ),
            child: Center(
              child: Text(
                isFollowing ? 'フォロー中' : 'フォロー',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isFollowing ? Colors.white54 : Colors.black,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _isFollowing(String targetUserId) async {
    if (_currentUserId.isEmpty) return false;
    try {
      final me = await _userService.getUser(_currentUserId);
      return me?.following.contains(targetUserId) ?? false;
    } catch (_) {
      return false;
    }
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
            _buildUserIcon(notification.senderIconUrl, senderId: notification.senderId),
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
          if (notification.albumArtUrl != null) ...[
            const SizedBox(width: 16),
            _buildAlbumArt(notification.albumArtUrl!),
          ],
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
          _buildUserIcon(notification.senderIconUrl, senderId: notification.senderId),
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
            child: _buildUserIcon(notification.senderIconUrl, senderId: notification.senderId),
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
    final hasLink = (notification.actionUrl != null &&
            notification.actionUrl!.isNotEmpty) ||
        (notification.postId != null && notification.postId!.isNotEmpty);

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
              if (hasLink) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0x80FFFFFF),
                  size: 18,
                ),
              ],
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
                memCacheHeight: 240,
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

  // senderId を渡して最新URLを優先表示
  Widget _buildUserIcon(String? fallbackUrl, {String? senderId}) {
    final url = (senderId != null && _freshIconUrls.containsKey(senderId))
        ? _freshIconUrls[senderId]
        : fallbackUrl;

    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF2D2D2D),
      ),
      child: url != null && url.isNotEmpty
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: url,
                width: 42,
                height: 42,
                memCacheWidth: 84,
                memCacheHeight: 84,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const Icon(
                  Icons.person,
                  color: Color(0x40FFFFFF),
                  size: 24,
                ),
              ),
            )
          : const Icon(
              Icons.person,
              color: Color(0x40FFFFFF),
              size: 24,
            ),
    );
  }

  Widget _buildAlbumArt(String imageUrl) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: 42,
        height: 42,
        memCacheWidth: 84,
        memCacheHeight: 84,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(
          width: 42,
          height: 42,
          color: const Color(0xFF2D2D2D),
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
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      // 既読にする（awaitしない — ナビゲーションと並行して実行。エラーは握りつぶす）
      if (!notification.isRead) {
        _notificationService.markAsRead(notification.notificationId).catchError((_) {});
      }

      if (!mounted) return;

      final currentUserId = _currentUserId;

      switch (notification.type) {
        case NotificationType.follow:
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  OtherUserProfileScreen(userId: notification.senderId),
            ),
          );
          break;
        case NotificationType.like:
        case NotificationType.comment:
        case NotificationType.post:
          if (notification.postId != null && notification.postId!.isNotEmpty) {
            final post = await _postService.getPost(notification.postId!);
            if (mounted && post != null) {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PostDetailScreen(
                    post: post,
                    currentUserId: currentUserId,
                    alwaysShowBack: false,
                  ),
                ),
              );
            } else if (mounted) {
              // 投稿が存在しない → 孤立通知を削除
              _notificationService
                  .deleteNotification(notification.notificationId)
                  .catchError((_) {});
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('投稿が見つかりませんでした'),
                    duration: Duration(seconds: 2),
                  ),
                );
              await Future.delayed(const Duration(seconds: 2));
            }
          }
          break;
        case NotificationType.vibe:
        case NotificationType.official:
          // postId があれば投稿へ、なければ actionUrl をブラウザで開く
          if (notification.postId != null && notification.postId!.isNotEmpty) {
            final post = await _postService.getPost(notification.postId!);
            if (mounted && post != null) {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PostDetailScreen(
                    post: post,
                    currentUserId: currentUserId,
                    alwaysShowBack: false,
                  ),
                ),
              );
            }
          } else if (notification.actionUrl != null &&
              notification.actionUrl!.isNotEmpty) {
            await _launchUrl(notification.actionUrl!);
          }
          break;
      }
    } finally {
      if (mounted) {
        _isNavigating = false;
      }
    }
  }

  /// URLを外部ブラウザで開く
  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }
}
