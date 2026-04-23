import 'package:cloud_firestore/cloud_firestore.dart';

/// 通知のタイプ
enum NotificationType {
  like,     // いいね
  comment,  // コメント
  follow,   // フォロー
  official, // 公式通知
  post,     // フォロー中ユーザーの投稿通知
  vibe,     // 毎日20:00のVibe通知
  mention,  // コメントでのタグ付け（@メンション）
}

/// 通知モデル
class NotificationModel {
  final String notificationId;
  final NotificationType type;
  final String recipientId; // 通知を受け取るユーザーID
  final String senderId; // アクションを起こしたユーザーID（公式通知の場合は"system"）
  final String senderUsername;
  final String? senderIconUrl;

  // いいね・コメント通知用フィールド
  final String? postId;
  final List<String>? postIds; // バッチ投稿通知用（複数投稿ID）
  final String? albumArtUrl;
  final String? trackName;

  // コメント通知用フィールド
  final String? commentText;

  // 公式通知用フィールド
  final String? title;
  final String? body;
  final String? imageUrl;
  final String? actionUrl; // タップ時の遷移先URL

  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;

  NotificationModel({
    required this.notificationId,
    required this.type,
    required this.recipientId,
    required this.senderId,
    required this.senderUsername,
    this.senderIconUrl,
    this.postId,
    this.postIds,
    this.albumArtUrl,
    this.trackName,
    this.commentText,
    this.title,
    this.body,
    this.imageUrl,
    this.actionUrl,
    this.isRead = false,
    required this.createdAt,
    this.readAt,
  });

  /// Firestoreドキュメントから作成
  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return NotificationModel(
      notificationId: doc.id,
      type: NotificationType.values.firstWhere(
        (e) => e.toString() == 'NotificationType.${data['type']}',
        orElse: () => NotificationType.like,
      ),
      recipientId: data['recipientId'] ?? '',
      senderId: data['senderId'] ?? '',
      senderUsername: data['senderUsername'] ?? '',
      senderIconUrl: data['senderIconUrl'],
      postId: data['postId'],
      postIds: data['postIds'] != null
          ? List<String>.from(data['postIds'] as List)
          : null,
      albumArtUrl: data['albumArtUrl'],
      trackName: data['trackName'],
      commentText: data['commentText'],
      title: data['title'],
      body: data['body'],
      imageUrl: data['imageUrl'],
      actionUrl: data['actionUrl'],
      isRead: data['isRead'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      readAt: (data['readAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Firestoreドキュメント用マップに変換
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'recipientId': recipientId,
      'senderId': senderId,
      'senderUsername': senderUsername,
      'senderIconUrl': senderIconUrl,
      'postId': postId,
      'postIds': postIds,
      'albumArtUrl': albumArtUrl,
      'trackName': trackName,
      'commentText': commentText,
      'title': title,
      'body': body,
      'imageUrl': imageUrl,
      'actionUrl': actionUrl,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
    };
  }

  /// 通知の一部フィールドを更新したコピーを作成
  NotificationModel copyWith({
    bool? isRead,
    DateTime? readAt,
  }) {
    return NotificationModel(
      notificationId: notificationId,
      type: type,
      recipientId: recipientId,
      senderId: senderId,
      senderUsername: senderUsername,
      senderIconUrl: senderIconUrl,
      postId: postId,
      postIds: postIds,
      albumArtUrl: albumArtUrl,
      trackName: trackName,
      commentText: commentText,
      title: title,
      body: body,
      imageUrl: imageUrl,
      actionUrl: actionUrl,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
    );
  }

  /// 通知メッセージを取得
  String getMessage() {
    switch (type) {
      case NotificationType.like:
        return 'あなたの投稿にいいねしました';
      case NotificationType.comment:
        return 'あなたの投稿にコメントしました';
      case NotificationType.follow:
        return 'があなたをフォローしました';
      case NotificationType.official:
        return body ?? '';
      case NotificationType.post:
        return body ?? '';
      case NotificationType.vibe:
        return body ?? '';
      case NotificationType.mention:
        return 'があなたをタグ付けしました';
    }
  }

  /// 相対時間を計算（例: "1d", "4h", "30m", "now"）
  String getRelativeTime() {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }
}
