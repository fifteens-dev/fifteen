import 'package:cloud_firestore/cloud_firestore.dart';

/// Vibeお題のステータス
enum VibeTopicStatus {
  voting,   // 投票受付中（翌日のお題候補）
  active,   // アクティブ（今日のお題）
  archived, // アーカイブ済み
}

/// Vibeお題を表すモデル
class VibeTopicModel {
  final String topicId;
  final String title; // 例: "ドライブで聴きたい曲"
  final DateTime date; // このお題がアクティブな日付
  final VibeTopicStatus status;
  final int voteCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  VibeTopicModel({
    required this.topicId,
    required this.title,
    required this.date,
    this.status = VibeTopicStatus.voting,
    this.voteCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  // Firestoreドキュメントから作成
  factory VibeTopicModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return VibeTopicModel(
      topicId: doc.id,
      title: data['title'] ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: _statusFromString(data['status'] ?? 'voting'),
      voteCount: data['voteCount'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // Firestoreに保存する形式に変換
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'date': Timestamp.fromDate(date),
      'status': status.name,
      'voteCount': voteCount,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  // コピーを作成（一部のフィールドを更新）
  VibeTopicModel copyWith({
    String? topicId,
    String? title,
    DateTime? date,
    VibeTopicStatus? status,
    int? voteCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return VibeTopicModel(
      topicId: topicId ?? this.topicId,
      title: title ?? this.title,
      date: date ?? this.date,
      status: status ?? this.status,
      voteCount: voteCount ?? this.voteCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ステータス文字列からEnumに変換
  static VibeTopicStatus _statusFromString(String status) {
    switch (status) {
      case 'active':
        return VibeTopicStatus.active;
      case 'archived':
        return VibeTopicStatus.archived;
      case 'voting':
      default:
        return VibeTopicStatus.voting;
    }
  }
}

/// VibeTopicStatusの拡張機能
extension VibeTopicStatusExtension on VibeTopicStatus {
  String get displayName {
    switch (this) {
      case VibeTopicStatus.voting:
        return '投票受付中';
      case VibeTopicStatus.active:
        return 'アクティブ';
      case VibeTopicStatus.archived:
        return 'アーカイブ';
    }
  }
}
