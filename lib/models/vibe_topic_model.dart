import 'package:cloud_firestore/cloud_firestore.dart';

/// Vibeお題のステータス
enum VibeTopicStatus {
  active,   // アクティブ（今日のお題）
  archived, // アーカイブ済み
}

/// Vibeお題を表すモデル
class VibeTopicModel {
  final String topicId;
  final String title; // 例: "夜中に1人で聴きたい曲"
  final String emoji; // 例: "🌙"（カテゴリ固定絵文字）
  final DateTime date; // このお題がアクティブな日付
  final VibeTopicStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  VibeTopicModel({
    required this.topicId,
    required this.title,
    this.emoji = '🎵',
    required this.date,
    this.status = VibeTopicStatus.active,
    required this.createdAt,
    required this.updatedAt,
  });

  // Firestoreドキュメントから作成
  factory VibeTopicModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return VibeTopicModel(
      topicId: doc.id,
      title: data['title'] ?? '',
      emoji: (data['emoji'] as String?) ?? '🎵',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: _statusFromString(data['status'] ?? 'active'),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // Firestoreに保存する形式に変換
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'emoji': emoji,
      'date': Timestamp.fromDate(date),
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  // コピーを作成（一部のフィールドを更新）
  VibeTopicModel copyWith({
    String? topicId,
    String? title,
    String? emoji,
    DateTime? date,
    VibeTopicStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return VibeTopicModel(
      topicId: topicId ?? this.topicId,
      title: title ?? this.title,
      emoji: emoji ?? this.emoji,
      date: date ?? this.date,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ステータス文字列からEnumに変換
  static VibeTopicStatus _statusFromString(String status) {
    switch (status) {
      case 'archived':
        return VibeTopicStatus.archived;
      case 'active':
      default:
        return VibeTopicStatus.active;
    }
  }
}

/// VibeTopicStatusの拡張機能
extension VibeTopicStatusExtension on VibeTopicStatus {
  String get displayName {
    switch (this) {
      case VibeTopicStatus.active:
        return 'アクティブ';
      case VibeTopicStatus.archived:
        return 'アーカイブ';
    }
  }
}
