import 'package:flutter/foundation.dart';
import '../models/post_model.dart';

/// 投稿のUI状態を一元管理するプロバイダー（コメント数・いいね）。
///
/// 保存状態は別の `SavedItemsProvider` が管理する（一つのソース・オブ・トゥルース）。
class PostUIState extends ChangeNotifier {
  /// 投稿ごとのコメント数（楽観的UI更新用）
  final Map<String, int> _commentCounts = {};

  /// 投稿ごとのいいね数（楽観的UI更新用）
  final Map<String, int> _likeCounts = {};

  /// ユーザーがいいねした投稿IDのセット（楽観的UI更新用）
  final Set<String> _likedPostIds = {};

  /// いいねしたユーザーのアイコンURL（postId -> iconUrls）
  final Map<String, List<String>> _likedUserIconUrls = {};

  /// いいねしたユーザーのID（postId -> userIds）
  final Map<String, List<String>> _likedUserIds = {};

  // ==================== ゲッター ====================

  int? getCommentCount(String postId) => _commentCounts[postId];

  int? getLikeCount(String postId) => _likeCounts[postId];

  bool isLiked(String postId) => _likedPostIds.contains(postId);

  List<String> getLikedUserIconUrls(String postId) =>
      _likedUserIconUrls[postId] ?? [];

  List<String> getLikedUserIds(String postId) => _likedUserIds[postId] ?? [];

  // ==================== 初期化 ====================

  void initializeLikeStates({
    required List<PostModel> posts,
    required String currentUserId,
    required Map<String, Map<String, dynamic>> likeStates,
  }) {
    for (final post in posts) {
      final likeState = likeStates[post.postId];
      if (likeState != null) {
        final likeCount = likeState['likeCount'] as int? ?? 0;
        final likedUserIds = List<String>.from(likeState['likedUserIds'] ?? []);

        if (likeCount > 0) {
          _likeCounts[post.postId] = likeCount;
        }

        if (likedUserIds.contains(currentUserId)) {
          _likedPostIds.add(post.postId);
        }
      }
    }
    notifyListeners();
  }

  void setLikedUsers({
    required String postId,
    required List<String> iconUrls,
    required List<String> userIds,
  }) {
    _likedUserIconUrls[postId] = iconUrls;
    _likedUserIds[postId] = userIds;
    notifyListeners();
  }

  // ==================== 更新操作 ====================

  void updateCommentCount(String postId, int count) {
    _commentCounts[postId] = count;
    notifyListeners();
  }

  void updateLikeCount(String postId, int count) {
    if (count > 0) {
      _likeCounts[postId] = count;
    } else {
      _likeCounts.remove(postId);
    }
    notifyListeners();
  }

  /// いいね状態をトグル（楽観的UI更新用）
  /// 戻り値: 新しいいいね状態（true = いいね済み）
  bool toggleLike(String postId, {required int currentLikeCount}) {
    final wasLiked = _likedPostIds.contains(postId);

    if (wasLiked) {
      _likedPostIds.remove(postId);
      _likeCounts[postId] = currentLikeCount - 1;
    } else {
      _likedPostIds.add(postId);
      _likeCounts[postId] = currentLikeCount + 1;
    }

    notifyListeners();
    return !wasLiked;
  }

  /// いいね状態を復元（エラー時のロールバック用）
  void revertLikeToggle(String postId,
      {required int originalLikeCount, required bool wasLiked}) {
    if (wasLiked) {
      _likedPostIds.add(postId);
    } else {
      _likedPostIds.remove(postId);
    }
    _likeCounts[postId] = originalLikeCount;
    notifyListeners();
  }

  // ==================== 表示用ヘルパー ====================

  /// 表示用のPostModelを取得（楽観的UI状態を適用）
  PostModel getDisplayPost(
    PostModel post, {
    String? currentUserId,
    String? currentUserIconUrl,
  }) {
    var displayPost = post;

    final commentCount = _commentCounts[post.postId];
    if (commentCount != null) {
      displayPost = displayPost.copyWith(commentCount: commentCount);
    }

    final likeCount = _likeCounts[post.postId];
    if (likeCount != null) {
      displayPost = displayPost.copyWith(likeCount: likeCount);
    }

    if (currentUserId != null && _likeCounts.containsKey(post.postId)) {
      final isLikedByUser = _likedPostIds.contains(post.postId);

      final updatedLikedUserIds = List<String>.from(displayPost.likedUserIds);
      if (isLikedByUser && !updatedLikedUserIds.contains(currentUserId)) {
        updatedLikedUserIds.add(currentUserId);
        displayPost = displayPost.copyWith(likedUserIds: updatedLikedUserIds);
      } else if (!isLikedByUser && updatedLikedUserIds.contains(currentUserId)) {
        updatedLikedUserIds.remove(currentUserId);
        displayPost = displayPost.copyWith(likedUserIds: updatedLikedUserIds);
      }

      if (currentUserIconUrl != null) {
        final updatedIconUrls = List<String>.from(displayPost.likedByUserIconUrls);
        if (isLikedByUser && !updatedIconUrls.contains(currentUserIconUrl)) {
          updatedIconUrls.add(currentUserIconUrl);
          displayPost =
              displayPost.copyWith(likedByUserIconUrls: updatedIconUrls);
        } else if (!isLikedByUser && updatedIconUrls.contains(currentUserIconUrl)) {
          updatedIconUrls.remove(currentUserIconUrl);
          displayPost =
              displayPost.copyWith(likedByUserIconUrls: updatedIconUrls);
        }
      }
    }

    return displayPost;
  }

  // ==================== 初期化（一括リセット） ====================

  /// 画面ロード・プルダウンリフレッシュ時に呼ぶ
  void resetAndInitialize({
    required List<PostModel> posts,
    required String currentUserId,
  }) {
    _likeCounts.clear();
    _likedPostIds.clear();
    _commentCounts.clear();
    _likedUserIconUrls.clear();
    _likedUserIds.clear();

    for (final post in posts) {
      _likeCounts[post.postId] = post.likeCount;
      if (post.likedUserIds.contains(currentUserId)) {
        _likedPostIds.add(post.postId);
      }
    }

    notifyListeners();
  }

  // ==================== クリア ====================

  void clear() {
    _commentCounts.clear();
    _likeCounts.clear();
    _likedPostIds.clear();
    _likedUserIconUrls.clear();
    _likedUserIds.clear();
    notifyListeners();
  }

  void clearPost(String postId) {
    _commentCounts.remove(postId);
    _likeCounts.remove(postId);
    _likedPostIds.remove(postId);
    _likedUserIconUrls.remove(postId);
    _likedUserIds.remove(postId);
    notifyListeners();
  }
}
