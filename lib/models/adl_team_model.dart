import 'package:cloud_firestore/cloud_firestore.dart';

/// ADL班モデル
class AdlTeamModel {
  final String teamId;
  final String eventId;
  final String name; // 班名（例: "A班"）
  final String inviteCode; // 招待コード（6文字英数字）
  final DateTime inviteCodeExpiresAt;
  final int likeCount; // いいね集計（Cloud Functionが更新）
  final int memberCount;
  final DateTime createdAt;

  AdlTeamModel({
    required this.teamId,
    required this.eventId,
    required this.name,
    required this.inviteCode,
    required this.inviteCodeExpiresAt,
    this.likeCount = 0,
    this.memberCount = 0,
    required this.createdAt,
  });

  factory AdlTeamModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AdlTeamModel(
      teamId: doc.id,
      eventId: data['eventId'] ?? '',
      name: data['name'] ?? '',
      inviteCode: data['inviteCode'] ?? '',
      inviteCodeExpiresAt:
          (data['inviteCodeExpiresAt'] as Timestamp?)?.toDate() ??
              DateTime.now(),
      likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'eventId': eventId,
        'name': name,
        'inviteCode': inviteCode,
        'inviteCodeExpiresAt': Timestamp.fromDate(inviteCodeExpiresAt),
        'likeCount': likeCount,
        'memberCount': memberCount,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  bool get isInviteCodeValid => DateTime.now().isBefore(inviteCodeExpiresAt);
}
