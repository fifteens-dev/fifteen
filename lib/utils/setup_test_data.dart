import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/track_model.dart';
import '../models/post_theme.dart';
import '../services/spotify_service.dart';
import '../utils/color_extractor.dart';

/// テスト用データをFirestoreにセットアップするユーティリティ
class SetupTestData {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SpotifyService _spotifyService = SpotifyService();

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

      // ダミーユーザーのID
      final dummyUserIds = ['dummy_user_sana', 'dummy_user_mina', 'dummy_user_momo'];

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
          'profileImageUrl': null,
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
          'profileImageUrl': null,
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
          'profileImageUrl': null,
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

  /// Spotifyから楽曲を検索してダミーユーザーの投稿を作成
  Future<void> createDummyUserPosts() async {
    try {
      if (kDebugMode) {
        print('🎵 Searching for tracks on Spotify...');
      }

      // 既存のダミーユーザーの投稿を削除（重複を防ぐ）
      final existingPosts = await _firestore
          .collection('posts')
          .where('userId', whereIn: ['dummy_user_sana', 'dummy_user_mina', 'dummy_user_momo'])
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
        final queries = userData['queries'] as List<String>;
        final photoUrls = userData['photoUrls'] as List<String>;

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

              await _firestore.collection('posts').add({
                'userId': userId,
                'username': username,
                'userIconUrl': null,
                'track': track.toMap(),
                'likeCount': (i + 1) * 7 + (userPostCount * 3),
                'commentCount': (i + 1) + userPostCount,
                'likedUserIds': <String>[],
                'createdAt': createdAt,
                'updatedAt': createdAt,
                'theme': extractedTheme?.toMap() ?? PostTheme.defaultTheme.toMap(),
                'photoUrl': photoUrls[i], // 画像パスを追加
              });

              userPostCount++;
              totalCreated++;

              if (kDebugMode) {
                print('✅ [$username] ${track.trackName} by ${track.artistName} (photo: ${photoUrls[i]})');
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
