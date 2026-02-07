import 'package:flutter/foundation.dart';
import '../models/post_model.dart';

/// 投稿のUI状態を一元管理するプロバイダー
///
/// 楽観的UI更新のための状態（コメント数、いいね数、いいね状態、保存状態）を管理します。
/// 複数の画面（ホーム、プロフィール等）で共有可能な状態を提供します。
class PostUIState extends ChangeNotifier {
  /// 投稿ごとのコメント数（楽観的UI更新用）
  final Map<String, int> _commentCounts = {};

  /// 投稿ごとのいいね数（楽観的UI更新用）
  final Map<String, int> _likeCounts = {};

  /// ユーザーがいいねした投稿IDのセット（楽観的UI更新用）
  final Set<String> _likedPostIds = {};

  /// ユーザーが保存した投稿IDのセット（楽観的UI更新用）
  final Set<String> _savedPostIds = {};

  /// いいねしたユーザーのアイコンURL（postId -> iconUrls）
  final Map<String, List<String>> _likedUserIconUrls = {};

  /// いいねしたユーザーのID（postId -> userIds）
  final Map<String, List<String>> _likedUserIds = {};

  // ==================== ゲッター ====================

  /// 投稿のコメント数を取得
  int? getCommentCount(String postId) => _commentCounts[postId];

  /// 投稿のいいね数を取得
  int? getLikeCount(String postId) => _likeCounts[postId];

  /// 投稿がいいねされているか
  bool isLiked(String postId) => _likedPostIds.contains(postId);

  /// 投稿が保存されているか
  bool isSaved(String postId) => _savedPostIds.contains(postId);

  /// いいねしたユーザーのアイコンURLを取得
  List<String> getLikedUserIconUrls(String postId) =>
      _likedUserIconUrls[postId] ?? [];

  /// いいねしたユーザーIDを取得
  List<String> getLikedUserIds(String postId) => _likedUserIds[postId] ?? [];

  // ==================== 初期化 ====================

  /// いいね状態を初期化（投稿のリストから）
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

  /// 保存状態を初期化
  void initializeSavedPosts(Set<String> savedPostIds) {
    _savedPostIds.addAll(savedPostIds);
    notifyListeners();
  }

  /// いいねしたユーザー情報を設定
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

  /// コメント数を更新
  void updateCommentCount(String postId, int count) {
    _commentCounts[postId] = count;
    notifyListeners();
  }

  /// いいね数を更新
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
      // いいね解除
      _likedPostIds.remove(postId);
      _likeCounts[postId] = currentLikeCount - 1;
    } else {
      // いいね追加
      _likedPostIds.add(postId);
      _likeCounts[postId] = currentLikeCount + 1;
    }

    notifyListeners();
    return !wasLiked;
  }

  /// いいね状態を復元（エラー時のロールバック用）
  void revertLikeToggle(String postId, {required int originalLikeCount, required bool wasLiked}) {
    if (wasLiked) {
      _likedPostIds.add(postId);
    } else {
      _likedPostIds.remove(postId);
    }
    _likeCounts[postId] = originalLikeCount;
    notifyListeners();
  }

  /// 保存状態をトグル（楽観的UI更新用）
  /// 戻り値: 新しい保存状態（true = 保存済み）
  bool toggleSave(String postId) {
    final wasSaved = _savedPostIds.contains(postId);

    if (wasSaved) {
      _savedPostIds.remove(postId);
    } else {
      _savedPostIds.add(postId);
    }

    notifyListeners();
    return !wasSaved;
  }

  /// 保存状態を復元（エラー時のロールバック用）
  void revertSaveToggle(String postId) {
    if (_savedPostIds.contains(postId)) {
      _savedPostIds.remove(postId);
    } else {
      _savedPostIds.add(postId);
    }
    notifyListeners();
  }

  // ==================== 表示用ヘルパー ====================

  /// 表示用のPostModelを取得（楽観的UI状態を適用）
  PostModel getDisplayPost(PostModel post, {String? currentUserId}) {
    var displayPost = post;

    // コメント数のオーバーライド
    final commentCount = _commentCounts[post.postId];
    if (commentCount != null) {
      displayPost = displayPost.copyWith(commentCount: commentCount);
    }

    // いいね数のオーバーライド
    final likeCount = _likeCounts[post.postId];
    if (likeCount != null) {
      displayPost = displayPost.copyWith(likeCount: likeCount);
    }

    // いいね状態のオーバーライド
    if (currentUserId != null) {
      final isLikedByUser = _likedPostIds.contains(post.postId);
      final updatedLikedUserIds = List<String>.from(displayPost.likedUserIds);

      if (isLikedByUser && !updatedLikedUserIds.contains(currentUserId)) {
        updatedLikedUserIds.add(currentUserId);
        displayPost = displayPost.copyWith(likedUserIds: updatedLikedUserIds);
      } else if (!isLikedByUser && _likeCounts.containsKey(post.postId)) {
        // いいね解除した場合
        updatedLikedUserIds.remove(currentUserId);
        displayPost = displayPost.copyWith(likedUserIds: updatedLikedUserIds);
      }
    }

    return displayPost;
  }

  // ==================== クリア ====================

  /// 全状態をクリア
  void clear() {
    _commentCounts.clear();
    _likeCounts.clear();
    _likedPostIds.clear();
    _savedPostIds.clear();
    _likedUserIconUrls.clear();
    _likedUserIds.clear();
    notifyListeners();
  }

  /// 特定の投稿の状態をクリア
  void clearPost(String postId) {
    _commentCounts.remove(postId);
    _likeCounts.remove(postId);
    _likedPostIds.remove(postId);
    _savedPostIds.remove(postId);
    _likedUserIconUrls.remove(postId);
    _likedUserIds.remove(postId);
    notifyListeners();
  }
}
