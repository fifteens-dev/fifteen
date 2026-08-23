import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/post_model.dart';
import '../models/post_theme.dart';
import '../models/vibe_ranking_item.dart';
import '../models/track_model.dart';
import '../utils/campus_vibe_utils.dart';
import 'post_fetch_service.dart';
import 'post_write_service.dart';
import 'post_check_service.dart';

/// 投稿データを管理するサービス（ファサード）
/// 各責務は PostFetchService / PostWriteService / PostCheckService に委譲
class PostService {
  final PostFetchService _fetchService = PostFetchService();
  final PostWriteService _writeService = PostWriteService();
  final PostCheckService _checkService = PostCheckService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _postsCollection = 'posts';

  // ─── Fetch ───────────────────────────────────────

  /// 投稿を取得（ページネーション付き、24時間以内のみ）
  Future<List<PostModel>> getPosts({
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) => _fetchService.getPosts(limit: limit, startAfter: startAfter);

  /// フォロー中のユーザーの投稿を取得
  Future<List<PostModel>> getPostsForFollowing(List<String> userIds, {int limit = 50}) =>
      _fetchService.getPostsForFollowing(userIds, limit: limit);

  /// 特定のユーザーの投稿を取得（Future版）
  Future<List<PostModel>> getPostsByUserId(String userId, {int limit = 20}) =>
      _fetchService.getPostsByUserId(userId, limit: limit);

  /// Vibe ストーリーバー用: 過去 24h の投稿をユーザー単位でグループ化して取得。
  ///
  /// [userIds] には「自分のフォロー + 自分」を想定。[viewerFollowsAuthor] は鍵投稿の
  /// 可視性判定に使う（自分自身は常に可視、フォロー先の鍵投稿も可視）。
  Future<List<List<PostModel>>> getRecentPostsGroupedByUser({
    required List<String> userIds,
    required bool Function(String authorUid) viewerFollowsAuthor,
  }) =>
      _fetchService.getRecentPostsGroupedByUser(
        userIds: userIds,
        viewerFollowsAuthor: viewerFollowsAuthor,
      );

  /// ユーザーの投稿をカーソルページネーション付きで取得
  Future<({List<PostModel> posts, DocumentSnapshot? lastDoc, bool hasMore})>
      getPostsByUserIdPaged(
    String userId, {
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) => _fetchService.getPostsWithPagination(userId, limit: limit, startAfter: startAfter);

  /// ユーザーの投稿を createdAt 範囲 [start, end) で取得（Music Memory 遅延ロード用）
  Future<List<PostModel>> getUserPostsInRange(
    String userId,
    DateTime start,
    DateTime end,
  ) => _fetchService.getUserPostsInRange(userId, start, end);

  /// 指定 trackId の投稿をカーソルページネーション付きで取得
  Future<({List<PostModel> posts, DocumentSnapshot? lastDoc, bool hasMore})>
      getPostsByTrackIdPaged(
    String trackId, {
    int limit = 12,
    DocumentSnapshot? startAfter,
  }) => _fetchService.getPostsByTrackIdPaged(trackId, limit: limit, startAfter: startAfter);

  /// 特定のユーザーが保存した投稿を取得
  Future<List<PostModel>> getPostsSavedByUser(String userId, {int limit = 50}) =>
      _fetchService.getPostsSavedByUser(userId, limit: limit);

  /// 特定の投稿を取得
  Future<PostModel?> getPost(String postId) => _fetchService.getPost(postId);

  /// ユーザーの投稿数を取得（Firestoreカウントクエリ）
  Future<int> getPostCountByUserId(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('userId', isEqualTo: userId)
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      if (kDebugMode) print('getPostCountByUserId error: $e');
      return 0;
    }
  }

  /// 複数の投稿IDから投稿リストを取得
  Future<List<PostModel>> getPostsByIds(List<String> postIds) async {
    if (postIds.isEmpty) return [];
    try {
      final futures = postIds.map((id) => _fetchService.getPost(id));
      final results = await Future.wait(futures);
      return results.whereType<PostModel>().toList();
    } catch (e) {
      if (kDebugMode) print('getPostsByIds error: $e');
      return [];
    }
  }

  // ─── Write ───────────────────────────────────────

  /// 投稿を作成
  Future<String> createPost({
    required String userId,
    required String username,
    String? userIconUrl,
    required Map<String, dynamic> trackData,
    String? photoUrl,
    double imageOffsetX = 0.0,
    double imageOffsetY = 0.0,
    double imageScale = 1.0,
    double imageNaturalWidth = 0.0,
    double imageNaturalHeight = 0.0,
    int selectedLayoutIndex = 0,
    double cardPositionX = 0.0,
    double cardPositionY = 0.0,
    double cardScale = 1.0,
    double cardRotation = 0.0,
    bool isVibe = false,
    bool isMoodPost = false,
    bool hideBackOverlays = false,
    String? vibeTopicId,
    String? vibeTopicTitle,
    String? emotionTag,
    PostTheme? theme,
    String? lyricsText,
    int audioStartMs = 0,
    int audioDurationSec = 15,
    String? university,
    bool campusVibeParticipating = true,
    String? adlTeamId,
    String audience = 'public',
  }) => _writeService.createPost(
    userId: userId,
    username: username,
    userIconUrl: userIconUrl,
    trackData: trackData,
    photoUrl: photoUrl,
    imageOffsetX: imageOffsetX,
    imageOffsetY: imageOffsetY,
    imageScale: imageScale,
    imageNaturalWidth: imageNaturalWidth,
    imageNaturalHeight: imageNaturalHeight,
    selectedLayoutIndex: selectedLayoutIndex,
    cardPositionX: cardPositionX,
    cardPositionY: cardPositionY,
    cardScale: cardScale,
    cardRotation: cardRotation,
    isVibe: isVibe,
    isMoodPost: isMoodPost,
    hideBackOverlays: hideBackOverlays,
    vibeTopicId: vibeTopicId,
    vibeTopicTitle: vibeTopicTitle,
    emotionTag: emotionTag,
    theme: theme,
    lyricsText: lyricsText,
    audioStartMs: audioStartMs,
    audioDurationSec: audioDurationSec,
    university: university,
    campusVibeParticipating: campusVibeParticipating,
    adlTeamId: adlTeamId,
    audience: audience,
  );

  /// 投稿を削除
  Future<void> deletePost(String postId) => _writeService.deletePost(postId);

  /// 投稿の写真URLを更新（分割アップロード後のバックグラウンド反映用）
  Future<void> updatePostPhotoUrl({
    required String postId,
    required String photoUrl,
  }) => _writeService.updatePostPhotoUrl(postId: postId, photoUrl: photoUrl);

  /// 投稿の歌詞テキストを更新
  Future<void> updateLyricsText({
    required String postId,
    required String lyricsText,
  }) => _writeService.updateLyricsText(postId: postId, lyricsText: lyricsText);

  /// いいねをトグル（追加/削除）
  Future<void> toggleLike({
    required String postId,
    required String userId,
  }) => _writeService.toggleLike(postId: postId, userId: userId);

  /// 絵文字リアクションを設定/変更/解除（1ユーザー＝1つ）
  Future<void> setReaction({
    required String postId,
    required String emoji,
    required String userId,
  }) => _writeService.setReaction(postId: postId, emoji: emoji, userId: userId);

  /// コメント数を更新
  Future<void> updateCommentCount(String postId, int commentCount) =>
      _writeService.updateCommentCount(postId, commentCount);

  /// アナリティクスイベントを記録
  Future<void> trackAnalyticsEvent({required String uid, required String type}) =>
      _writeService.trackAnalyticsEvent(uid: uid, type: type);

  // ─── Check ───────────────────────────────────────

  /// 特定ユーザーが指定した日に投稿しているかチェック
  Future<bool> hasUserPostedOnDate(String userId, DateTime date) =>
      _checkService.hasUserPostedOnDate(userId, date);

  /// 特定ユーザーが今日投稿しているかチェック
  Future<bool> hasUserPostedToday(String userId) =>
      _checkService.hasUserPostedToday(userId);

  /// 現サイクルで期限内投稿済みか（他人の裏側閲覧＋リアクション許可の判定）
  Future<bool> hasOnTimePostInCurrentCycle(String userId) =>
      _checkService.hasOnTimePostInCurrentCycle(userId);

  /// 現サイクルで既に投稿しているか（投稿フローの初回/次回以降 判定）
  Future<bool> hasAnyPostInCurrentCycle(String userId) =>
      _checkService.hasAnyPostInCurrentCycle(userId);

  /// 特定ユーザーが今週末（金〜日）に投稿しているかチェック（Campus Vibe用）
  Future<bool> hasUserPostedInCurrentWeekend(String userId) =>
      _checkService.hasUserPostedInCurrentWeekend(userId);

  /// 特定ユーザーの今日の投稿を取得
  Future<List<PostModel>> getTodaysPosts(String userId) =>
      _checkService.getTodaysPosts(userId);

  /// 特定ユーザーの今日以外の投稿を取得
  Future<List<PostModel>> getPostsExcludingToday(String userId, {int limit = 20}) =>
      _checkService.getPostsExcludingToday(userId, limit: limit);

  // ─── Streams (kept in PostService) ───────────────

  /// 投稿のリアルタイムストリームを取得
  Stream<List<PostModel>> getPostsStream({int limit = 20}) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));

    return _firestore
        .collection(_postsCollection)
        .where('createdAt', isGreaterThan: Timestamp.fromDate(cutoff))
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .asyncMap((snapshot) async {
      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
      return await _fetchService.applyLatestUserInfo(posts);
    });
  }

  /// 特定のユーザーの投稿を取得（Stream版）
  Stream<List<PostModel>> getUserPostsStream(String userId, {int limit = 20}) {
    return _firestore
        .collection(_postsCollection)
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
    });
  }

  /// 投稿のストリームを取得
  Stream<PostModel?> getPostStream(String postId) {
    return _firestore
        .collection(_postsCollection)
        .doc(postId)
        .snapshots()
        .map((doc) {
      if (doc.exists) {
        return PostModel.fromFirestore(doc);
      }
      return null;
    });
  }

  // ─── Vibe ─────────────────────────────────────────

  /// 特定のお題のVibe投稿を取得
  Future<List<PostModel>> getVibePostsByTopic(
    String topicId,
    DateTime date,
  ) async {
    try {
      final normalizedDate = DateTime(date.year, date.month, date.day);
      final nextDay = normalizedDate.add(const Duration(days: 1));

      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('isVibe', isEqualTo: true)
          .where('vibeTopicId', isEqualTo: topicId)
          .where('vibeDate', isGreaterThanOrEqualTo: Timestamp.fromDate(normalizedDate))
          .where('vibeDate', isLessThan: Timestamp.fromDate(nextDay))
          .get();

      // Vibe プレイリストには「鍵投稿（フォロワー限定）」は流さない仕様。
      // ただし ADL/Vibe の集計値（postCount）には鍵投稿も含めるため、
      // ここで表示用にだけフィルタする（書き込み側は変更しない）。
      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .where((p) => p.audience == PostAudience.public)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return await _fetchService.applyLatestUserInfo(posts);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting vibe posts by topic: $e');
      }
      return [];
    }
  }

  /// ランキング計算（投稿数でグループ化＆ソート）
  Future<List<VibeRankingItem>> calculateVibeRanking(
    String topicId,
    DateTime date, {
    int limit = 10,
  }) async {
    try {
      final vibePosts = await getVibePostsByTopic(topicId, date);

      if (vibePosts.isEmpty) {
        return [];
      }

      final Map<String, List<PostModel>> groupedPosts = {};

      for (final post in vibePosts) {
        final trackKey = post.track.trackId.isNotEmpty
            ? post.track.trackId
            : '${post.track.trackName}_${post.track.artistName}';

        if (!groupedPosts.containsKey(trackKey)) {
          groupedPosts[trackKey] = [];
        }
        groupedPosts[trackKey]!.add(post);
      }

      final List<Map<String, dynamic>> rankingData = [];

      for (final entry in groupedPosts.entries) {
        final posts = entry.value;
        final postCount = posts.length;
        final userIds = posts.map((p) => p.userId).toList();
        final userIconUrls = posts
            .map((p) => p.userIconUrl ?? '')
            .where((url) => url.isNotEmpty)
            .toList();
        final usernames = posts
            .map((p) => p.username)
            .where((name) => name.isNotEmpty)
            .toList();
        final representativeTrack = posts.first.track;

        rankingData.add({
          'track': representativeTrack,
          'postCount': postCount,
          'userIds': userIds,
          'userIconUrls': userIconUrls,
          'usernames': usernames,
        });
      }

      rankingData.sort((a, b) => (b['postCount'] as int).compareTo(a['postCount'] as int));

      final List<VibeRankingItem> ranking = [];
      for (int i = 0; i < rankingData.length && i < limit; i++) {
        final data = rankingData[i];
        ranking.add(VibeRankingItem(
          rank: i + 1,
          track: data['track'] as TrackModel,
          postCount: data['postCount'] as int,
          userIds: List<String>.from(data['userIds']),
          userIconUrls: List<String>.from(data['userIconUrls']),
          usernames: List<String>.from(data['usernames']),
        ));
      }

      return ranking;
    } catch (e) {
      if (kDebugMode) {
        print('Error calculating vibe ranking: $e');
      }
      return [];
    }
  }

  // ─── Campus Vibe ─────────────────────────────────

  /// Campus Vibe投稿一覧を取得（今週末・大学一致・参加フラグtrue）
  /// スケーラビリティ対策: 週末範囲・参加フラグ・大学を Firestore 側で絞り込み + limit
  Future<List<PostModel>> getCampusVibePosts(String university) async {
    try {
      final range = CampusVibeUtils.weekendRange();
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('university', isEqualTo: university)
          .where('campusVibeParticipating', isEqualTo: true)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(range.end))
          .orderBy('createdAt', descending: true)
          .limit(300)
          .get();

      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
      return posts;
    } catch (e) {
      if (kDebugMode) print('getCampusVibePosts error: $e');
      return [];
    }
  }

  /// 今週末より古い Campus Vibe 投稿を非表示化（campusVibeParticipating: false）
  /// 画面オープン時にバックグラウンドで呼び出す
  Future<void> archiveOldCampusVibePosts(String university) async {
    try {
      final weekendStart = CampusVibeUtils.weekendRange().start;
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('university', isEqualTo: university)
          .where('campusVibeParticipating', isEqualTo: true)
          .where('createdAt', isLessThan: Timestamp.fromDate(weekendStart))
          .limit(50)
          .get();

      if (snapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'campusVibeParticipating': false});
      }
      await batch.commit();
      if (kDebugMode) {
        print('🗂 Campus Vibe 旧投稿アーカイブ: ${snapshot.docs.length}件');
      }
    } catch (e) {
      if (kDebugMode) print('archiveOldCampusVibePosts error: $e');
    }
  }

  // ─── 過去履歴 ─────────────────────────────────────

  /// 過去のVibeお題一覧を取得（topicTitle + date のユニーク一覧、新しい順、0件除外）
  /// スケーラビリティ対策: 直近30日 / 最大1000件に制限（300〜600 active users 想定）
  Future<List<({String topicTitle, String topicId, DateTime date, int count})>> getPastVibeTopics() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('isVibe', isEqualTo: true)
          .where('vibeDate', isGreaterThan: Timestamp.fromDate(cutoff))
          .orderBy('vibeDate', descending: true)
          .limit(1000)
          .get();

      final groups = <String, ({String topicTitle, String topicId, DateTime date, int count})>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final title = data['vibeTopicTitle'] as String?;
        if (title == null || title.isEmpty) continue;
        final topicId = (data['vibeTopicId'] as String?) ?? '';
        final ts = data['vibeDate'] ?? data['createdAt'];
        final date = ts is Timestamp ? ts.toDate() : DateTime.now();
        final normalized = DateTime(date.year, date.month, date.day);
        final key = '${topicId}_${normalized.millisecondsSinceEpoch}';
        if (!groups.containsKey(key)) {
          groups[key] = (topicTitle: title, topicId: topicId, date: normalized, count: 1);
        } else {
          final e = groups[key]!;
          groups[key] = (topicTitle: e.topicTitle, topicId: e.topicId, date: e.date, count: e.count + 1);
        }
      }

      final today = DateTime.now();
      final yesterdayNormalized = DateTime(today.year, today.month, today.day - 1);

      final result = groups.values
          .where((e) => e.date.isBefore(yesterdayNormalized))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return result;
    } catch (e) {
      if (kDebugMode) print('getPastVibeTopics error: $e');
      return [];
    }
  }

  /// 指定した日付範囲のVibe投稿をトピック単位で集計（件数制限なし）
  Future<List<({String topicTitle, String topicId, DateTime date, int count})>>
      getVibeTopicsByDateRange(DateTime from, DateTime to) async {
    try {
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('isVibe', isEqualTo: true)
          .where('vibeDate', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('vibeDate', isLessThan: Timestamp.fromDate(to))
          .orderBy('vibeDate', descending: true)
          .get();

      final groups = <String, ({String topicTitle, String topicId, DateTime date, int count})>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final title = data['vibeTopicTitle'] as String?;
        if (title == null || title.isEmpty) continue;
        final topicId = (data['vibeTopicId'] as String?) ?? '';
        final ts = data['vibeDate'] ?? data['createdAt'];
        final date = ts is Timestamp ? ts.toDate() : DateTime.now();
        final normalized = DateTime(date.year, date.month, date.day);
        final key = '${topicId}_${normalized.millisecondsSinceEpoch}';
        if (!groups.containsKey(key)) {
          groups[key] = (topicTitle: title, topicId: topicId, date: normalized, count: 1);
        } else {
          final e = groups[key]!;
          groups[key] = (topicTitle: e.topicTitle, topicId: e.topicId, date: e.date, count: e.count + 1);
        }
      }

      return groups.values.toList()..sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      if (kDebugMode) print('getVibeTopicsByDateRange error: $e');
      return [];
    }
  }

  /// Vibeお題ごとのサムネイル付き集計を取得（検索画面のVibeセクション用）
  /// - topic+date 単位で集計、件数の多い順
  /// - 各 topic につき最大4枚のサムネイル（写真優先、不足時にアルバムアートで補完）
  Future<List<({
    String topicTitle,
    String topicId,
    DateTime date,
    int count,
    List<String> thumbnails,
  })>> getVibeTopicsWithThumbnails({int limit = 20, int minCount = 1, bool randomize = false}) async {
    try {
      // 直近60日 / 最大60件に制限（6題×サムネ4枚=24件が最小要件、余裕を持たせて60件）
      // 不足分は vibe_topics コレクションで補完するためこれ以上は不要
      final cutoff = DateTime.now().subtract(const Duration(days: 60));
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('isVibe', isEqualTo: true)
          .where('vibeDate', isGreaterThan: Timestamp.fromDate(cutoff))
          .orderBy('vibeDate', descending: true)
          .limit(60)
          .get();

      final groups = <String, ({
        String topicTitle,
        String topicId,
        DateTime date,
        int count,
        List<String> photos,
        List<String> jackets,
      })>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final title = data['vibeTopicTitle'] as String?;
        if (title == null || title.isEmpty) continue;
        final topicId = (data['vibeTopicId'] as String?) ?? '';
        final ts = data['vibeDate'] ?? data['createdAt'];
        final date = ts is Timestamp ? ts.toDate() : DateTime.now();
        final normalized = DateTime(date.year, date.month, date.day);
        final key = '${topicId}_${normalized.millisecondsSinceEpoch}';

        final photo = data['photoUrl']?.toString();
        final track = data['track'] as Map<String, dynamic>?;
        final jacket = track?['albumImageUrl']?.toString();

        final existing = groups[key];
        if (existing == null) {
          groups[key] = (
            topicTitle: title,
            topicId: topicId,
            date: normalized,
            count: 1,
            photos: [
              if (photo != null && photo.startsWith('http')) photo,
            ],
            jackets: [
              if (jacket != null && jacket.startsWith('http')) jacket,
            ],
          );
        } else {
          final newPhotos = List<String>.of(existing.photos);
          final newJackets = List<String>.of(existing.jackets);
          if (photo != null && photo.startsWith('http') && newPhotos.length < 4) {
            newPhotos.add(photo);
          }
          if (jacket != null &&
              jacket.startsWith('http') &&
              newJackets.length < 4 &&
              !newJackets.contains(jacket)) {
            newJackets.add(jacket);
          }
          groups[key] = (
            topicTitle: existing.topicTitle,
            topicId: existing.topicId,
            date: existing.date,
            count: existing.count + 1,
            photos: newPhotos,
            jackets: newJackets,
          );
        }
      }

      final result = groups.values
          .where((g) => g.count >= minCount)
          .map((g) {
        final picked = <String>['', '', '', ''];
        final usedPhotos = <String>{};
        for (var i = 0; i < 2 && i < g.photos.length; i++) {
          picked[i] = g.photos[i];
          usedPhotos.add(g.photos[i]);
        }
        final jacketsAvailable = g.jackets.toList();
        final extraPhotos =
            g.photos.where((p) => !usedPhotos.contains(p)).toList();
        for (var slot = 2; slot < 4; slot++) {
          if (jacketsAvailable.isNotEmpty) {
            picked[slot] = jacketsAvailable.removeAt(0);
          } else if (extraPhotos.isNotEmpty) {
            picked[slot] = extraPhotos.removeAt(0);
          }
        }
        return (
          topicTitle: g.topicTitle,
          topicId: g.topicId,
          date: g.date,
          count: g.count,
          thumbnails: picked,
        );
      }).toList();

      if (randomize) {
        result.shuffle();
      } else {
        result.sort((a, b) => b.count.compareTo(a.count));
      }

      final trimmed = result.length > limit ? result.sublist(0, limit) : result;

      // 件数が limit に満たない場合、vibe_topics コレクションから補完
      if (trimmed.length < limit) {
        final existingTopicIds = trimmed.map((r) => r.topicId).toSet();
        try {
          final topicsSnap = await _firestore
              .collection('vibe_topics')
              .orderBy('date', descending: true)
              .limit(limit * 3) // 候補を多めに取って重複除去
              .get();

          final extras = <({
            String topicTitle,
            String topicId,
            DateTime date,
            int count,
            List<String> thumbnails,
          })>[];

          for (final doc in topicsSnap.docs) {
            if (trimmed.length + extras.length >= limit) break;
            final data = doc.data();
            final title = (data['title'] as String?) ?? '';
            if (title.isEmpty) continue;
            if (existingTopicIds.contains(doc.id)) continue;
            extras.add((
              topicTitle: title,
              topicId: doc.id,
              date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
              // Cloud Function (vibeTopicPostAggregation) が集計した postCount を使う。
              // 過去60日の posts クエリに乗らなかった古いお題でも実数が表示される。
              count: (data['postCount'] as num?)?.toInt() ?? 0,
              thumbnails: ['', '', '', ''],
            ));
            existingTopicIds.add(doc.id);
          }
          return [...trimmed, ...extras];
        } catch (_) {}
      }

      return trimmed;
    } catch (e) {
      if (kDebugMode) print('getVibeTopicsWithThumbnails error: $e');
      return [];
    }
  }

  /// 特定のVibeお題・日付の全投稿を取得
  Future<List<PostModel>> getVibePostsByTopicAndDate(String topicId, DateTime date) async {
    try {
      final normalized = DateTime(date.year, date.month, date.day);
      final nextDay = normalized.add(const Duration(days: 1));
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('isVibe', isEqualTo: true)
          .where('vibeTopicId', isEqualTo: topicId)
          .where('vibeDate', isGreaterThanOrEqualTo: Timestamp.fromDate(normalized))
          .where('vibeDate', isLessThan: Timestamp.fromDate(nextDay))
          .get();
      // Vibe プレイリスト系には鍵投稿を流さない（[getVibePostsByTopic] と同じ方針）。
      final posts = snapshot.docs
          .map((d) => PostModel.fromFirestore(d))
          .where((p) => p.audience == PostAudience.public)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return posts;
    } catch (e) {
      if (kDebugMode) print('getVibePostsByTopicAndDate error: $e');
      return [];
    }
  }

  /// 過去のCampusVibe一覧を取得（university + 週開始日のユニーク一覧、新しい順、0件除外）
  Future<List<({String university, DateTime weekStart, int count})>> getPastCampusVibeEntries() async {
    try {
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('university', isGreaterThan: '')
          .get();

      final groups = <String, ({String university, DateTime weekStart, int count})>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        // campusVibePost: true のもの（参加選択した投稿）のみ集計
        if (data['campusVibePost'] != true) continue;
        final university = data['university'] as String?;
        if (university == null || university.isEmpty) continue;
        final ts = data['createdAt'];
        final date = ts is Timestamp ? ts.toDate() : DateTime.now();
        // 週の土曜日を基準に（Campus Vibeは週末開催）
        final range = CampusVibeUtils.weekendRangeFor(date);
        final weekStart = range.start;
        final key = '${university}_${weekStart.millisecondsSinceEpoch}';
        if (!groups.containsKey(key)) {
          groups[key] = (university: university, weekStart: weekStart, count: 1);
        } else {
          final e = groups[key]!;
          groups[key] = (university: e.university, weekStart: e.weekStart, count: e.count + 1);
        }
      }

      final result = groups.values.toList()
        ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
      return result;
    } catch (e) {
      if (kDebugMode) print('getPastCampusVibeEntries error: $e');
      return [];
    }
  }

  /// 特定の週・大学のCampusVibe投稿を取得
  Future<List<PostModel>> getCampusVibePostsByWeekAndUniversity(DateTime weekStart, String university) async {
    try {
      final range = CampusVibeUtils.weekendRangeFor(weekStart);
      // 複合インデックス不要のため university のみで絞り込み、日付はクライアント側でフィルタリング
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('university', isEqualTo: university)
          .get();
      final posts = snapshot.docs
          .map((d) => PostModel.fromFirestore(d))
          .where((p) =>
              p.campusVibePost &&
              !p.createdAt.isBefore(range.start) &&
              !p.createdAt.isAfter(range.end))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return posts;
    } catch (e) {
      if (kDebugMode) print('getCampusVibePostsByWeekAndUniversity error: $e');
      return [];
    }
  }

  /// Vibeお題をキーワード検索（topicTitleの前方一致）
  Future<List<({String topicTitle, String topicId, DateTime date, int count})>> searchVibeTopics(String query) async {
    if (query.trim().isEmpty) return [];
    final all = await getPastVibeTopics();
    final lower = query.toLowerCase();
    return all.where((t) => t.topicTitle.toLowerCase().contains(lower)).toList();
  }

  /// Campus Vibe投稿件数を取得（集計クエリ）
  ///
  /// Firestore コスト最適化のため、count() aggregation を使用。
  /// 全件スナップショットを流す代わりに、サーバー側で集計した値だけを取得する。
  /// 課金は最大でも結果件数1000あたり1read。
  Future<int> getCampusVibePostCount(String university) async {
    final range = CampusVibeUtils.weekendRange();
    try {
      final snap = await _firestore
          .collection(_postsCollection)
          .where('university', isEqualTo: university)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
          .where('createdAt',
              isLessThanOrEqualTo: Timestamp.fromDate(range.end))
          .count()
          .get();
      return snap.count ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
