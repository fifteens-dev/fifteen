import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/post_model.dart';
import '../models/track_model.dart';
import '../models/post_theme.dart';
import '../models/comment_model.dart';

/// テスト用のダミー投稿データを生成するユーティリティ
class TestData {
  static const String _localCommentsKey = 'local_comments';
  static const String _localLikesKey = 'local_likes';
  static const String _localSavedPostsKey = 'local_saved_posts';

  // ローカルコメントを保持する静的マップ（メモリキャッシュ）
  static final Map<String, List<CommentModel>> _localComments = {};
  static bool _isLoaded = false;

  // ローカルいいね状態を保持する静的マップ（メモリキャッシュ）
  // Map<postId, Map<'likeCount': int, 'likedUserIds': List<String>>>
  static final Map<String, Map<String, dynamic>> _localLikes = {};
  static bool _isLikesLoaded = false;

  // ローカル保存投稿を保持する静的マップ（メモリキャッシュ）
  // Map<userId, List<postId>>
  static final Map<String, List<String>> _localSavedPosts = {};
  static bool _isSavedPostsLoaded = false;

  /// SharedPreferencesからローカルコメントを読み込み
  static Future<void> _loadLocalComments() async {
    if (_isLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_localCommentsKey);

      if (jsonString != null) {
        final Map<String, dynamic> data = json.decode(jsonString);

        _localComments.clear();
        data.forEach((postId, commentsJson) {
          final List<dynamic> commentsList = commentsJson as List;
          _localComments[postId] = commentsList.map((commentMap) {
            return CommentModel(
              commentId: commentMap['commentId'],
              postId: commentMap['postId'],
              userId: commentMap['userId'],
              username: commentMap['username'],
              userIconUrl: commentMap['userIconUrl'],
              content: commentMap['content'],
              createdAt: DateTime.parse(commentMap['createdAt']),
              updatedAt: DateTime.parse(commentMap['updatedAt']),
            );
          }).toList();
        });
      }

      _isLoaded = true;
    } catch (e) {
      print('ローカルコメントの読み込みに失敗: $e');
      _localComments.clear();
      _isLoaded = true;
    }
  }

  /// SharedPreferencesにローカルコメントを保存
  static Future<void> _saveLocalComments() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final Map<String, dynamic> data = {};
      _localComments.forEach((postId, comments) {
        data[postId] = comments.map((comment) {
          return {
            'commentId': comment.commentId,
            'postId': comment.postId,
            'userId': comment.userId,
            'username': comment.username,
            'userIconUrl': comment.userIconUrl,
            'content': comment.content,
            'createdAt': comment.createdAt.toIso8601String(),
            'updatedAt': comment.updatedAt.toIso8601String(),
          };
        }).toList();
      });

      await prefs.setString(_localCommentsKey, json.encode(data));
    } catch (e) {
      print('ローカルコメントの保存に失敗: $e');
    }
  }

  /// ローカルコメントを追加
  static Future<void> addLocalComment(
      String postId, CommentModel comment) async {
    await _loadLocalComments();

    if (!_localComments.containsKey(postId)) {
      _localComments[postId] = [];
    }
    _localComments[postId]!.add(comment);

    await _saveLocalComments();
  }

  /// ローカルコメントを取得
  static Future<List<CommentModel>> getLocalComments(String postId) async {
    await _loadLocalComments();
    return _localComments[postId] ?? [];
  }

  /// ローカルコメントを削除
  static Future<void> removeLocalComment(
      String postId, String commentId) async {
    await _loadLocalComments();

    if (_localComments.containsKey(postId)) {
      _localComments[postId]!
          .removeWhere((comment) => comment.commentId == commentId);
      await _saveLocalComments();
    }
  }

  /// ローカルコメントをクリア（テスト用）
  static Future<void> clearLocalComments(String postId) async {
    await _loadLocalComments();
    _localComments.remove(postId);
    await _saveLocalComments();
  }

  /// 全てのローカルコメントをクリア（テスト用）
  static Future<void> clearAllLocalComments() async {
    _localComments.clear();
    _isLoaded = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localCommentsKey);
    } catch (e) {
      print('ローカルコメントのクリアに失敗: $e');
    }
  }

  /// SharedPreferencesからローカルいいね状態を読み込み
  static Future<void> _loadLocalLikes() async {
    if (_isLikesLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_localLikesKey);

      if (jsonString != null) {
        final Map<String, dynamic> data = json.decode(jsonString);

        _localLikes.clear();
        data.forEach((postId, likeData) {
          _localLikes[postId] = {
            'likeCount': likeData['likeCount'] as int,
            'likedUserIds': List<String>.from(likeData['likedUserIds'] as List),
          };
        });
      }

      _isLikesLoaded = true;
    } catch (e) {
      print('ローカルいいね状態の読み込みに失敗: $e');
      _localLikes.clear();
      _isLikesLoaded = true;
    }
  }

  /// SharedPreferencesにローカルいいね状態を保存
  static Future<void> _saveLocalLikes() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final Map<String, dynamic> data = {};
      _localLikes.forEach((postId, likeData) {
        data[postId] = {
          'likeCount': likeData['likeCount'],
          'likedUserIds': likeData['likedUserIds'],
        };
      });

      await prefs.setString(_localLikesKey, json.encode(data));
    } catch (e) {
      print('ローカルいいね状態の保存に失敗: $e');
    }
  }

  /// いいねをトグル（追加/削除）
  static Future<void> toggleLike(
      String postId, String userId, int originalLikeCount) async {
    await _loadLocalLikes();

    // 現在の状態を取得（初回の場合は元の投稿のいいね数を使用）
    final likeData = _localLikes[postId] ??
        {
          'likeCount': originalLikeCount,
          'likedUserIds': <String>[],
        };

    final likedUserIds = List<String>.from(likeData['likedUserIds']);
    int likeCount = likeData['likeCount'] as int;

    // いいね状態をトグル
    if (likedUserIds.contains(userId)) {
      // いいね解除
      likedUserIds.remove(userId);
      likeCount = (likeCount - 1).clamp(0, 999999);
    } else {
      // いいね追加
      likedUserIds.add(userId);
      likeCount++;
    }

    // 状態を更新
    _localLikes[postId] = {
      'likeCount': likeCount,
      'likedUserIds': likedUserIds,
    };

    await _saveLocalLikes();
  }

  /// いいね状態を取得
  static Future<Map<String, dynamic>> getLikeState(String postId) async {
    await _loadLocalLikes();

    return _localLikes[postId] ??
        {
          'likeCount': 0,
          'likedUserIds': <String>[],
        };
  }

  /// いいね数を取得
  static Future<int> getLikeCount(String postId) async {
    final likeState = await getLikeState(postId);
    return likeState['likeCount'] as int;
  }

  /// ユーザーがいいねしているか確認
  static Future<bool> isLikedByUser(String postId, String userId) async {
    final likeState = await getLikeState(postId);
    final likedUserIds = List<String>.from(likeState['likedUserIds']);
    return likedUserIds.contains(userId);
  }

  /// 全てのローカルいいね状態をクリア（テスト用）
  static Future<void> clearAllLocalLikes() async {
    _localLikes.clear();
    _isLikesLoaded = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localLikesKey);
    } catch (e) {
      print('ローカルいいね状態のクリアに失敗: $e');
    }
  }

  /// テスト用の投稿リストを生成
  static List<PostModel> generateTestPosts() {
    return [
      // 投稿カード1（青緑系グラデーション - いとしのエリー）
      PostModel(
        postId: 'test_post_1',
        userId: 'test_user_1',
        username: 'knyaita',
        userIconUrl: null,
        track: TrackModel(
          trackId: 'track_1',
          trackName: 'いとしのエリー',
          artistName: 'サザンオールスターズ',
          albumImageUrl: 'https://picsum.photos/seed/album1/400/400',
        ),
        likeCount: 3,
        commentCount: generateTestComments('test_post_1').length,
        likedUserIds: ['user_a', 'user_b', 'user_c'],
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
        theme: PostTheme.blueGreen,
      ),

      // 投稿カード2（紫系グラデーション - ヒロイン）
      PostModel(
        postId: 'test_post_2',
        userId: 'test_user_2',
        username: 'l0hx9',
        userIconUrl: null,
        track: TrackModel(
          trackId: 'track_2',
          trackName: 'ヒロイン',
          artistName: 'back number',
          albumImageUrl: 'https://picsum.photos/seed/album2/400/400',
        ),
        likeCount: 3,
        commentCount: generateTestComments('test_post_2').length,
        likedUserIds: ['user_d', 'user_e'],
        createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 5)),
        theme: PostTheme.purple,
      ),

      // 投稿カード3（ベージュ系グラデーション - 白い恋人達）
      PostModel(
        postId: 'test_post_3',
        userId: 'test_user_3',
        username: 'rockstar',
        userIconUrl: null,
        track: TrackModel(
          trackId: 'track_3',
          trackName: '白い恋人達',
          artistName: '桑田佳祐',
          albumImageUrl: 'https://picsum.photos/seed/album3/400/400',
        ),
        likeCount: 89,
        commentCount: generateTestComments('test_post_3').length,
        likedUserIds: [],
        createdAt: DateTime.now().subtract(const Duration(hours: 8)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 8)),
        theme: PostTheme.beige,
      ),

      // 投稿カード4（青緑系グラデーション - LAST PARTY）
      PostModel(
        postId: 'test_post_4',
        userId: 'test_user_4',
        username: 'popsinger',
        userIconUrl: null,
        track: TrackModel(
          trackId: 'track_4',
          trackName: 'LAST PARTY',
          artistName: 'BAD HOP',
          albumImageUrl: 'https://picsum.photos/seed/album4/400/400',
        ),
        likeCount: 256,
        commentCount: generateTestComments('test_post_4').length,
        likedUserIds: ['user_f', 'user_g', 'user_h'],
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
        theme: PostTheme.blueGreen,
      ),

      // 投稿カード5（紫系グラデーション - かわいいだけじゃダメですか？）
      PostModel(
        postId: 'test_post_5',
        userId: 'test_user_5',
        username: 'indie_artist',
        userIconUrl: null,
        track: TrackModel(
          trackId: 'track_5',
          trackName: 'かわいいだけじゃダメですか？',
          artistName: 'CUTIE STREET',
          albumImageUrl: 'https://picsum.photos/seed/album5/400/400',
        ),
        likeCount: 512,
        commentCount: generateTestComments('test_post_5').length,
        likedUserIds: ['user_i', 'user_j'],
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        updatedAt: DateTime.now().subtract(const Duration(days: 2)),
        theme: PostTheme.purple,
      ),

      // 投稿カード6（ベージュ系グラデーション - One more time, One more chance）
      PostModel(
        postId: 'test_post_6',
        userId: 'test_user_6',
        username: 'edm_producer',
        userIconUrl: null,
        track: TrackModel(
          trackId: 'track_6',
          trackName: 'One more time, One more chance',
          artistName: '山崎まさよし',
          albumImageUrl: 'https://picsum.photos/seed/album6/400/400',
        ),
        likeCount: 1024,
        commentCount: generateTestComments('test_post_6').length,
        likedUserIds: ['user_k'],
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        updatedAt: DateTime.now().subtract(const Duration(days: 3)),
        theme: PostTheme.beige,
      ),
    ];
  }

  /// テスト用のコメントリストを生成
  static List<CommentModel> generateTestComments(String postId) {
    // 各投稿に対応するコメントマップ
    final commentsMap = {
      'test_post_1': [
        CommentModel(
          commentId: 'comment_1_1',
          postId: postId,
          userId: 'user_a',
          username: 'musiclover',
          userIconUrl: null,
          content: 'サザンの名曲ですね！懐かしい〜',
          createdAt: DateTime.now().subtract(const Duration(hours: 1)),
          updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
        CommentModel(
          commentId: 'comment_1_2',
          postId: postId,
          userId: 'user_b',
          username: 'retro_fan',
          userIconUrl: null,
          content: 'ドライブにぴったりの曲！',
          createdAt: DateTime.now().subtract(const Duration(minutes: 45)),
          updatedAt: DateTime.now().subtract(const Duration(minutes: 45)),
        ),
        CommentModel(
          commentId: 'comment_1_3',
          postId: postId,
          userId: 'user_c',
          username: 'jpop_master',
          userIconUrl: null,
          content: 'エリーの切ない感じがたまらない',
          createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
          updatedAt: DateTime.now().subtract(const Duration(minutes: 30)),
        ),
      ],
      'test_post_2': [
        CommentModel(
          commentId: 'comment_2_1',
          postId: postId,
          userId: 'user_d',
          username: 'indie_lover',
          userIconUrl: null,
          content: 'back number最高！この曲大好き',
          createdAt: DateTime.now().subtract(const Duration(hours: 4)),
          updatedAt: DateTime.now().subtract(const Duration(hours: 4)),
        ),
        CommentModel(
          commentId: 'comment_2_2',
          postId: postId,
          userId: 'user_e',
          username: 'rock_girl',
          userIconUrl: null,
          content: '歌詞がめっちゃ刺さる〜',
          createdAt: DateTime.now().subtract(const Duration(hours: 3)),
          updatedAt: DateTime.now().subtract(const Duration(hours: 3)),
        ),
        CommentModel(
          commentId: 'comment_2_3',
          postId: postId,
          userId: 'user_f',
          username: 'ライブ行きたい',
          userIconUrl: null,
          content: 'ライブで聴いたら泣いちゃいそう',
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
          updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ],
      'test_post_3': [
        CommentModel(
          commentId: 'comment_3_1',
          postId: postId,
          userId: 'user_g',
          username: 'winter_lover',
          userIconUrl: null,
          content: '冬の定番曲！桑田さんの歌声最高',
          createdAt: DateTime.now().subtract(const Duration(hours: 7)),
          updatedAt: DateTime.now().subtract(const Duration(hours: 7)),
        ),
      ],
      'test_post_4': [
        CommentModel(
          commentId: 'comment_4_1',
          postId: postId,
          userId: 'user_h',
          username: 'hiphop_head',
          userIconUrl: null,
          content: 'BAD HOPのこの曲やばい！',
          createdAt: DateTime.now().subtract(const Duration(hours: 20)),
          updatedAt: DateTime.now().subtract(const Duration(hours: 20)),
        ),
        CommentModel(
          commentId: 'comment_4_2',
          postId: postId,
          userId: 'user_i',
          username: 'rap_fan',
          userIconUrl: null,
          content: 'パーティーで絶対盛り上がる',
          createdAt: DateTime.now().subtract(const Duration(hours: 18)),
          updatedAt: DateTime.now().subtract(const Duration(hours: 18)),
        ),
      ],
    };

    return commentsMap[postId] ?? [];
  }

  /// 投稿IDからコメント数を取得（ダミーコメント + ローカルコメント）
  static Future<int> getCommentCount(String postId) async {
    final dummyComments = generateTestComments(postId);
    final localComments = await getLocalComments(postId);
    return dummyComments.length + localComments.length;
  }

  /// SharedPreferencesからローカル保存投稿を読み込み
  static Future<void> _loadLocalSavedPosts() async {
    if (_isSavedPostsLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_localSavedPostsKey);

      if (jsonString != null) {
        final Map<String, dynamic> data = json.decode(jsonString);

        _localSavedPosts.clear();
        data.forEach((userId, postIds) {
          _localSavedPosts[userId] = List<String>.from(postIds as List);
        });
      }

      _isSavedPostsLoaded = true;
    } catch (e) {
      print('ローカル保存投稿の読み込みに失敗: $e');
      _localSavedPosts.clear();
      _isSavedPostsLoaded = true;
    }
  }

  /// SharedPreferencesにローカル保存投稿を保存
  static Future<void> _saveLocalSavedPosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final Map<String, dynamic> data = {};
      _localSavedPosts.forEach((userId, postIds) {
        data[userId] = postIds;
      });

      await prefs.setString(_localSavedPostsKey, json.encode(data));
    } catch (e) {
      print('ローカル保存投稿の保存に失敗: $e');
    }
  }

  /// 投稿の保存をトグル（追加/削除）
  static Future<void> toggleSavePost(String userId, String postId) async {
    await _loadLocalSavedPosts();

    // 現在の保存投稿リストを取得
    final savedPosts = _localSavedPosts[userId] ?? <String>[];

    // 保存状態をトグル
    if (savedPosts.contains(postId)) {
      // 保存解除
      savedPosts.remove(postId);
    } else {
      // 保存追加
      savedPosts.add(postId);
    }

    // 状態を更新
    if (savedPosts.isEmpty) {
      _localSavedPosts.remove(userId);
    } else {
      _localSavedPosts[userId] = savedPosts;
    }

    await _saveLocalSavedPosts();
  }

  /// ユーザーの保存済み投稿IDリストを取得
  static Future<List<String>> getSavedPosts(String userId) async {
    await _loadLocalSavedPosts();
    return _localSavedPosts[userId] ?? <String>[];
  }

  /// ユーザーが投稿を保存しているか確認
  static Future<bool> hasSavedPost(String userId, String postId) async {
    final savedPosts = await getSavedPosts(userId);
    return savedPosts.contains(postId);
  }

  /// 全てのローカル保存投稿をクリア（テスト用）
  static Future<void> clearAllLocalSavedPosts() async {
    _localSavedPosts.clear();
    _isSavedPostsLoaded = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localSavedPostsKey);
    } catch (e) {
      print('ローカル保存投稿のクリアに失敗: $e');
    }
  }
}
