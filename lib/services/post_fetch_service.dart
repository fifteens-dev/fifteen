import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/post_model.dart';
import 'music_memory_cycle_service.dart';

/// 投稿データの取得を担当するサービス
class PostFetchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _postsCollection = 'posts';

  // ユーザー情報のインメモリキャッシュ（TTL: 30分）
  // PostService の static キャッシュを共有するため、外部から渡すか同じ参照を持つ
  static final Map<String, ({String? username, String? iconUrl, DateTime fetchedAt})> _userInfoCache = {};
  static const Duration _userCacheTtl = Duration(minutes: 30);

  /// 投稿リストのユーザー名・アイコンを最新のプロフィール情報で更新
  /// スケーラビリティ対策: 個別 getUser ではなく `whereIn` で 10件単位バッチ取得し
  /// N+1 パターンを解消。1回のホーム取得で 50〜200 reads → 5〜20 reads に削減。
  Future<List<PostModel>> applyLatestUserInfo(List<PostModel> posts) async {
    if (posts.isEmpty) return posts;

    // 投稿者 + いいねユーザー全員のIDを収集
    final allUserIds = <String>{};
    for (final post in posts) {
      allUserIds.add(post.userId);
      allUserIds.addAll(post.likedUserIds);
    }

    final userMap = <String, ({String? username, String? iconUrl})>{};
    final now = DateTime.now();
    final missing = <String>[];

    // ① キャッシュからまず充足
    for (final uid in allUserIds) {
      final cached = _userInfoCache[uid];
      if (cached != null && now.difference(cached.fetchedAt) < _userCacheTtl) {
        userMap[uid] = (username: cached.username, iconUrl: cached.iconUrl);
      } else {
        missing.add(uid);
      }
    }

    // ② 未取得分を whereIn で 10件単位にバッチ取得
    if (missing.isNotEmpty) {
      const chunkSize = 10; // Firestore whereIn の上限
      for (var i = 0; i < missing.length; i += chunkSize) {
        final chunk = missing.sublist(
            i, i + chunkSize > missing.length ? missing.length : i + chunkSize);
        try {
          final snapshot = await _firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final uid = doc.id;
            final username = data['username'] as String?;
            final iconUrl = data['profileImageUrl'] as String?;
            _userInfoCache[uid] = (
              username: username,
              iconUrl: iconUrl,
              fetchedAt: DateTime.now(),
            );
            userMap[uid] = (username: username, iconUrl: iconUrl);
          }
        } catch (e) {
          if (kDebugMode) print('applyLatestUserInfo whereIn batch error: $e');
        }
      }
    }

    return posts.map((post) {
      final userInfo = userMap[post.userId];

      // いいねユーザーのアイコンURLを最新に更新
      final updatedLikedByIconUrls = post.likedUserIds.map((uid) {
        final info = userMap[uid];
        return info?.iconUrl ?? '';
      }).toList();

      return post.copyWith(
        username: userInfo?.username ?? post.username,
        userIconUrl: userInfo?.iconUrl ?? post.userIconUrl,
        likedByUserIconUrls: updatedLikedByIconUrls,
      );
    }).toList();
  }

  /// 投稿を取得（ページネーション付き、24時間以内のみ）
  Future<List<PostModel>> getPosts({
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));

      Query query = _firestore
          .collection(_postsCollection)
          .where('createdAt', isGreaterThan: Timestamp.fromDate(cutoff))
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      // Vibe 投稿（isVibe==true）はストーリーバー専用のため、
      // ホームタイムラインの投稿カードには載せない。
      final posts = snapshot.docs
          .where((doc) {
            final data = doc.data() as Map<String, dynamic>?;
            return data?['isVibe'] != true;
          })
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();

      return await applyLatestUserInfo(posts);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting posts: $e');
      }
      return [];
    }
  }

  /// フォロー中のユーザーの投稿を取得（Firestore whereIn のバッチ処理）
  /// ダミーユーザー投稿・Vibe 投稿（ストーリー）はタイムラインには出さない。
  ///
  /// 表示範囲は Music Memory の投稿サイクル制。直近の通知時刻（notifiedAt）以降の
  /// 投稿のみを出し、次の通知が来ると前サイクル分は自然に外れる。
  Future<List<PostModel>> getPostsForFollowing(List<String> userIds, {int limit = 50}) async {
    if (userIds.isEmpty) return [];

    try {
      final cutoff = MusicMemoryCycleService().currentCycleStart;
      final allPosts = <PostModel>[];
      final seenIds = <String>{};

      // Firestore whereIn は最大30件制限のためバッチ処理
      for (int i = 0; i < userIds.length; i += 30) {
        final batch = userIds.skip(i).take(30).toList();
        final snapshot = await _firestore
            .collection(_postsCollection)
            .where('userId', whereIn: batch)
            .where('createdAt', isGreaterThan: Timestamp.fromDate(cutoff))
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .get();

        for (final doc in snapshot.docs) {
          if (seenIds.add(doc.id)) {
            final data = doc.data();
            // ダミー投稿はタイムラインに出さない（Vibeでは表示）
            if (data['isDummyPost'] == true) continue;
            // Vibe 投稿（ストーリー）は投稿カードとして載せない
            if (data['isVibe'] == true) continue;
            allPosts.add(PostModel.fromFirestore(doc));
          }
        }
      }

      allPosts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final limited = allPosts.take(limit).toList();
      return await applyLatestUserInfo(limited);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting posts for following: $e');
      }
      return [];
    }
  }

  /// Vibe ストーリーバー用: 過去 24 時間の投稿をユーザー別にグループ化して返す。
  ///
  /// - 入力 [userIds] には「自分のフォロー先 + 自分」を渡す想定（自分の投稿は
  ///   ストーリーバー先頭の Vibe 円で別表示するため、呼び出し元で除外してもよい）
  /// - audience=followers の投稿は [viewerFollowsAuthor] が true でないと弾く
  /// - ダミー投稿（isDummyPost=true）は表示対象外
  /// - 結果は「ユーザーごとの最新 createdAt の降順」で並ぶ
  ///
  /// 返り値: 各 entry は1ユーザー分の `List<PostModel>`（そのユーザーの 24h 投稿、新しい順）
  Future<List<List<PostModel>>> getRecentPostsGroupedByUser({
    required List<String> userIds,
    required bool Function(String authorUid) viewerFollowsAuthor,
  }) async {
    if (userIds.isEmpty) return [];
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      final byUser = <String, List<PostModel>>{};

      for (int i = 0; i < userIds.length; i += 30) {
        final batch = userIds.skip(i).take(30).toList();
        final snapshot = await _firestore
            .collection(_postsCollection)
            .where('userId', whereIn: batch)
            .where('createdAt', isGreaterThan: Timestamp.fromDate(cutoff))
            .orderBy('createdAt', descending: true)
            .get();

        for (final doc in snapshot.docs) {
          final data = doc.data();
          if (data['isDummyPost'] == true) continue;
          // 「気分で投稿」フラグが立った投稿はストーリーには載せない。
          if (data['isMoodPost'] == true) continue;
          final post = PostModel.fromFirestore(doc);
          // audience=followers なら閲覧権限を確認（自分の投稿は常に可視）
          if (post.audience == PostAudience.followers &&
              !viewerFollowsAuthor(post.userId)) {
            continue;
          }
          (byUser[post.userId] ??= []).add(post);
        }
      }

      // 各ユーザーの投稿リスト内も念のため新しい順にソート
      for (final list in byUser.values) {
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }

      // ユーザーリストを「最新投稿の createdAt 降順」で並べる
      final entries = byUser.entries.toList()
        ..sort((a, b) =>
            b.value.first.createdAt.compareTo(a.value.first.createdAt));

      // 投稿者ユーザー情報を最新化（アイコン・ユーザー名を流用するため）
      final flat = entries.expand((e) => e.value).toList();
      final updated = await applyLatestUserInfo(flat);
      // updated の順序は flat と同じ（applyLatestUserInfo は順序保持）
      int cursor = 0;
      final result = <List<PostModel>>[];
      for (final e in entries) {
        final n = e.value.length;
        result.add(updated.sublist(cursor, cursor + n));
        cursor += n;
      }
      return result;
    } catch (e) {
      if (kDebugMode) {
        print('Error getRecentPostsGroupedByUser: $e');
      }
      return [];
    }
  }

  /// 特定のユーザーの投稿を取得（Future版）
  Future<List<PostModel>> getPostsByUserId(String userId, {int limit = 20}) async {
    try {
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
      return await applyLatestUserInfo(posts);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting posts by userId: $e');
      }
      return [];
    }
  }

  /// ユーザーの投稿を [start]（含む）〜[end]（含まない）の createdAt 範囲で取得。
  /// Music Memory の月表示を 3ヶ月区切りで遅延ロードするために使う。
  Future<List<PostModel>> getUserPostsInRange(
    String userId,
    DateTime start,
    DateTime end,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('userId', isEqualTo: userId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('createdAt', isLessThan: Timestamp.fromDate(end))
          .orderBy('createdAt', descending: true)
          .get();

      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
      return await applyLatestUserInfo(posts);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting user posts in range: $e');
      }
      return [];
    }
  }

  /// ユーザーの投稿をカーソルページネーション付きで取得
  Future<({List<PostModel> posts, DocumentSnapshot? lastDoc, bool hasMore})>
      getPostsWithPagination(
    String userId, {
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      var query = _firestore
          .collection(_postsCollection)
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();

      return (
        posts: await applyLatestUserInfo(posts),
        lastDoc: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        hasMore: snapshot.docs.length == limit,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error getting posts with pagination: $e');
      }
      return (posts: <PostModel>[], lastDoc: null, hasMore: false);
    }
  }

  /// 特定のユーザーが保存した投稿を取得
  Future<List<PostModel>> getPostsSavedByUser(String userId, {int limit = 50}) async {
    try {
      // ユーザー文書から savedPosts リストを取得
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return [];

      final savedPostIds = List<String>.from(
        (userDoc.data()?['savedPosts'] as List<dynamic>? ?? []).whereType<String>(),
      );
      if (savedPostIds.isEmpty) return [];

      // 直近 limit 件に絞る（新しい順 = リスト末尾が新しいと仮定しリバース）
      final ids = savedPostIds.reversed.take(limit).toList();

      // 30件単位の whereIn バッチで取得
      const chunkSize = 30;
      final List<PostModel> posts = [];
      for (var i = 0; i < ids.length; i += chunkSize) {
        final chunk = ids.sublist(i, (i + chunkSize).clamp(0, ids.length));
        final snap = await _firestore
            .collection(_postsCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        posts.addAll(snap.docs.map((doc) => PostModel.fromFirestore(doc)));
      }

      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return await applyLatestUserInfo(posts);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting saved posts by userId: $e');
      }
      return [];
    }
  }

  /// 特定の投稿を取得
  Future<PostModel?> getPost(String postId) async {
    try {
      final doc = await _firestore.collection(_postsCollection).doc(postId).get();

      if (doc.exists) {
        return PostModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting post: $e');
      }
      return null;
    }
  }

  /// 指定 trackId の投稿をカーソルページネーション付きで取得
  Future<({List<PostModel> posts, DocumentSnapshot? lastDoc, bool hasMore})>
      getPostsByTrackIdPaged(
    String trackId, {
    int limit = 12,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      var query = _firestore
          .collection(_postsCollection)
          .where('track.trackId', isEqualTo: trackId)
          .orderBy('createdAt', descending: true)
          .limit(limit);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      final snapshot = await query.get();
      final posts =
          snapshot.docs.map((doc) => PostModel.fromFirestore(doc)).toList();
      return (
        posts: await applyLatestUserInfo(posts),
        lastDoc: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        hasMore: snapshot.docs.length == limit,
      );
    } catch (e) {
      if (kDebugMode) print('getPostsByTrackIdPaged error: $e');
      return (posts: <PostModel>[], lastDoc: null, hasMore: false);
    }
  }
}
