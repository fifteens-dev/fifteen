import 'package:cloud_firestore/cloud_firestore.dart';

/// ADLイベントモデル
class AdlEventModel {
  final String eventId;
  final String name;
  final bool isActive;
  final DateTime startTime;
  final DateTime inviteCodeExpiresAt; // 招待コード有効期限（最大4時間）
  final DateTime createdAt;
  final String createdBy;

  AdlEventModel({
    required this.eventId,
    required this.name,
    required this.isActive,
    required this.startTime,
    required this.inviteCodeExpiresAt,
    required this.createdAt,
    required this.createdBy,
  });

  factory AdlEventModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AdlEventModel(
      eventId: doc.id,
      name: data['name'] ?? '',
      isActive: data['isActive'] == true,
      startTime: (data['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      inviteCodeExpiresAt:
          (data['inviteCodeExpiresAt'] as Timestamp?)?.toDate() ??
              DateTime.now(),
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'isActive': isActive,
        'startTime': Timestamp.fromDate(startTime),
        'inviteCodeExpiresAt': Timestamp.fromDate(inviteCodeExpiresAt),
        'createdAt': Timestamp.fromDate(createdAt),
        'createdBy': createdBy,
      };

  bool get isInviteCodeValid => DateTime.now().isBefore(inviteCodeExpiresAt);
}
