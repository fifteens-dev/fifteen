import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import '../models/track_model.dart';
import 'lyrics_service.dart';

/// アップロード中にオーバーレイでカードを再現するためのスナップショット
class PostingCardData {
  final TrackModel track;
  final String username;
  final String? userIconUrl;
  final XFile? selectedImage;
  final Offset imageOffset;
  final double imageScale;
  final Size? imageNaturalSize;
  final int selectedLayoutIndex;
  final Offset cardCenter; // 歌詞カードの中心座標（363×645ローカル座標系）
  final double cardScale;
  final double cardRotation;
  final LyricsData? lyricsData;
  final double albumArtOpacity;
  final Color? gradientStart;
  final Color? gradientEnd;
  final String? previewUrl;
  final int audioStartMs;
  final int audioDurationSec;
  final bool isVibe;
  final String? vibeTopicTitle;
  final String? adlTeamId;
  /// 「1人1日1投稿」ルール上、この投稿が班員投稿として扱われる予定か。
  /// false の場合は裏面右上の @◯◯ を非表示にする。
  final bool willCountForAdl;

  const PostingCardData({
    required this.track,
    required this.username,
    this.userIconUrl,
    this.selectedImage,
    this.imageOffset = Offset.zero,
    this.imageScale = 1.0,
    this.imageNaturalSize,
    this.selectedLayoutIndex = 0,
    this.cardCenter = const Offset(181.5, 290.25),
    this.cardScale = 1.0,
    this.cardRotation = 0.0,
    this.lyricsData,
    this.albumArtOpacity = 1.0,
    this.gradientStart,
    this.gradientEnd,
    this.previewUrl,
    this.audioStartMs = 0,
    this.audioDurationSec = 15,
    this.isVibe = false,
    this.vibeTopicTitle,
    this.adlTeamId,
    this.willCountForAdl = true,
  });
}

/// 投稿アップロード中の状態を全画面で共有するシングルトン。
///
/// post_final_preview_screen が遷移前に startPosting() を呼び、
/// バックグラウンドアップロード完了後に finishPosting() を呼ぶ。
/// home_screen はこれを ListenableBuilder で購読してオーバーレイを表示する。
class PostingState extends ChangeNotifier {
  static final instance = PostingState._();
  PostingState._();

  bool _isPosting = false;
  PostingCardData? _cardData;
  OverlayEntry? _overlayEntry;

  /// 直近で `startPosting` を呼んだ日付（端末ローカル）。
  /// 1投稿目のアップロード中に2投稿目フローへ進むケースで、
  /// Firestore 反映前でも「今日もう開始した」と判定するために使う。
  DateTime? _lastPostStartedDate;

  bool get isPosting => _isPosting;
  PostingCardData? get cardData => _cardData;

  /// 今セッションで本日中に投稿開始したか。
  /// Firestore 反映ラグを補うフォールバック判定として使う。
  bool get hasStartedPostToday {
    final last = _lastPostStartedDate;
    if (last == null) return false;
    final now = DateTime.now();
    return last.year == now.year &&
        last.month == now.month &&
        last.day == now.day;
  }

  void startPosting(PostingCardData data) {
    _isPosting = true;
    _cardData = data;
    _lastPostStartedDate = DateTime.now();
    notifyListeners();
  }

  void setOverlayEntry(OverlayEntry entry) {
    _overlayEntry = entry;
  }

  void finishPosting() {
    _isPosting = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
    notifyListeners();
  }
}
