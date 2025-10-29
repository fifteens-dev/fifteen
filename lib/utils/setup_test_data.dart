import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
      }
      rethrow;
    }
  }
}
