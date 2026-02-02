import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/post_theme.dart';
import '../services/spotify_service.dart';
import '../utils/color_extractor.dart';
import '../constants/emotion_tags.dart';

/// テスト用データをFirestoreにセットアップするユーティリティ
class SetupTestData {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SpotifyService _spotifyService = SpotifyService();

  // ダミーユーザーの定数
  static const List<String> dummyUserIds = [
    'dummy_user_sana',
    'dummy_user_mina',
    'dummy_user_momo',
  ];

  static const Map<String, String> dummyUserProfileImages = {
    'dummy_user_sana': 'assets/profile_images/sana.png',
    'dummy_user_mina': 'assets/profile_images/mina.png',
    'dummy_user_momo': 'assets/profile_images/momo.png',
  };

  /// テスト用招待コードを作成
  Future<void> createTestInviteCodes() async {
    try {
      final testCodes = [
        'TEST123',
        'WELCOME',
        'HELLO15S',
      ];

      for (final code in testCodes) {
        await _firestore.collection('invite_codes').doc(code).set({
          'code': code,
          'isUsed': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (kDebugMode) {
          print('✅ Created test invite code: $code');
        }
      }

      if (kDebugMode) {
        print('✅ All test invite codes created successfully!');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error creating test invite codes: $e');
        // 権限エラーの場合は警告のみ（Firestoreルールの設定が必要）
        if (e.toString().contains('permission-denied')) {
          print('⚠️ Firestoreの権限エラーです。招待コード「TEST123」は手動で認証してください。');
        }
      }
      // 権限エラーの場合は再スローしない
      if (!e.toString().contains('permission-denied')) {
        rethrow;
      }
    }
  }

  /// 古いテスト投稿を削除（test_user_1/2/3の投稿）
  Future<void> deleteOldTestPosts() async {
    try {
      // test_user_1, test_user_2, test_user_3 の投稿を削除
      final oldTestUserIds = ['test_user_1', 'test_user_2', 'test_user_3'];

      for (final userId in oldTestUserIds) {
        final posts = await _firestore
            .collection('posts')
            .where('userId', isEqualTo: userId)
            .get();

        for (final doc in posts.docs) {
          await doc.reference.delete();
          if (kDebugMode) {
            final data = doc.data();
            final track = data['track'] as Map<String, dynamic>?;
            final trackName = track?['trackName'] ?? 'Unknown';
            print('🗑️  Deleted old test post: $trackName (userId: $userId)');
          }
        }
      }

      if (kDebugMode) {
        print('✅ All old test posts deleted successfully!');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error deleting old test posts: $e');
      }
      rethrow;
    }
  }

  /// ダミーユーザー以外の全投稿を削除
  Future<void> deleteNonDummyPosts() async {
    try {
      if (kDebugMode) {
        print('🗑️  Deleting all non-dummy user posts...');
      }

      // 全投稿を取得
      final allPosts = await _firestore.collection('posts').get();

      int deletedCount = 0;

      for (final doc in allPosts.docs) {
        final data = doc.data();
        final userId = data['userId'] as String?;

        // ダミーユーザーでない場合は削除
        if (userId != null && !dummyUserIds.contains(userId)) {
          await doc.reference.delete();

          final track = data['track'] as Map<String, dynamic>?;
          final trackName = track?['trackName'] ?? 'Unknown';
          final username = data['username'] ?? userId;

          if (kDebugMode) {
            print('🗑️  Deleted: "$trackName" by @$username (userId: $userId)');
          }

          deletedCount++;
        }
      }

      if (kDebugMode) {
        print('✅ Deleted $deletedCount non-dummy posts!');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error deleting non-dummy posts: $e');
      }
      rethrow;
    }
  }

  /// ダミーユーザーを作成
  Future<void> createDummyUsers() async {
    try {
      // ダミーユーザーのデータ
      final dummyUsers = [
        {
          'uid': 'dummy_user_sana',
          'phoneNumber': '+819012345678',
          'username': 'm.by__sana',
          'name': '사나 Sana',
          'bio': '🩶',
          'profileImageUrl': 'assets/profile_images/sana.png',
          'followers': <String>[],
          'following': <String>[],
          'postsCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        {
          'uid': 'dummy_user_mina',
          'phoneNumber': '+819087654321',
          'username': 'mina.myoi',
          'name': 'Mina Myoui',
          'bio': '🐧 TWICE',
          'profileImageUrl': 'assets/profile_images/mina.png',
          'followers': <String>[],
          'following': <String>[],
          'postsCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        {
          'uid': 'dummy_user_momo',
          'phoneNumber': '+819011112222',
          'username': 'momo.hirai',
          'name': 'Momo Hirai',
          'bio': '🍑 ダンス大好き',
          'profileImageUrl': 'assets/profile_images/momo.png',
          'followers': <String>[],
          'following': <String>[],
          'postsCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      ];

      for (final userData in dummyUsers) {
        await _firestore.collection('users').doc(userData['uid'] as String).set(userData);
        if (kDebugMode) {
          print('✅ Created dummy user: ${userData['username']}');
        }
      }

      if (kDebugMode) {
        print('✅ All dummy users created successfully!');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error creating dummy users: $e');
      }
      rethrow;
    }
  }

  /// 今日のVibeトピックを取得または作成
  Future<Map<String, String>> getOrCreateTodayVibeTopic() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // 既存のアクティブなトピックを検索（dateフィルタはクライアント側で実行）
      final existingTopics = await _firestore
          .collection('vibeTopics')
          .where('status', isEqualTo: 'active')
          .get();

      // クライアント側で今日の日付にフィルタリング
      final todayTopics = existingTopics.docs.where((doc) {
        final data = doc.data();
        final date = (data['date'] as Timestamp?)?.toDate();
        if (date == null) return false;

        final normalizedDate = DateTime(date.year, date.month, date.day);
        return normalizedDate.isAtSameMomentAs(today);
      }).toList();

      if (todayTopics.isNotEmpty) {
        // 既存のトピックを使用
        final doc = todayTopics.first;
        final data = doc.data();
        final topicId = doc.id;
        final title = data['title'] as String? ?? 'ドライブで聴きたい曲';

        if (kDebugMode) {
          print('✅ Using existing Vibe topic: $title (ID: $topicId)');
        }

        return {'id': topicId, 'title': title};
      }

      // 既存のトピックがない場合は新規作成
      const topicId = 'test_vibe_drive';
      const title = 'ドライブで聴きたい曲';

      await _firestore.collection('vibeTopics').doc(topicId).set({
        'title': title,
        'date': Timestamp.fromDate(today),
        'status': 'active',
        'voteCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('✅ Created new Vibe topic: $title (ID: $topicId)');
      }

      return {'id': topicId, 'title': title};
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting or creating Vibe topic: $e');
      }
      rethrow;
    }
  }

  /// Spotifyから楽曲を検索してダミーユーザーの投稿を作成
  Future<void> createDummyUserPosts() async {
    try {
      if (kDebugMode) {
        print('🎵 Searching for tracks on Spotify...');
      }

      // 今日のVibeトピックを取得または作成
      final vibeTopicData = await getOrCreateTodayVibeTopic();
      final vibeTopicId = vibeTopicData['id']!;
      final vibeTopicTitle = vibeTopicData['title']!;

      // 既存のダミーユーザーの投稿を削除（重複を防ぐ）
      final existingPosts = await _firestore
          .collection('posts')
          .where('userId', whereIn: dummyUserIds)
          .get();

      for (final doc in existingPosts.docs) {
        await doc.reference.delete();
      }

      if (kDebugMode) {
        print('🗑️  Deleted ${existingPosts.docs.length} existing dummy posts');
      }

      // 3人のダミーユーザーの投稿データ（各ユーザーに画像を割り当て）
      final userPosts = [
        // m.by__sana の投稿（J-POP / K-POP）
        {
          'userId': 'dummy_user_sana',
          'username': 'm.by__sana',
          'userIconUrl': 'assets/profile_images/sana.png',
          'queries': [
            'Lemon 米津玄師',
            'Candy Pop TWICE',
            'Pretender Official髭男dism',
            'KICK BACK 米津玄師',
          ],
          'photoUrls': [
            'assets/images/dummy_photo_1.jpg',
            'assets/images/dummy_photo_2.jpg',
            'assets/images/dummy_photo_3.jpg',
            'assets/images/dummy_photo_4.jpg',
          ],
        },
        // mina.myoi の投稿（アニメソング / J-POP）
        {
          'userId': 'dummy_user_mina',
          'username': 'mina.myoi',
          'userIconUrl': 'assets/profile_images/mina.png',
          'queries': [
            'アイドル YOASOBI',
            '残酷な天使のテーゼ 高橋洋子',
            'IRIS OUT 米津玄師',  // チェンソーマンOP（より具体的に）
            'たぶん YOASOBI',
          ],
          'photoUrls': [
            'assets/images/dummy_photo_5.jpg',
            'assets/images/dummy_photo_6.jpg',
            'assets/images/dummy_photo_7.jpg',
            'assets/images/dummy_photo_8.jpg',
          ],
        },
        // momo.hirai の投稿（人気J-POP）
        {
          'userId': 'dummy_user_momo',
          'username': 'momo.hirai',
          'userIconUrl': 'assets/profile_images/momo.png',
          'queries': [
            'きらり 藤井風',
            'Subtitle Official髭男dism',
            '水平線 back number',
            'ドライフラワー 優里',
          ],
          'photoUrls': [
            'assets/images/dummy_photo_9.jpg',
            'assets/images/dummy_photo_10.jpg',
            'assets/images/dummy_photo_11.jpg',
            'assets/images/dummy_photo_12.jpg',
          ],
        },
      ];

      int totalCreated = 0;

      for (final userData in userPosts) {
        final userId = userData['userId'] as String;
        final username = userData['username'] as String;
        final userIconUrl = userData['userIconUrl'] as String;
        final queries = userData['queries'] as List<String>;
        final photoUrls = userData['photoUrls'] as List<String>;

        // この投稿者以外のユーザーIDを取得（保存したユーザーとして設定）
        final savedByUserIds = dummyUserIds.where((id) => id != userId).toList();

        // 保存したユーザーのアイコンURLを取得
        final savedByUserIconUrls = savedByUserIds
            .map((id) => dummyUserProfileImages[id]!)
            .toList();

        int userPostCount = 0;

        for (int i = 0; i < queries.length; i++) {
          try {
            final tracks = await _spotifyService.searchTracks(queries[i], limit: 1);

            if (tracks.isNotEmpty) {
              final track = tracks.first;

              // アルバムアートから色を抽出してテーマを生成
              PostTheme? extractedTheme;
              try {
                if (kDebugMode) {
                  print('🎨 Extracting colors from album art...');
                }
                final albumArtUrl = track.albumImageUrl;
                extractedTheme = await ColorExtractor.extractThemeFromAlbumArt(albumArtUrl);

                if (kDebugMode && extractedTheme != null) {
                  print('✅ Color extraction complete: ${extractedTheme.gradientStart} → ${extractedTheme.gradientEnd}');
                }
              } catch (e) {
                if (kDebugMode) {
                  print('⚠️  Color extraction error (using default theme): $e');
                }
                extractedTheme = null;
              }

              // 投稿日時を設定（最初の1曲は昨日、残り3曲は今日）
              Timestamp createdAt;
              if (i == 0) {
                // 最初の投稿は昨日の同じ時刻
                final yesterday = DateTime.now().subtract(const Duration(days: 1));
                createdAt = Timestamp.fromDate(yesterday);
                if (kDebugMode) {
                  print('📅 Post date: Yesterday (${yesterday.toString().split(' ')[0]})');
                }
              } else {
                // 残りの投稿は今日（サーバー時刻）
                createdAt = Timestamp.now();
                if (kDebugMode) {
                  print('📅 Post date: Today');
                }
              }

              // 歌詞カードのレイアウトと位置をランダムに設定
              final selectedLayoutIndex = i % 5; // 0-4のレイアウトを順番に
              final cardPositionX = 50.0 + (i * 20.0); // 位置を少しずつずらす
              final cardPositionY = 100.0 + (i * 15.0);
              final cardScale = 1.0;
              final cardRotation = 0.0;

              // ランダムにVibeまたは感情を割り当て（50%の確率で各カテゴリー）
              final random = Random();
              final isVibe = random.nextBool();
              final String? postVibeTopicTitle;
              final String? emotionTag;
              final DateTime? vibeDate;

              if (isVibe) {
                // テスト用のVibeは全て今日のVibeトピックを使用
                postVibeTopicTitle = vibeTopicTitle;
                emotionTag = null;
                vibeDate = DateTime(
                  createdAt.toDate().year,
                  createdAt.toDate().month,
                  createdAt.toDate().day,
                );
              } else {
                // 感情タグをランダムに選択
                postVibeTopicTitle = null;
                emotionTag = EmotionTags.tags[random.nextInt(EmotionTags.tags.length)];
                vibeDate = null;
              }

              await _firestore.collection('posts').add({
                'userId': userId,
                'username': username,
                'userIconUrl': userIconUrl,
                'track': track.toMap(),
                'likeCount': (i + 1) * 7 + (userPostCount * 3),
                'commentCount': (i + 1) + userPostCount,
                'likedUserIds': <String>[],
                'savedByUserIds': savedByUserIds, // 他の2人のダミーユーザーが保存
                'savedByUserIconUrls': savedByUserIconUrls, // 保存したユーザーのアイコンURL
                'createdAt': createdAt,
                'updatedAt': createdAt,
                'theme': extractedTheme?.toMap() ?? PostTheme.defaultTheme.toMap(),
                'photoUrl': photoUrls[i], // 画像パスを追加
                'selectedLayoutIndex': selectedLayoutIndex,
                'cardPositionX': cardPositionX,
                'cardPositionY': cardPositionY,
                'cardScale': cardScale,
                'cardRotation': cardRotation,
                'isVibe': isVibe,
                'vibeTopicId': isVibe ? vibeTopicId : null,
                'vibeTopicTitle': postVibeTopicTitle,
                'vibeDate': vibeDate != null ? Timestamp.fromDate(vibeDate) : null,
                'emotionTag': emotionTag,
              });

              userPostCount++;
              totalCreated++;

              if (kDebugMode) {
                final categoryInfo = isVibe ? 'Vibe: $postVibeTopicTitle' : 'Emotion: $emotionTag';
                print('✅ [$username] ${track.trackName} by ${track.artistName} ($categoryInfo)');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('⚠️  Could not find track for query: ${queries[i]}');
            }
          }
        }

        // ユーザーの投稿数を更新
        if (userPostCount > 0) {
          await _firestore.collection('users').doc(userId).update({
            'postsCount': userPostCount,
          });
        }
      }

      if (kDebugMode) {
        print('✅ Created $totalCreated posts from ${userPosts.length} dummy users!');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error creating dummy user posts: $e');
      }
      rethrow;
    }
  }

  /// ダミーユーザーのいいねをセットアップ
  /// 全てのダミーユーザーが残り2人の全投稿をいいねする
  Future<void> setupDummyLikes() async {
    try {
      if (kDebugMode) {
        print('👍 Setting up dummy likes for all dummy users...');
      }

      int totalLikedCount = 0;

      for (final likerId in dummyUserIds) {
        final likerIconUrl = dummyUserProfileImages[likerId]!;
        final targetUserIds = dummyUserIds.where((id) => id != likerId).toList();

        int likedCount = 0;

        for (final targetUserId in targetUserIds) {
          final posts = await _firestore
              .collection('posts')
              .where('userId', isEqualTo: targetUserId)
              .get();

          for (final doc in posts.docs) {
            final data = doc.data();
            final likedUserIds = List<String>.from(data['likedUserIds'] ?? []);
            final likedByUserIconUrls =
                List<String>.from(data['likedByUserIconUrls'] ?? []);

            // 既にいいね済みの場合はスキップ
            if (likedUserIds.contains(likerId)) {
              if (kDebugMode) {
                final track = data['track'] as Map<String, dynamic>?;
                final trackName = track?['trackName'] ?? 'Unknown';
                print('⏭️  Already liked by $likerId: $trackName');
              }
              continue;
            }

            likedUserIds.add(likerId);
            likedByUserIconUrls.add(likerIconUrl);

            await doc.reference.update({
              'likedUserIds': likedUserIds,
              'likedByUserIconUrls': likedByUserIconUrls,
              'likeCount': likedUserIds.length,
              'updatedAt': FieldValue.serverTimestamp(),
            });

            likedCount++;

            if (kDebugMode) {
              final track = data['track'] as Map<String, dynamic>?;
              final trackName = track?['trackName'] ?? 'Unknown';
              final username = data['username'] ?? targetUserId;
              print('👍 $likerId liked: "$trackName" by @$username');
            }
          }
        }

        totalLikedCount += likedCount;

        if (kDebugMode) {
          print('✅ $likerId liked $likedCount posts');
        }
      }

      if (kDebugMode) {
        print('✅ All dummy likes set up! Total: $totalLikedCount likes');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error setting up dummy likes: $e');
      }
      rethrow;
    }
  }

  /// すべてのテストデータをセットアップ
  Future<void> setupAllTestData() async {
    try {
      await createTestInviteCodes();

      if (kDebugMode) {
        print('✅ Test data setup completed!');
        print('');
        print('Available test invite codes:');
        print('  - TEST123');
        print('  - WELCOME');
        print('  - HELLO15S');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error setting up test data: $e');
        // 権限エラーの場合は警告のみ
        if (e.toString().contains('permission-denied')) {
          print('⚠️ Firestoreの権限エラーです。招待コード画面では「TEST123」を入力してテストしてください。');
          return; // 成功として扱う
        }
      }
      rethrow;
    }
  }
}
