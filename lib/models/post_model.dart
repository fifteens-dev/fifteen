import 'package:cloud_firestore/cloud_firestore.dart';
import 'track_model.dart';
import 'post_theme.dart';

/// 投稿情報を表すモデル
class PostModel {
  final String postId;
  final String userId;
  final String username;
  final String? userIconUrl;
  final TrackModel track;
  final int likeCount;
  final int commentCount;
  final List<String> likedUserIds; // いいねしたユーザーのIDリスト
  final List<String> likedByUserIconUrls; // いいねしたユーザーのアイコンURLリスト
  final List<String> savedByUserIds; // 保存したユーザーのIDリスト
  final List<String> savedByUserIconUrls; // 保存したユーザーのアイコンURLリスト
  final DateTime createdAt;
  final DateTime updatedAt;
  final PostTheme theme; // カラーテーマ
  final String? photoUrl; // 投稿の写真URL
  final double imageOffsetX; // 写真のXオフセット
  final double imageOffsetY; // 写真のYオフセット
  final double imageScale; // 写真のスケール
  final double imageNaturalWidth; // 写真の元の幅
  final double imageNaturalHeight; // 写真の元の高さ
  final int selectedLayoutIndex; // 選択された歌詞カードレイアウト
  final double cardPositionX; // 歌詞カードのX位置
  final double cardPositionY; // 歌詞カードのY位置
  final double cardScale; // 歌詞カードのスケール
  final double cardRotation; // 歌詞カードの回転角度（ラジアン）
  final bool isVibe; // Vibe投稿かどうか
  final String? vibeTopicId; // 参加しているお題のID
  final String? vibeTopicTitle; // Vibeお題のタイトル（例: "ドライブで聴きたい曲"）
  final DateTime? vibeDate; // Vibe投稿の日付（集計用）
  final String? emotionTag; // 感情タグ（例: "嬉しい", "悲しい", "楽しい"）
  final String? lyricsText; // 歌詞テキスト（歌詞カード表示用）
  final int audioStartMs; // 音楽再生開始位置（ミリ秒）
  final int audioDurationSec; // 音楽再生時間（秒）

  PostModel({
    required this.postId,
    required this.userId,
    required this.username,
    this.userIconUrl,
    required this.track,
    this.likeCount = 0,
    this.commentCount = 0,
    this.likedUserIds = const [],
    this.likedByUserIconUrls = const [],
    this.savedByUserIds = const [],
    this.savedByUserIconUrls = const [],
    required this.createdAt,
    required this.updatedAt,
    this.theme = PostTheme.defaultTheme,
    this.photoUrl,
    this.imageOffsetX = 0.0,
    this.imageOffsetY = 0.0,
    this.imageScale = 1.0,
    this.imageNaturalWidth = 0.0,
    this.imageNaturalHeight = 0.0,
    this.selectedLayoutIndex = 0,
    this.cardPositionX = 0.0,
    this.cardPositionY = 0.0,
    this.cardScale = 1.0,
    this.cardRotation = 0.0,
    this.isVibe = false,
    this.vibeTopicId,
    this.vibeTopicTitle,
    this.vibeDate,
    this.emotionTag,
    this.lyricsText,
    this.audioStartMs = 0,
    this.audioDurationSec = 15,
  });

