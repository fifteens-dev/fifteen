import '../models/post_model.dart';
import '../models/track_model.dart';
import '../models/post_theme.dart';

/// テスト用のダミー投稿データを生成するユーティリティ
class TestData {
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
        commentCount: 3,
        likedUserIds: ['user_a', 'user_b', 'user_c'],
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
        theme: PostTheme.blueGreen,
      ),

      // 投稿カード2（紫系グラデーション - いつか結婚しても）
      PostModel(
        postId: 'test_post_2',
        userId: 'test_user_2',
        username: 'l0hx9',
        userIconUrl: null,
        track: TrackModel(
          trackId: 'track_2',
          trackName: 'いつか結婚しても',
          artistName: 'My Hair is Bad',
          albumImageUrl: 'https://picsum.photos/seed/album2/400/400',
        ),
        likeCount: 3,
        commentCount: 3,
        likedUserIds: ['user_d', 'user_e'],
        createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 5)),
        theme: PostTheme.purple,
      ),

      // 投稿カード3（ベージュ系グラデーション）
      PostModel(
        postId: 'test_post_3',
        userId: 'test_user_3',
        username: 'rockstar',
        userIconUrl: null,
        track: TrackModel(
          trackId: 'track_3',
          trackName: 'Electric Dreams',
          artistName: 'Neon Lights',
          albumImageUrl: 'https://picsum.photos/seed/album3/400/400',
        ),
        likeCount: 89,
        commentCount: 15,
        likedUserIds: [],
        createdAt: DateTime.now().subtract(const Duration(hours: 8)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 8)),
        theme: PostTheme.beige,
      ),

      // 投稿カード4（青緑系グラデーション）
      PostModel(
        postId: 'test_post_4',
        userId: 'test_user_4',
        username: 'popsinger',
        userIconUrl: null,
        track: TrackModel(
          trackId: 'track_4',
          trackName: 'Dancing Queen',
          artistName: 'ABBA',
          albumImageUrl: 'https://picsum.photos/seed/album4/400/400',
        ),
        likeCount: 256,
        commentCount: 47,
        likedUserIds: ['user_f', 'user_g', 'user_h'],
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
        theme: PostTheme.blueGreen,
      ),

      // 投稿カード5（紫系グラデーション）
      PostModel(
        postId: 'test_post_5',
        userId: 'test_user_5',
        username: 'indie_artist',
        userIconUrl: null,
        track: TrackModel(
          trackId: 'track_5',
          trackName: 'Neon Nights',
          artistName: 'The Weeknd',
          albumImageUrl: 'https://picsum.photos/seed/album5/400/400',
        ),
        likeCount: 512,
        commentCount: 94,
        likedUserIds: ['user_i', 'user_j'],
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        updatedAt: DateTime.now().subtract(const Duration(days: 2)),
        theme: PostTheme.purple,
      ),

      // 投稿カード6（ベージュ系グラデーション）
      PostModel(
        postId: 'test_post_6',
        userId: 'test_user_6',
        username: 'edm_producer',
        userIconUrl: null,
        track: TrackModel(
          trackId: 'track_6',
          trackName: 'Sunrise Festival',
          artistName: 'Calvin Harris',
          albumImageUrl: 'https://picsum.photos/seed/album6/400/400',
        ),
        likeCount: 1024,
        commentCount: 187,
        likedUserIds: ['user_k'],
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        updatedAt: DateTime.now().subtract(const Duration(days: 3)),
        theme: PostTheme.beige,
      ),
    ];
  }
}
