import 'package:cloud_firestore/cloud_firestore.dart';

/// グループ（groups/{groupId}）。
///
/// ホーム画面に並ぶ投稿の単位。友達（相互フォロー）とは別の仕組みで、
/// 友達でない人同士が同じグループにいてもよい。
///
/// 1 グループは [maxMembers] 人まで。1 人が入れるグループ数に上限はない
/// （2026-11-01 の方針）。
///
/// 設定（名前・アイコン・参加の締め切り）はメンバーなら誰でも変えられる。
/// 最後の 1 人が抜けたらグループごと消す。抜けた人の投稿は posts に残るので、
/// Music Memory やプレイリストからは消えない。
class GroupModel {
  /// 1 グループの人数の上限（作った人を含む）。firestore.rules と揃えること。
  static const int maxMembers = 10;

  /// 既定のアイコン（イラスト）の数。作成時にこの中からランダムに選ぶ。
  static const int iconCount = 7;

  final String groupId;
  final String name;

  /// 作った人。
  final String ownerId;

  /// メンバーの uid。作った人も含む。`arrayContains` で自分のグループを引く。
  final List<String> memberIds;

  final DateTime createdAt;

  /// 既定のアイコンの番号（0〜[iconCount]-1）。
  final int iconIndex;

  /// 招待コード（6 桁の英数字）。まだ無いグループは null。
  final String? inviteCode;

  /// 参加を締め切ったか。締め切るとリンクやコードからも参加できない。
  final bool joinClosed;

  /// このグループの通知を切っているメンバー。
  final List<String> mutedMemberIds;

  const GroupModel({
    required this.groupId,
    required this.name,
    required this.ownerId,
    required this.memberIds,
    required this.createdAt,
    this.iconIndex = 0,
    this.inviteCode,
    this.joinClosed = false,
    this.mutedMemberIds = const [],
  });

  factory GroupModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final icon = (data['iconIndex'] as num?)?.toInt();
    return GroupModel(
      groupId: doc.id,
      name: (data['name'] as String?) ?? '',
      ownerId: (data['ownerId'] as String?) ?? '',
      memberIds: List<String>.from(data['memberIds'] as List? ?? const []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      // アイコンを持つ前に作ったグループは ID から決める（毎回同じになる）。
      iconIndex: (icon ?? doc.id.hashCode.abs()) % iconCount,
      inviteCode: data['inviteCode'] as String?,
      joinClosed: data['joinClosed'] == true,
      mutedMemberIds:
          List<String>.from(data['mutedMemberIds'] as List? ?? const []),
    );
  }

  bool isMutedFor(String uid) => mutedMemberIds.contains(uid);
}
