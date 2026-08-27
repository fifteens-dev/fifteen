import 'package:cloud_firestore/cloud_firestore.dart';

/// Milfolha チームアカウントの統計・プロフィール（milfolha_teams/{teamId}）。
///
/// ADL の AdlTeamModel に準拠。班プロフィール画面のアイコン/紹介文/名前を保持する。
/// メンバー数・ポイントはクライアント集計するためここには持たない（プロフィール表示は
/// memberCount のみ任意で保持）。
class MilfolhaTeamModel {
  final String teamId;
  final String name; // 表示名（例: "A"）
  final String? profileImageUrl; // 班アイコン（管理者/班員が設定）
  final String? description; // 班紹介文
  final int memberCount;

  const MilfolhaTeamModel({
    required this.teamId,
    required this.name,
    this.profileImageUrl,
    this.description,
    this.memberCount = 0,
  });

  factory MilfolhaTeamModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return MilfolhaTeamModel(
      teamId: doc.id,
      name: (data['name'] as String?) ?? doc.id,
      profileImageUrl: data['profileImageUrl'] as String?,
      description: data['description'] as String?,
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
    );
  }
}
