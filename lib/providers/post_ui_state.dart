import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../models/post_model.dart';
import '../services/post_service.dart';

/// 投稿のUI状態を一元管理するプロバイダー（コメント数・いいね）。
///
/// 保存状態は別の `SavedItemsProvider` が管理する（一つのソース・オブ・トゥルース）。
class PostUIState extends ChangeNotifier {
  /// 静的アクセス用のインスタンス参照。
  /// `_runUpload` のような非 widget コンテキストから override を書き込むため。
  static PostUIState? _instance;

  PostUIState() {
    _instance = this;
  }

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

  /// 投稿ごとの countsForAdl 楽観的 override。
  /// 投稿完了直後、Cloud Function の集計トリガーが flag を書く前でも
  /// UI に「@◯◯ を表示するかしないか」を正しく反映するために使う。
  final Map<String, bool> _countsForAdlOverrides = {};

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

    // countsForAdl の楽観的 override を適用（Cloud Function 反映前の暫定値）
    final countsForAdlOverride = _countsForAdlOverrides[post.postId];
    if (countsForAdlOverride != null) {
      displayPost =
          displayPost.copyWith(countsForAdl: countsForAdlOverride);
    }

    return displayPost;
  }

  /// 投稿の countsForAdl 値を楽観的に上書きする。
  /// 投稿完了直後に呼ぶことで、Cloud Function が flag を書く前でも
  /// 「@◯◯ を表示するかしないか」を正しく UI に反映できる。
  void setCountsForAdlOverride(String postId, bool value) {
    _countsForAdlOverrides[postId] = value;
    notifyListeners();
  }

  /// 静的ショートカット。`_runUpload` のような非 widget コンテキスト用。
  static void setCountsForAdlOverrideStatic(String postId, bool value) {
    _instance?.setCountsForAdlOverride(postId, value);
  }

  /// 既存のいいね状態を保持したまま、新しい posts を追加で登録する。
  ///
  /// `resetAndInitialize` と違い既存の楽観的更新を上書きしない。
  /// プロフィール画面や Vibe プレイリスト等、ホーム以外で投稿一覧を
  /// 表示する画面の初期化に使う。これにより、ホームで like → プロフィール
  /// で見ても like 反映済み、という状態が共有される。
  void mergePosts({
    required List<PostModel> posts,
    required String currentUserId,
  }) {
    for (final post in posts) {
      // 既に楽観的更新済みの postId はスキップ（最新の操作結果を保持）
      if (_likeCounts.containsKey(post.postId)) continue;
      _likeCounts[post.postId] = post.likeCount;
      if (post.likedUserIds.contains(currentUserId)) {
        _likedPostIds.add(post.postId);
      }
    }
    notifyListeners();
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

  // ==================== 共通ヘルパー ====================

  /// いいねトグル + Firestore 書き込み + 失敗時ロールバック の共通フロー。
  /// どの画面の onLike からも呼べる。
  Future<void> togglePostLike({
    required PostModel post,
    required String userId,
    required PostService postService,
  }) async {
    final currentLikeCount = getLikeCount(post.postId) ?? post.likeCount;
    final wasLiked = isLiked(post.postId);
    toggleLike(post.postId, currentLikeCount: currentLikeCount);
    try {
      await postService.toggleLike(postId: post.postId, userId: userId);
    } catch (_) {
      revertLikeToggle(
        post.postId,
        originalLikeCount: currentLikeCount,
        wasLiked: wasLiked,
      );
    }
  }

  /// BuildContext から PostUIState を取って togglePostLike を呼ぶショートカット。
  /// `onLike: () => PostUIState.handleLike(context, post, userId, postService)`
  /// の形で書けるので、4 画面の重複コードを排除できる。
  static Future<void> handleLike({
    required BuildContext context,
    required PostModel post,
    required String userId,
    required PostService postService,
  }) async {
    final provider = context.read<PostUIState>();
    await provider.togglePostLike(
      post: post,
      userId: userId,
      postService: postService,
    );
  }
}
