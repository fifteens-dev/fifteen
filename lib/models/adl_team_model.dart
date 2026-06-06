import 'package:cloud_firestore/cloud_firestore.dart';

/// ADL班モデル
class AdlTeamModel {
  final String teamId;
  final String eventId;
  final String name; // 班名（例: "A班"）
  final String inviteCode; // 招待コード（6文字英数字）
  final int likeCount; // いいね集計（Cloud Functionが更新）
  final int memberCount;
  final int postCount; // 投稿数集計（Cloud Functionが更新）
  final DateTime createdAt;
  final String? profileImageUrl; // 班プロフィール画像URL（管理者が設定）
  final String? description; // 班紹介文（管理者が設定）

  AdlTeamModel({
    required this.teamId,
    required this.eventId,
    required this.name,
    required this.inviteCode,
    this.likeCount = 0,
    this.memberCount = 0,
    this.postCount = 0,
    required this.createdAt,
    this.profileImageUrl,
    this.description,
  });

  factory AdlTeamModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AdlTeamModel(
      teamId: doc.id,
      eventId: data['eventId'] ?? '',
      name: data['name'] ?? '',
      inviteCode: data['inviteCode'] ?? '',
      likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
      postCount: (data['postCount'] as num?)?.toInt() ?? 0,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      profileImageUrl: data['profileImageUrl'] as String?,
      description: data['description'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'eventId': eventId,
        'name': name,
        'inviteCode': inviteCode,
        'likeCount': likeCount,
        'memberCount': memberCount,
        'postCount': postCount,
        'createdAt': Timestamp.fromDate(createdAt),
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
        if (description != null) 'description': description,
      };
}
