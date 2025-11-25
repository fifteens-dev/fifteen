import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/track_model.dart';
import '../models/post_theme.dart';

/// テスト用データをFirestoreにセットアップするユーティリティ
class SetupTestData {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

  /// テスト用投稿データを作成
  Future<void> createTestPosts() async {
    try {
      final testPosts = [
        {
          'userId': 'test_user_1',
          'username': 'knyaita',
          'userIconUrl': null,
          'track': TrackModel(
            trackId: 'track_1',
            trackName: 'いとしのエリー',
            artistName: 'サザンオールスターズ',
            albumImageUrl: '',
          ).toMap(),
          'likeCount': 3,
          'commentCount': 3,
          'likedUserIds': [],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'theme': PostTheme.blueGreen.toMap(),
        },
        {
          'userId': 'test_user_2',
          'username': 'musiclover',
          'userIconUrl': null,
          'track': TrackModel(
            trackId: 'track_2',
            trackName: 'Lemon',
            artistName: '米津玄師',
            albumImageUrl: '',
          ).toMap(),
          'likeCount': 5,
          'commentCount': 2,
          'likedUserIds': [],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'theme': PostTheme.purple.toMap(),
        },
        {
          'userId': 'test_user_3',
          'username': 'vibemaker',
          'userIconUrl': null,
          'track': TrackModel(
            trackId: 'track_3',
            trackName: 'きらり',
            artistName: '藤井風',
            albumImageUrl: '',
          ).toMap(),
          'likeCount': 8,
          'commentCount': 4,
          'likedUserIds': [],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'theme': PostTheme.beige.toMap(),
        },
      ];

      for (final postData in testPosts) {
        await _firestore.collection('posts').add(postData);
        if (kDebugMode) {
          final track = postData['track'] as Map<String, dynamic>;
          print('✅ Created test post: ${track['trackName']}');
        }
      }

      if (kDebugMode) {
        print('✅ All test posts created successfully!');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error creating test posts: $e');
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
