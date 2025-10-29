import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class InviteCodeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _inviteCodesCollection = 'invite_codes';

  // 招待コードを検証
  Future<bool> validateInviteCode(String code) async {
    try {
      final doc = await _firestore
          .collection(_inviteCodesCollection)
          .doc(code.toUpperCase())
          .get();

      if (!doc.exists) {
        return false;
      }

      final data = doc.data();
      if (data == null) return false;

      // 使用済みかチェック
      final isUsed = data['isUsed'] ?? false;
      if (isUsed) {
        return false;
      }

      // 有効期限をチェック（オプション）
      if (data.containsKey('expiresAt')) {
        final expiresAt = (data['expiresAt'] as Timestamp).toDate();
        if (DateTime.now().isAfter(expiresAt)) {
          return false;
        }
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error validating invite code: $e');
      }
      return false;
    }
  }

  // 招待コードを使用済みにする
  Future<void> markInviteCodeAsUsed(String code, String userId) async {
    try {
      await _firestore
          .collection(_inviteCodesCollection)
          .doc(code.toUpperCase())
          .update({
        'isUsed': true,
        'usedBy': userId,
        'usedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error marking invite code as used: $e');
      }
      rethrow;
    }
  }

  // 開発用：テスト用招待コードを作成
  Future<void> createTestInviteCode(String code) async {
    try {
      await _firestore.collection(_inviteCodesCollection).doc(code).set({
        'code': code,
        'isUsed': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error creating test invite code: $e');
      }
      rethrow;
    }
  }
}
