import 'package:cloud_firestore/cloud_firestore.dart';
import 'track_model.dart';
import 'post_theme.dart';

/// 投稿の公開範囲。
/// - `public`: 全ユーザーに公開（既定）
/// - `followers`: 投稿者をフォローしているユーザーのみ閲覧可
class PostAudience {
  static const String public = 'public';
  static const String followers = 'followers';

  /// Firestore 値が null/未知のときは public として扱う（既存投稿の後方互換）。
  static String normalize(dynamic value) {
    if (value == followers) return followers;
    return public;
  }
}

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
  /// ナビバー投稿ボタン → Music Memory モーダル経由で作成された
  /// 「気分で投稿」フラグ。true の投稿はストーリーバーに載せない。
  final bool isMoodPost;
  /// true のとき、PostCard 裏面はユーザー情報バッジ・歌詞カード・楽曲情報バー
  /// などの overlay を一切描画せず、photoUrl を BoxFit.cover で全面表示する。
  /// Vibe ストーリーで「写真なし = プレビューをキャプチャして photo として上げる」
  /// フローで使う。
  final bool hideBackOverlays;
  final String? vibeTopicId; // 参加しているお題のID
  final String? vibeTopicTitle; // Vibeお題のタイトル（例: "ドライブで聴きたい曲"）
  final DateTime? vibeDate; // Vibe投稿の日付（集計用）
  /// Music Memory 投稿サイクルの開始時刻（作成時点の通知時刻 notifiedAt）。
  /// タイムライン表示・Late 判定の基準。Music Memory 投稿以外は null。
  final DateTime? cycleStart;
  /// このサイクルの締切（翌1:00）を過ぎて投稿された「Late 投稿」か。
  final bool isLate;
  final String? emotionTag; // 感情タグ（例: "嬉しい", "悲しい", "楽しい"）
  final String? lyricsText; // 歌詞テキスト（歌詞カード表示用）
  final int audioStartMs; // 音楽再生開始位置（ミリ秒）
  final int audioDurationSec; // 音楽再生時間（秒）
  final String? university; // 投稿者の大学名（Campus Vibe用）
  final bool campusVibeParticipating; // Campus Vibe参加フラグ（デフォルトtrue）
  final bool campusVibePost; // Campus Vibe参加投稿フラグ（作成時確定・変更不可）
  final String? adlTeamId; // ADL班タグ
  /// ADL集計対象として「班員の投稿」と扱うか。
  /// Cloud Functionが「1人1日1投稿」ルールで初回投稿のみtrueにする。
  /// null（フラグ未設定）の場合はレガシー投稿として扱い、UIは表示する。
  final bool? countsForAdl;
  /// 公開範囲（`PostAudience.public` または `PostAudience.followers`）。
  /// 投稿時に確定し、後から変更不可。既存投稿（フィールドなし）は `public` 扱い。
  final String audience;

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
    this.isMoodPost = false,
    this.hideBackOverlays = false,
    this.vibeTopicId,
    this.vibeTopicTitle,
    this.vibeDate,
    this.cycleStart,
    this.isLate = false,
    this.emotionTag,
    this.lyricsText,
    this.audioStartMs = 0,
    this.audioDurationSec = 15,
    this.university,
    this.campusVibeParticipating = true,
    this.campusVibePost = false,
    this.adlTeamId,
    this.countsForAdl,
    this.audience = PostAudience.public,
  });

  // Firestoreドキュメントから作成
  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    List<String> safeStringList(String key) =>
        (data[key] as List<dynamic>? ?? []).whereType<String>().toList();

    final now = DateTime.now();
    DateTime safeTimestamp(String key) {
      final val = data[key];
      return val is Timestamp ? val.toDate() : now;
    }

    DateTime? safeTimestampOrNull(String key) {
      final val = data[key];
      return val is Timestamp ? val.toDate() : null;
    }

    return PostModel(
      postId: doc.id,
      userId: data['userId']?.toString() ?? '',
      username: data['username']?.toString() ?? '',
      userIconUrl: data['userIconUrl']?.toString(),
      // track フィールドが Map 以外の型で保存されていた場合も空Mapにフォールバック
      track: TrackModel.fromMap(
          data['track'] is Map<String, dynamic>
              ? data['track'] as Map<String, dynamic>
              : {}),
      likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (data['commentCount'] as num?)?.toInt() ?? 0,
      likedUserIds: safeStringList('likedUserIds'),
      likedByUserIconUrls: safeStringList('likedByUserIconUrls'),
      savedByUserIds: safeStringList('savedByUserIds'),
      savedByUserIconUrls: safeStringList('savedByUserIconUrls'),
      createdAt: safeTimestamp('createdAt'),
      updatedAt: safeTimestamp('updatedAt'),
      // theme が Map 以外の型だった場合はデフォルトテーマにフォールバック
      theme: data['theme'] is Map<String, dynamic>
          ? PostTheme.fromMap(data['theme'] as Map<String, dynamic>)
          : PostTheme.defaultTheme,
      photoUrl: data['photoUrl']?.toString(),
      imageOffsetX: (data['imageOffsetX'] as num?)?.toDouble() ?? 0.0,
      imageOffsetY: (data['imageOffsetY'] as num?)?.toDouble() ?? 0.0,
      imageScale: (data['imageScale'] as num?)?.toDouble() ?? 1.0,
      imageNaturalWidth: (data['imageNaturalWidth'] as num?)?.toDouble() ?? 0.0,
      imageNaturalHeight: (data['imageNaturalHeight'] as num?)?.toDouble() ?? 0.0,
      selectedLayoutIndex: (data['selectedLayoutIndex'] as num?)?.toInt() ?? 0,
      cardPositionX: (data['cardPositionX'] as num?)?.toDouble() ?? 0.0,
      cardPositionY: (data['cardPositionY'] as num?)?.toDouble() ?? 0.0,
      cardScale: (data['cardScale'] as num?)?.toDouble() ?? 1.0,
      cardRotation: (data['cardRotation'] as num?)?.toDouble() ?? 0.0,
      isVibe: data['isVibe'] == true,
      isMoodPost: data['isMoodPost'] == true,
      hideBackOverlays: data['hideBackOverlays'] == true,
      vibeTopicId: data['vibeTopicId']?.toString(),
      vibeTopicTitle: data['vibeTopicTitle']?.toString(),
      vibeDate: safeTimestampOrNull('vibeDate'),
      cycleStart: safeTimestampOrNull('cycleStart'),
      isLate: data['isLate'] == true,
      emotionTag: data['emotionTag']?.toString(),
      lyricsText: data['lyricsText']?.toString(),
      audioStartMs: (data['audioStartMs'] as num?)?.toInt() ?? 0,
      audioDurationSec: (data['audioDurationSec'] as num?)?.toInt() ?? 15,
      university: data['university']?.toString(),
      // null の場合デフォルト true、false が明示されている場合のみ false
      campusVibeParticipating: data['campusVibeParticipating'] != false,
      campusVibePost: data['campusVibePost'] == true,
      adlTeamId: data['adlTeamId']?.toString(),
      countsForAdl: data['countsForAdl'] is bool
          ? data['countsForAdl'] as bool
          : null,
      audience: PostAudience.normalize(data['audience']),
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
      'isMoodPost': isMoodPost,
      'hideBackOverlays': hideBackOverlays,
      'vibeTopicId': vibeTopicId,
      'vibeTopicTitle': vibeTopicTitle,
      'vibeDate': vibeDate != null ? Timestamp.fromDate(vibeDate!) : null,
      'cycleStart': cycleStart != null ? Timestamp.fromDate(cycleStart!) : null,
      'isLate': isLate,
      'emotionTag': emotionTag,
      'lyricsText': lyricsText,
      'audioStartMs': audioStartMs,
      'audioDurationSec': audioDurationSec,
      'university': university,
      'campusVibeParticipating': campusVibeParticipating,
      'adlTeamId': adlTeamId,
      'audience': audience,
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
    bool? isMoodPost,
    bool? hideBackOverlays,
    String? vibeTopicId,
    String? vibeTopicTitle,
    DateTime? vibeDate,
    DateTime? cycleStart,
    bool? isLate,
    String? emotionTag,
    String? lyricsText,
    int? audioStartMs,
    int? audioDurationSec,
    String? university,
    bool? campusVibeParticipating,
    String? adlTeamId,
    bool? countsForAdl,
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
      isMoodPost: isMoodPost ?? this.isMoodPost,
      hideBackOverlays: hideBackOverlays ?? this.hideBackOverlays,
      vibeTopicId: vibeTopicId ?? this.vibeTopicId,
      vibeTopicTitle: vibeTopicTitle ?? this.vibeTopicTitle,
      vibeDate: vibeDate ?? this.vibeDate,
      cycleStart: cycleStart ?? this.cycleStart,
      isLate: isLate ?? this.isLate,
      emotionTag: emotionTag ?? this.emotionTag,
      lyricsText: lyricsText ?? this.lyricsText,
      audioStartMs: audioStartMs ?? this.audioStartMs,
      audioDurationSec: audioDurationSec ?? this.audioDurationSec,
      university: university ?? this.university,
      campusVibeParticipating: campusVibeParticipating ?? this.campusVibeParticipating,
      campusVibePost: this.campusVibePost,
      adlTeamId: adlTeamId ?? this.adlTeamId,
      countsForAdl: countsForAdl ?? this.countsForAdl,
      // audience は投稿時に確定（後から変更不可）
      audience: this.audience,
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
