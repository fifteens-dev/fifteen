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

  bool get isPosting => _isPosting;
  PostingCardData? get cardData => _cardData;

  void startPosting(PostingCardData data) {
    _isPosting = true;
    _cardData = data;
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
