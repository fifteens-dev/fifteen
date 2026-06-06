import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../services/user_service.dart';
import 'other_user_profile_screen.dart';
import 'post_detail_screen.dart';
import '../widgets/common/app_toast.dart';
import 'batch_posts_screen.dart';

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
  // postId → アルバムアートURL のキャッシュ（albumArtUrlが未保存の古い通知向け）
  final Map<String, String?> _albumArtCache = {};
  Timer? _iconRefreshTimer;
  Timer? _markAsReadTimer;
  bool _isNavigating = false;
  // 3秒後に視覚的に既読化するためのローカルフラグ
  bool _visuallyRead = false;
  // タップして開いた通知IDのローカル既読セット（Firestoreストリーム更新前に視覚反映）
  final Set<String> _openedNotificationIds = {};

  // ── ページネーション状態 ──────────────────────────────────────
  static const int _pageSize = 20;
  final List<NotificationModel> _notifications = [];
  final Set<String> _loadedIds = {};
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  // 先頭ページのみリアルタイム監視（新着反映用）
  StreamSubscription<List<NotificationModel>>? _firstPageSubscription;
  // スクロール検知
  final ScrollController _scrollController = ScrollController();
  static const double _loadMoreThreshold = 400;

  @override
  void initState() {
    super.initState();
    _currentUserId = _authService.currentUser?.uid ?? '';
    if (_currentUserId.isNotEmpty) {
      _loadInitial();
      _subscribeFirstPage();
    }
    _scrollController.addListener(_onScroll);
    _loadCurrentUsername();
    // 5分ごとにアイコンURLを再取得
    _iconRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _refreshIcons(),
    );
    // 3秒後に視覚的に既読化（グレー化）
    // Firestore への書き込みは dispose() で保証するため、ここは UI 更新のみ
    _markAsReadTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() { _visuallyRead = true; });
    });
  }

  Future<void> _loadInitial() async {
    try {
      final result = await _notificationService.getNotificationsPaged(
        _currentUserId,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _notifications.clear();
        _loadedIds.clear();
        for (final n in result.notifications) {
          if (_loadedIds.add(n.notificationId)) _notifications.add(n);
        }
        _lastDoc = result.lastDoc;
        _hasMore = result.hasMore;
        _isInitialLoading = false;
      });
      _refreshIcons();
      _fetchMissingAlbumArts(result.notifications);
    } catch (_) {
      if (mounted) setState(() => _isInitialLoading = false);
    }
  }

  /// 先頭ページのみリアルタイム監視。新着通知は upsert。
  void _subscribeFirstPage() {
    _firstPageSubscription?.cancel();
    _firstPageSubscription = _notificationService
        .getNotificationsStream(_currentUserId, limit: _pageSize)
        .listen((latest) {
      if (!mounted) return;
      bool changed = false;
      // 先頭に新規通知をマージ（既存はFirestore側更新でstreamが反映）
      for (final n in latest) {
        if (!_loadedIds.contains(n.notificationId)) {
          _notifications.insert(0, n);
          _loadedIds.add(n.notificationId);
          changed = true;
        } else {
          // 既存通知の更新（既読フラグなど）を反映
          final idx = _notifications.indexWhere(
              (e) => e.notificationId == n.notificationId);
          if (idx != -1) {
            _notifications[idx] = n;
            changed = true;
          }
        }
      }
      if (changed) {
        setState(() {});
        _refreshIcons();
        _fetchMissingAlbumArts(latest);
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - _loadMoreThreshold) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await _notificationService.getNotificationsPaged(
        _currentUserId,
        limit: _pageSize,
        startAfter: _lastDoc,
      );
      if (!mounted) return;
      setState(() {
        for (final n in result.notifications) {
          if (_loadedIds.add(n.notificationId)) _notifications.add(n);
        }
        _lastDoc = result.lastDoc ?? _lastDoc;
        _hasMore = result.hasMore;
        _isLoadingMore = false;
      });
      _refreshIcons();
      _fetchMissingAlbumArts(result.notifications);
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
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
    _firstPageSubscription?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    // 画面を離れるタイミング（戻るボタン含む）で必ず既読化
    // タイマーが3秒未満でキャンセルされた場合でも Firestore に書き込む
    if (_currentUserId.isNotEmpty) {
      _notificationService.markAllAsRead(_currentUserId).catchError((_) {});
    }
    super.dispose();
  }

  /// postIdを持つがalbumArtUrlが未保存の通知のアルバムアートを遅延取得
  Future<void> _fetchMissingAlbumArts(List<NotificationModel> notifications) async {
    final postIds = notifications
        .where((n) =>
            (n.albumArtUrl == null || n.albumArtUrl!.isEmpty) &&
            // バッチ通知は postIds[0] を使用、単独通知は postId を使用
            ((n.postIds != null && n.postIds!.isNotEmpty)
                ? !_albumArtCache.containsKey(n.postIds!.first)
                : (n.postId != null &&
                    n.postId!.isNotEmpty &&
                    !_albumArtCache.containsKey(n.postId))))
        .map((n) => n.postIds != null && n.postIds!.isNotEmpty
            ? n.postIds!.first
            : n.postId!)
        .toSet()
        .toList();

    if (postIds.isEmpty) return;

    final results = await Future.wait(
      postIds.map((pid) async {
        final post = await _postService.getPost(pid);
        return MapEntry(pid, post?.track.albumImageUrl);
      }),
    );

    if (mounted) {
      setState(() {
        for (final entry in results) {
          _albumArtCache[entry.key] = entry.value;
        }
      });
    }
  }

  /// 通知送信者の最新アイコンURLをまとめて取得（並列・未取得分のみ）
  Future<void> _refreshIcons() async {
    final refreshStart = DateTime.now();

    if (_notifications.isNotEmpty) {
      // system など固定送信者を除外し、キャッシュ済みのIDはスキップ
      final senderIds = _notifications
          .map((n) => n.senderId)
          .where((id) => id.isNotEmpty && id != 'system' && !_freshIconUrls.containsKey(id))
          .toSet()
          .toList();

      if (senderIds.isNotEmpty) {
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
    }

    // 最低1秒はリフレッシュインジケーターを表示
    final elapsed = DateTime.now().difference(refreshStart);
    if (elapsed < const Duration(seconds: 1)) {
      await Future.delayed(const Duration(seconds: 1) - elapsed);
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
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notifications.isEmpty) {
      return _buildEmptyState();
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: () async {
            await _loadInitial();
          },
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  _buildNotificationCell(_notifications[index]),
              childCount: _notifications.length,
            ),
          ),
        ),
        if (_isLoadingMore)
          const SliverPadding(
            padding: EdgeInsets.symmetric(vertical: 16),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CupertinoActivityIndicator(color: Colors.white),
                ),
              ),
            ),
          ),
        if (!_hasMore && _notifications.length > _pageSize)
          const SliverPadding(
            padding: EdgeInsets.symmetric(vertical: 16),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: Text(
                  'すべての通知を表示しました',
                  style: TextStyle(color: Color(0x40FFFFFF), fontSize: 12),
                ),
              ),
            ),
          ),
      ],
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
    final isRead = notification.isRead || _visuallyRead ||
        _openedNotificationIds.contains(notification.notificationId);
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
      case NotificationType.mention:
        return _buildMentionNotification(notification);
    }
  }

  Widget _buildFollowNotification(NotificationModel notification) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildUserIcon(notification.senderIconUrl, senderId: notification.senderId),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                  '${notification.senderUsername}があなたをフォローしました',
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
            HapticFeedback.mediumImpact();
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
              mainAxisSize: MainAxisSize.min,
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
          () {
            // バッチ通知は最初の投稿のアルバムアートを使用
            final lookupId = notification.postIds != null && notification.postIds!.isNotEmpty
                ? notification.postIds!.first
                : notification.postId;
            final artUrl = notification.albumArtUrl ??
                (lookupId != null ? _albumArtCache[lookupId] : null);
            if (artUrl != null && artUrl.isNotEmpty) {
              return Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 16),
                _buildAlbumArt(artUrl),
              ]);
            }
            return const SizedBox.shrink();
          }(),
        ],
      ),
    );
  }

  Widget _buildMentionNotification(NotificationModel notification) {
    final artUrl = notification.albumArtUrl ??
        (notification.postId != null ? _albumArtCache[notification.postId] : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUserIcon(notification.senderIconUrl, senderId: notification.senderId),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                      style: const TextStyle(fontSize: 14, color: Color(0x80FFFFFF)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  notification.getMessage(),
                  style: const TextStyle(fontSize: 14, color: Color(0x80FFFFFF)),
                ),
                if (notification.commentText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '"${notification.commentText}"',
                    style: const TextStyle(fontSize: 12, color: Color(0x60FFFFFF)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (artUrl != null && artUrl.isNotEmpty)
            _buildAlbumArt(artUrl),
        ],
      ),
    );
  }

  Widget _buildVibeNotification(NotificationModel notification) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
              mainAxisSize: MainAxisSize.min,
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
    final artUrl = notification.albumArtUrl ??
        (notification.postId != null ? _albumArtCache[notification.postId] : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildUserIcon(notification.senderIconUrl, senderId: notification.senderId),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
          if (artUrl != null && artUrl.isNotEmpty)
            _buildAlbumArt(artUrl),
        ],
      ),
    );
  }

  Widget _buildCommentNotification(NotificationModel notification) {
    final artUrl = notification.albumArtUrl ??
        (notification.postId != null ? _albumArtCache[notification.postId] : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUserIcon(notification.senderIconUrl, senderId: notification.senderId),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
          const SizedBox(width: 16),
          if (artUrl != null && artUrl.isNotEmpty)
            _buildAlbumArt(artUrl),
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

    return SizedBox(
      width: 42,
      height: 42,
      child: Container(
        width: 42,
        height: 42,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF2D2D2D),
        ),
        clipBehavior: Clip.antiAlias,
        child: url != null && url.isNotEmpty
            ? CachedNetworkImage(
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
              )
            : const Icon(
                Icons.person,
                color: Color(0x40FFFFFF),
                size: 24,
              ),
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
      // ローカル開封済みとして記録（戻った時に即座に視覚反映）
      _openedNotificationIds.add(notification.notificationId);

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
        case NotificationType.mention:
          // バッチ通知（複数postIds）→ スクロール可能な投稿リスト画面へ
          if (notification.postIds != null && notification.postIds!.length > 1) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BatchPostsScreen(
                  postIds: notification.postIds!,
                  currentUserId: currentUserId,
                ),
              ),
            );
          } else if (notification.postId != null && notification.postId!.isNotEmpty) {
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
              AppToast.show(context, '投稿が見つかりませんでした');
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
        setState(() { _isNavigating = false; });
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
