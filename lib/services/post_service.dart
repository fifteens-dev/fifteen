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

  /// ユーザーの投稿をカーソルページネーション付きで取得
  Future<({List<PostModel> posts, DocumentSnapshot? lastDoc, bool hasMore})>
      getPostsByUserIdPaged(
    String userId, {
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) => _fetchService.getPostsWithPagination(userId, limit: limit, startAfter: startAfter);

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
    String? vibeTopicId,
    String? vibeTopicTitle,
    String? emotionTag,
    PostTheme? theme,
    String? lyricsText,
    int audioStartMs = 0,
    int audioDurationSec = 15,
    String? university,
    bool campusVibeParticipating = true,
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
    vibeTopicId: vibeTopicId,
    vibeTopicTitle: vibeTopicTitle,
    emotionTag: emotionTag,
    theme: theme,
    lyricsText: lyricsText,
    audioStartMs: audioStartMs,
    audioDurationSec: audioDurationSec,
    university: university,
    campusVibeParticipating: campusVibeParticipating,
  );

  /// 投稿を削除
  Future<void> deletePost(String postId) => _writeService.deletePost(postId);

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

      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
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
        final representativeTrack = posts.first.track;

        rankingData.add({
          'track': representativeTrack,
          'postCount': postCount,
          'userIds': userIds,
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
  Future<List<PostModel>> getCampusVibePosts(String university) async {
    try {
      final range = CampusVibeUtils.weekendRange();
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('university', isEqualTo: university)
          .get();

      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .where((p) =>
              p.campusVibeParticipating &&
              !p.createdAt.isBefore(range.start) &&
              !p.createdAt.isAfter(range.end))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
  Future<List<({String topicTitle, String topicId, DateTime date, int count})>> getPastVibeTopics() async {
    try {
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('isVibe', isEqualTo: true)
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
      final posts = snapshot.docs.map((d) => PostModel.fromFirestore(d)).toList()
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

  /// Campus Vibe投稿件数をリアルタイムで流すStream
  Stream<int> streamCampusVibePostCount(String university) {
    final range = CampusVibeUtils.weekendRange();
    return _firestore
        .collection(_postsCollection)
        .where('university', isEqualTo: university)
        .snapshots()
        .map((snap) => snap.docs.where((doc) {
              final data = doc.data();
              if ((data['campusVibeParticipating'] as bool?) == false) {
                return false;
              }
              final ts = data['createdAt'];
              if (ts is! Timestamp) return false;
              final date = ts.toDate();
              return !date.isBefore(range.start) && !date.isAfter(range.end);
            }).length);
  }
}
