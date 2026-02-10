import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 招待コード検証結果
enum InviteCodeValidationResult {
  valid,              // 有効
  notFound,           // 存在しない
  alreadyUsed,        // すでに使用済み
  expired,            // 期限切れ
  error,              // エラー
}

class InviteCodeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _inviteCodesCollection = 'invite_codes';

  // 招待コードを検証（詳細な結果を返す）
  Future<InviteCodeValidationResult> validateInviteCodeDetailed(String code) async {
    try {
      final doc = await _firestore
          .collection(_inviteCodesCollection)
          .doc(code.toUpperCase())
          .get();

      if (!doc.exists) {
        return InviteCodeValidationResult.notFound;
      }

      final data = doc.data();
      if (data == null) return InviteCodeValidationResult.notFound;

      // 使用回数制の場合
      final maxUses = data['maxUses'] as int?;
      final usedCount = data['usedCount'] as int? ?? 0;
      if (maxUses != null) {
        if (usedCount >= maxUses) {
          return InviteCodeValidationResult.alreadyUsed;
        }
      } else {
        // 従来の1回使い切り方式
        final isUsed = data['isUsed'] ?? false;
        if (isUsed) {
          return InviteCodeValidationResult.alreadyUsed;
        }
      }

      // 有効期限をチェック（オプション）
      if (data.containsKey('expiresAt')) {
        final expiresAt = (data['expiresAt'] as Timestamp).toDate();
        if (DateTime.now().isAfter(expiresAt)) {
          return InviteCodeValidationResult.expired;
        }
      }

      return InviteCodeValidationResult.valid;
    } catch (e) {
      if (kDebugMode) {
        print('Error validating invite code: $e');
      }
      return InviteCodeValidationResult.error;
    }
  }

  // 招待コードを検証（後方互換性のため）
  Future<bool> validateInviteCode(String code) async {
    final result = await validateInviteCodeDetailed(code);
    return result == InviteCodeValidationResult.valid;
  }

  // 招待コードを使用済みにする
  Future<void> markInviteCodeAsUsed(String code, String userId) async {
    try {
      final docRef = _firestore
          .collection(_inviteCodesCollection)
          .doc(code.toUpperCase());
      final doc = await docRef.get();
      final data = doc.data();

      if (data != null && data['maxUses'] != null) {
        // 使用回数制：カウントをインクリメント
        await docRef.update({
          'usedCount': FieldValue.increment(1),
          'lastUsedBy': userId,
          'lastUsedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // 従来方式：使用済みフラグ
        await docRef.update({
          'isUsed': true,
          'usedBy': userId,
          'usedAt': FieldValue.serverTimestamp(),
        });
      }
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

  // 使用回数制の招待コードを作成
  Future<void> createInviteCodeWithMaxUses(String code, int maxUses) async {
    try {
      await _firestore.collection(_inviteCodesCollection).doc(code.toUpperCase()).set({
        'code': code.toUpperCase(),
        'maxUses': maxUses,
        'usedCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error creating invite code: $e');
      }
      rethrow;
    }
  }
}
