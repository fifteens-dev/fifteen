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

  /// Firestore の app_config/global.inviteCode に設定したグローバルコードを取得
  Future<String?> _getGlobalInviteCode() async {
    try {
      final doc = await _firestore.collection('app_config').doc('global').get();
      return doc.data()?['inviteCode'] as String?;
    } catch (_) {
      return null;
    }
  }

  // 招待コードを検証（詳細な結果を返す）
  Future<InviteCodeValidationResult> validateInviteCodeDetailed(String code) async {
    try {
      // グローバル招待コードを先にチェック（管理者が Firebase コンソールで任意設定可能）
      final globalCode = await _getGlobalInviteCode();
      if (globalCode != null &&
          globalCode.isNotEmpty &&
          code.toUpperCase() == globalCode.toUpperCase()) {
        return InviteCodeValidationResult.valid;
      }

      final doc = await _firestore
          .collection(_inviteCodesCollection)
          .doc(code.toUpperCase())
          .get();

      if (!doc.exists) {
        return InviteCodeValidationResult.notFound;
      }

      final data = doc.data();
      if (data == null) return InviteCodeValidationResult.notFound;

      // 使用回数制限なし（usedCount はトラッキング用のみ）

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

  /// 招待コードを使用済みにする。
  ///
  /// invite_codes/{code} の usedCount を増やすと同時に、
  /// invite_usages に「誰が誰のコードを使ったか」を1レコード記録する。
  /// invite_usages は ADL個人賞（招待人数ランキング）の集計に使う。
  ///
  /// 戻り値: コードオーナーUID（招待者）。コード自己使用やグローバルコードの場合は null。
  Future<String?> markInviteCodeAsUsed(String code, String userId) async {
    // グローバルコードは使用済み記録不要
    final globalCode = await _getGlobalInviteCode();
    if (globalCode != null &&
        globalCode.isNotEmpty &&
        code.toUpperCase() == globalCode.toUpperCase()) {
      return null;
    }

    try {
      final upperCode = code.toUpperCase();
      final codeRef = _firestore.collection(_inviteCodesCollection).doc(upperCode);
      final codeSnap = await codeRef.get();
      final ownerUid = codeSnap.data()?['ownerUid'] as String?;

      final batch = _firestore.batch();
      batch.update(codeRef, {
        'usedCount': FieldValue.increment(1),
        'lastUsedBy': userId,
        'lastUsedAt': FieldValue.serverTimestamp(),
      });

      // 個人賞集計用: 招待者 != 自分 のときだけ記録する
      if (ownerUid != null && ownerUid.isNotEmpty && ownerUid != userId) {
        final usageRef = _firestore.collection('invite_usages').doc();
        batch.set(usageRef, {
          'ownerUid': ownerUid,
          'usedBy': userId,
          'code': upperCode,
          'usedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      return ownerUid;
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