  // Firestoreドキュメントから作成
  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return PostModel(
      postId: doc.id,
      userId: data['userId'] ?? '',
      username: data['username'] ?? '',
      userIconUrl: data['userIconUrl'],
      track: TrackModel.fromMap(data['track'] ?? {}),
      likeCount: data['likeCount'] ?? 0,
      commentCount: data['commentCount'] ?? 0,
      likedUserIds: List<String>.from(data['likedUserIds'] ?? []),
      likedByUserIconUrls: List<String>.from(data['likedByUserIconUrls'] ?? []),
      savedByUserIds: List<String>.from(data['savedByUserIds'] ?? []),
      savedByUserIconUrls: List<String>.from(data['savedByUserIconUrls'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      theme: data['theme'] != null
          ? PostTheme.fromMap(data['theme'] as Map<String, dynamic>)
          : PostTheme.defaultTheme,
      photoUrl: data['photoUrl'],
      imageOffsetX: (data['imageOffsetX'] ?? 0.0).toDouble(),
      imageOffsetY: (data['imageOffsetY'] ?? 0.0).toDouble(),
      imageScale: (data['imageScale'] ?? 1.0).toDouble(),
      imageNaturalWidth: (data['imageNaturalWidth'] ?? 0.0).toDouble(),
      imageNaturalHeight: (data['imageNaturalHeight'] ?? 0.0).toDouble(),
      selectedLayoutIndex: data['selectedLayoutIndex'] ?? 0,
      cardPositionX: (data['cardPositionX'] ?? 0.0).toDouble(),
      cardPositionY: (data['cardPositionY'] ?? 0.0).toDouble(),
      cardScale: (data['cardScale'] ?? 1.0).toDouble(),
      cardRotation: (data['cardRotation'] ?? 0.0).toDouble(),
      isVibe: data['isVibe'] ?? false,
      vibeTopicId: data['vibeTopicId'],
      vibeTopicTitle: data['vibeTopicTitle'],
      vibeDate: (data['vibeDate'] as Timestamp?)?.toDate(),
      emotionTag: data['emotionTag'],
      lyricsText: data['lyricsText'],
      audioStartMs: data['audioStartMs'] ?? 0,
      audioDurationSec: data['audioDurationSec'] ?? 15,
    );
  }

  // Firestoreに保存する形式に変換
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'username': username,
      'userIconUrl': userIconUrl,
      'track': track.toMap(),
      'likeCount': likeCount,
      'commentCount': commentCount,
      'likedUserIds': likedUserIds,
      'likedByUserIconUrls': likedByUserIconUrls,
      'savedByUserIds': savedByUserIds,
      'savedByUserIconUrls': savedByUserIconUrls,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'theme': theme.toMap(),
      'photoUrl': photoUrl,
      'imageOffsetX': imageOffsetX,
      'imageOffsetY': imageOffsetY,
      'imageScale': imageScale,
      'imageNaturalWidth': imageNaturalWidth,
      'imageNaturalHeight': imageNaturalHeight,
      'selectedLayoutIndex': selectedLayoutIndex,
      'cardPositionX': cardPositionX,
      'cardPositionY': cardPositionY,
      'cardScale': cardScale,
      'cardRotation': cardRotation,
      'isVibe': isVibe,
      'vibeTopicId': vibeTopicId,
      'vibeTopicTitle': vibeTopicTitle,
      'vibeDate': vibeDate != null ? Timestamp.fromDate(vibeDate!) : null,
      'emotionTag': emotionTag,
      'lyricsText': lyricsText,
      'audioStartMs': audioStartMs,
      'audioDurationSec': audioDurationSec,
    };
  }

  // コピーを作成（一部のフィールドを更新）
  PostModel copyWith({
    String? postId,
    String? userId,
    String? username,
    String? userIconUrl,
    TrackModel? track,
    int? likeCount,
    int? commentCount,
    List<String>? likedUserIds,
    List<String>? likedByUserIconUrls,
    List<String>? savedByUserIds,
    List<String>? savedByUserIconUrls,
    DateTime? createdAt,
    DateTime? updatedAt,
    PostTheme? theme,
    String? photoUrl,
    double? imageOffsetX,
    double? imageOffsetY,
    double? imageScale,
    double? imageNaturalWidth,
    double? imageNaturalHeight,
    int? selectedLayoutIndex,
    double? cardPositionX,
    double? cardPositionY,
    double? cardScale,
    double? cardRotation,
    bool? isVibe,
    String? vibeTopicId,
    String? vibeTopicTitle,
    DateTime? vibeDate,
    String? emotionTag,
    String? lyricsText,
    int? audioStartMs,
    int? audioDurationSec,
  }) {
    return PostModel(
      postId: postId ?? this.postId,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      userIconUrl: userIconUrl ?? this.userIconUrl,
      track: track ?? this.track,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      likedUserIds: likedUserIds ?? this.likedUserIds,
      likedByUserIconUrls: likedByUserIconUrls ?? this.likedByUserIconUrls,
      savedByUserIds: savedByUserIds ?? this.savedByUserIds,
      savedByUserIconUrls: savedByUserIconUrls ?? this.savedByUserIconUrls,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      theme: theme ?? this.theme,
      photoUrl: photoUrl ?? this.photoUrl,
      imageOffsetX: imageOffsetX ?? this.imageOffsetX,
      imageOffsetY: imageOffsetY ?? this.imageOffsetY,
      imageScale: imageScale ?? this.imageScale,
      imageNaturalWidth: imageNaturalWidth ?? this.imageNaturalWidth,
      imageNaturalHeight: imageNaturalHeight ?? this.imageNaturalHeight,
      selectedLayoutIndex: selectedLayoutIndex ?? this.selectedLayoutIndex,
      cardPositionX: cardPositionX ?? this.cardPositionX,
      cardPositionY: cardPositionY ?? this.cardPositionY,
      cardScale: cardScale ?? this.cardScale,
      cardRotation: cardRotation ?? this.cardRotation,
      isVibe: isVibe ?? this.isVibe,
      vibeTopicId: vibeTopicId ?? this.vibeTopicId,
      vibeTopicTitle: vibeTopicTitle ?? this.vibeTopicTitle,
      vibeDate: vibeDate ?? this.vibeDate,
      emotionTag: emotionTag ?? this.emotionTag,
      lyricsText: lyricsText ?? this.lyricsText,
      audioStartMs: audioStartMs ?? this.audioStartMs,
      audioDurationSec: audioDurationSec ?? this.audioDurationSec,
    );
  }

  // いいねを追加
  PostModel toggleLike(String userId) {
    final isLiked = likedUserIds.contains(userId);
    final newLikedUserIds = List<String>.from(likedUserIds);

    if (isLiked) {
      newLikedUserIds.remove(userId);
    } else {
      newLikedUserIds.add(userId);
    }

    return copyWith(
      likedUserIds: newLikedUserIds,
      likeCount: newLikedUserIds.length,
      updatedAt: DateTime.now(),
    );
  }

  // いいねしているかチェック
  bool isLikedBy(String userId) {
    return likedUserIds.contains(userId);
  }
}
