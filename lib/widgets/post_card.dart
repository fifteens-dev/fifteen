import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'animated_waveform.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import '../constants/adl_teams.dart';
import '../models/post_model.dart';
import '../models/post_theme.dart';
import '../screens/adl_team_playlist_screen.dart';
import '../screens/artist_profile_screen.dart';
import '../screens/other_user_profile_screen.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/lyrics_service.dart';
import '../services/post_service.dart';
import '../utils/album_image.dart';
import '../utils/color_extractor.dart';
import '../utils/photo_helper.dart';
import 'profile_widgets.dart';
import 'post_creation/lyrics_card_layouts.dart';
import 'post_card/post_card_constants.dart';
import 'post_card/marquee_text.dart';
import 'dialogs/restriction_notification.dart';
import 'dialogs/report_dialog.dart';
import 'native_pull_down_button.dart';
import 'package:photo_manager/photo_manager.dart';
import 'common/app_toast.dart';
import 'reaction_overlay.dart';

part 'post_card/mixins/post_card_color_mixin.dart';
part 'post_card/mixins/post_card_lyrics_mixin.dart';
part 'post_card/mixins/post_card_audio_mixin.dart';
part 'post_card/mixins/post_card_like_mixin.dart';
part 'post_card/mixins/post_card_reaction_mixin.dart';

/// 投稿カードウィジェット（表裏反転アニメーション付き）
class PostCard extends StatefulWidget {
  final PostModel post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  /// 絵文字リアクションが選ばれたときのコールバック（新リアクションUI）。
  final void Function(String emoji)? onReaction;
  final VoidCallback? onAdd;
  final VoidCallback? onDelete;
  final String? currentUserId;
  final String? currentUserIconUrl; // 現在のユーザーのアイコンURL（楽観的UI用）
  final AudioPlayerService audioService; // 音楽再生サービス（外部から注入）
  final bool showFrontOnly; // trueの場合、表面のみ表示（反転なし）
  final VoidCallback? onCardTap; // showFrontOnly時の外部タップハンドラ
  final bool isSaved; // 保存済みかどうか
  final bool hideReactionCounts; // trueの場合、リアクション数を非表示（プレビュー用）
  final bool hideAudienceBadge; // trueの場合、公開範囲バッジ（globe/lock）を非表示（投稿フロー中）
  // trueの場合、表裏ともコメント入力バーを非表示にし、その分の空きに合わせて
  // 表面=内容を中央寄りに再配置 / 裏面=文字を下へスライド（Music Memory・共有プレビュー用）。
  final bool hideCommentBar;
  // trueの場合、カード上の共有ボタン（表裏とも）を非表示（Music Memory 詳細画面用。
  // 共有はヘッダー側のボタンから行う）。
  final bool hideShareButton;
  final Color? preExtractedGradientStart; // 事前抽出されたグラデーション開始色
  final Color? preExtractedGradientEnd; // 事前抽出されたグラデーション終了色
  final bool autoFlipAfterDelay; // trueの場合、0.5秒後に自動で裏返す
  final bool startFromBack; // trueの場合、裏面から開始（表面への反転時に音楽再生）
  final VoidCallback? onPlayStarted; // 音楽再生開始時のコールバック
  final String? externalPreviewUrl; // 外部から渡されるプレビューURL（waveform用）
  final bool backSideEnabled; // falseの場合、裏面に反転しない
  final bool disableInteractions; // trueの場合、いいね・コメント無効（カウントのみ表示）
  final bool autoPlay; // trueの場合、裏面スタート時に自動で音楽を再生
  final bool audioManagedExternally; // trueの場合、音楽制御を外部（プロフィール画面等）に委譲
  final VoidCallback? onFlipToBack; // 初めて裏面に反転したときのコールバック（閲覧済み記録用）
  final VoidCallback? onShare; // 共有ボタンタップ時のコールバック（未指定時はPNG保存）
  // trueの場合、カードタップで内部反転せず onCardTap を呼ぶだけにする。
  // 反転は親が flipToBack()/flipToFront() で制御する（ホーム2列グリッド用）。
  final bool externalFlipControl;

  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onReaction,
    this.onAdd,
    this.onDelete,
    this.currentUserId,
    this.currentUserIconUrl,
    required this.audioService, // 必須パラメータ
    this.showFrontOnly = false, // デフォルトは両面表示
    this.onCardTap, // 外部タップハンドラ（オプション）
    this.isSaved = false, // デフォルトは未保存
    this.hideReactionCounts = false, // デフォルトはカウント表示
    this.hideAudienceBadge = false, // デフォルトはバッジ表示（投稿完了後の通常カード）
    this.hideCommentBar = false, // デフォルトはコメントバー表示
    this.hideShareButton = false, // デフォルトはカード上の共有ボタン表示
    this.preExtractedGradientStart, // 事前抽出された色（オプション）
    this.preExtractedGradientEnd, // 事前抽出された色（オプション）
    this.autoFlipAfterDelay = false, // デフォルトは自動反転なし
    this.startFromBack = false, // デフォルトは表面から開始
    this.onPlayStarted, // 再生開始通知（オプション）
    this.externalPreviewUrl, // 外部プレビューURL（オプション）
    this.backSideEnabled = true, // デフォルトは裏面反転可能
    this.disableInteractions = false, // デフォルトはインタラクション有効
    this.autoPlay = false, // デフォルトは自動再生なし
    this.audioManagedExternally = false, // デフォルトはPostCard内部で音楽制御
    this.onFlipToBack, // 裏面反転コールバック（オプション）
    this.onShare, // 共有コールバック（オプション）
    this.externalFlipControl = false, // デフォルトは内部で反転制御
  });

  @override
  State<PostCard> createState() => PostCardState();
}

class PostCardState extends State<PostCard>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // コメント機能の表示スイッチ。false でコメントボタン/バーを非表示（接続を切る）。
  // 復活させるときは true に戻すだけ（コード自体は残している）。
  static const bool kCommentsEnabled = false;

  // ── 絵文字リアクション用の状態 ──────────────────────────
  OverlayEntry? _reactionPickerEntry; // ピッカー吹き出し
  OverlayEntry? _reactionBurstEntry; // 選択直後のふわっと上がるアニメ
  Rect? _reactionAnchorRect; // スマイルボタンのグローバル矩形（吹き出し/バースト位置）
  String? _reactionOverride; // 楽観的リアクション（null=解除）
  bool _hasReactionOverride = false; // 楽観的上書きが有効か

  /// コメント機能を切っている間は「コメントバー無し」レイアウト（Figma 5111:10598）で
  /// 楽曲情報エリアを配置する（コメントバーの隙間分を詰めて波形などを正位置に）。
  bool get _effHideCommentBar => widget.hideCommentBar || !kCommentsEnabled;

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _showFront = true;

  // カードキャプチャ用
  final GlobalKey _cardRepaintKey = GlobalKey();

  // 裏面無効タップ時のリジェクトシェイク用
  late AnimationController _rejectController;
  late Animation<double> _rejectAnimation;

  // 楽観的UI更新用のローカル状態
  bool? _isLikedOptimistic;
  int? _likeCountOptimistic;
  List<String>? _likedByUserIconUrlsOptimistic;

  // サービス
  final ITunesSearchService _itunesService = ITunesSearchService();
  final LyricsService _lyricsService = LyricsService();
  final PostService _postService = PostService();

  // 動的に取得したpreview URLをキャッシュ
  String? _cachedPreviewUrl;

  /// 表示するアルバムアートURL（Spotifyから取得したものを使用）
  String get _displayAlbumArtUrl => widget.post.track.albumImageUrl;

  /// 裏面に写真が設定されているかチェック
  bool get _hasBackPhoto {
    return widget.post.photoUrl != null && widget.post.photoUrl!.isNotEmpty;
  }

  /// photoUrlがネットワークURL（https://）かどうかをチェック
  bool get _isPhotoUrlNetwork {
    if (!_hasBackPhoto) return false;
    return PhotoHelper.isNetworkUrl(widget.post.photoUrl!);
  }

  /// photoUrlがData URL（Base64）かどうかをチェック
  bool get _isPhotoUrlDataUrl {
    if (!_hasBackPhoto) return false;
    return PhotoHelper.isDataUrl(widget.post.photoUrl!);
  }

  // Base64写真のデコードキャッシュ
  Uint8List? _decodedPhotoBytes;
  String? _decodedPhotoUrl;

  // 裏面スクリーンショット用

  // アルバムアートから抽出した色
  Color? _extractedGradientStart;
  Color? _extractedGradientEnd;
  bool _isColorExtracting = false;

  // 動的に取得した歌詞
  String? _fetchedLyricsText;
  bool _isLyricsFetching = false;
  bool _lyricsFetchAttempted = false;

  // BPM
  double? _tempo;

  // 音楽再生の二重呼び出し防止フラグ
  bool _isPlayAudioInProgress = false;

  // スクロール時にウィジェットの状態を保持
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _initializeAnimations();
    _initializeColors();
    _tempo = widget.post.track.tempo;

    // 裏面から開始モード
    if (widget.startFromBack) {
      _showFront = false;
      _flipController.value = 1.0; // アニメーションなしで裏面を表示
    }

    // 自動再生が有効な場合、裏面スタートでビルド後に音楽を再生
    // （外部制御モードの場合はPostCardが音楽を再生しない）
    if (widget.startFromBack && widget.autoPlay && !widget.audioManagedExternally) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onPlayStarted?.call(); // 再生開始を親に通知（スクロール管理用）
          _playAudioAsync();
        }
      });
    }

    // 自動反転が有効な場合、0.5秒後に裏返す
    if (widget.autoFlipAfterDelay && !widget.startFromBack) {
      Future.delayed(PostCardConstants.autoFlipDelay, () {
        if (mounted && _showFront) {
          _flipCard();
        }
      });
    }
  }

  /// アニメーションの初期化
  void _initializeAnimations() {
    // カード反転アニメーション
    _flipController = AnimationController(
      duration: PostCardConstants.flipAnimationDuration,
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );

    // 裏面無効タップ時のリジェクトシェイクアニメーション（カチカチ）
    // 裏面無効タップ時のピーク反転アニメーション
    // 少しだけ反転しかけて弾むように戻る
    _rejectController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _rejectAnimation = TweenSequence<double>([
      // 前半: 約14度まで素早く反転しかける
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.08)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      // 後半: elasticOutでバウンドしながら戻る
      TweenSequenceItem(
        tween: Tween(begin: 0.08, end: 0.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 70,
      ),
    ]).animate(_rejectController);
  }


  @override
  void dispose() {
    _clearReactionOverlays();
    _flipController.dispose();
    _rejectController.dispose();
    super.dispose();
  }

  /// 表面に戻す（外部から呼び出し可能）
  void flipToFront() {
    if (!mounted || _showFront) return;
    setState(() { _showFront = true; });
    _flipController.reverse();
  }

  /// 裏面に戻す（外部から呼び出し可能）。
  /// [playAudio] が true の場合、裏面反転と同時に音楽を再生し、裏面閲覧記録
  /// （onFlipToBack）も通知する（ホーム2列グリッドのタップ拡大用）。
  /// 既存の呼び出し元（音楽を外部管理する画面）は playAudio=false のまま影響を受けない。
  void flipToBack({bool playAudio = false}) {
    if (!mounted || !_showFront) return;
    setState(() { _showFront = false; });
    _flipController.forward();
    if (playAudio) {
      widget.onFlipToBack?.call();
      if (!widget.audioManagedExternally) {
        widget.onPlayStarted?.call();
        _playAudioAsync();
      }
    }
  }

  /// カードをタップして裏返す
  void _flipCard() async {
    // 外部反転制御モード: 反転せず外部ハンドラのみ呼ぶ（親が flip を制御）。
    if (widget.externalFlipControl) {
      widget.onCardTap?.call();
      return;
    }

    // 表面のみ表示モードの場合は外部ハンドラを呼ぶ
    if (widget.showFrontOnly) {
      widget.onCardTap?.call();
      return;
    }

    // 裏面無効の場合、表面→裏面への反転をブロック（カチカチシェイクで拒否を表現）
    // 音楽は再生する
    if (!widget.backSideEnabled && _showFront) {
      HapticFeedback.heavyImpact();
      _rejectController.forward(from: 0.0);
      RestrictionNotification.show(context, message: '投稿して表示\nあなたのVibeをシェアして\n友達の投稿をみよう');
      if (!widget.audioManagedExternally) {
        widget.onPlayStarted?.call();
        _playAudioAsync();
      }
      return;
    }

    // 触覚フィードバック
    HapticFeedback.mediumImpact();

    // 状態を先に更新してUIを即座に反映
    setState(() {
      _showFront = !_showFront;
    });

    if (!_showFront) {
      // 裏面に反転 → 閲覧済みとして記録
      widget.onFlipToBack?.call();

      _flipController.forward();

      // 外部制御モードでない場合のみPostCardが音楽を再生
      if (!widget.audioManagedExternally) {
        widget.onPlayStarted?.call();
        _playAudioAsync();
      }
    } else {
      // 表面に反転
      _flipController.reverse();

      // startFromBackモード: 外部制御でない場合のみ音楽再生
      if (widget.startFromBack && !widget.audioManagedExternally) {
        widget.onPlayStarted?.call();
        _playAudioAsync();
      }
    }
  }

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.post.postId != widget.post.postId) {
      _clearLikeOptimistic();
      _clearReactionOptimistic();
      _clearReactionOverlays();
    } else {
      _syncLikeOptimisticWithActual();
      _syncReactionOptimistic();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixinのために必要

    return Center(
      child: SizedBox(
        width: 363.0,
        height: 645.0,
        child: RepaintBoundary(
          key: _cardRepaintKey,
          child: widget.showFrontOnly
              ? _buildFront() // 表面のみ表示（反転アニメーションなし）
              : AnimatedBuilder(
                  animation: Listenable.merge([_flipAnimation, _rejectAnimation]),
                  builder: (context, child) {
                    final flipAngle = _flipAnimation.value * pi;
                    final peekAngle = _rejectAnimation.value * pi;
                    final totalAngle = flipAngle + peekAngle;
                    final isFront = totalAngle.abs() < pi / 2;

                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001)
                        ..rotateY(totalAngle),
                      child: isFront ? _buildFront() : _buildBack(),
                    );
                  },
                ),
        ),
      ),
    );
  }

  /// カード表面（アルバムカバー全表示）
  Widget _buildFront() {
    final theme = _getDynamicTheme();

    return GestureDetector(
      onTap: _flipCard,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 実際のレンダリングサイズを使用（制約を受けた場合でも正確）
          final cardWidth = constraints.maxWidth > 0 ? constraints.maxWidth : 363.0;
          final cardHeight = constraints.maxHeight > 0 ? constraints.maxHeight : 645.0;
          final albumSize = cardWidth; // アルバムカバーは正方形（カード幅と同じ）
          final contentHeight = cardHeight * (295.0 / 645.0); // タイトルエリア

          return Container(
            width: cardWidth,
            height: cardHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PostCardConstants.cardBorderRadius),
              color: theme.gradientEnd,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(PostCardConstants.cardBorderRadius),
              child: Stack(
            children: [
              // アルバムカバー（全表示）
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  width: albumSize,
                  height: albumSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: _displayAlbumArtUrl.isNotEmpty
                      ? _buildAlbumArt(
                          _displayAlbumArtUrl,
                          fit: BoxFit.cover,
                          errorWidget: _buildAlbumPlaceholder(),
                        )
                      : _buildAlbumPlaceholder(),
                ),
              ),

              // 公開範囲バッジ（地球儀/鍵）は廃止。投稿は自動でフォロワー限定判定のため不要。

              // グラデーションオーバーレイ（下部3/7）
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: contentHeight,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.gradientStart
                            .withOpacity(0.0), // 上端は透明（アルバムと重なる部分）
                        theme.gradientEnd, // 13px以降は不透明
                      ],
                      stops: const [
                        0.0,
                        0.0442
                      ], // 上部4.42% (13px/294px) でグラデーション完了
                    ),
                  ),
                ),
              ),

              // コンテンツ（下部）- Figmaに合わせて絶対配置
              // Figmaは下から計測（Y軸反転）なので、294px基準で変換
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: contentHeight,
                child: Stack(
                  children: [
                    // ユーザー情報 - Figma: bottom: 238px → top: 56px (294-238), left: 12px
                    Positioned(
                      left: cardWidth * (12 / 363),
                      top: contentHeight * (24 / 294),
                      child: _buildUserInfo(theme),
                    ),

                    // 曲名とアーティスト名 - ボタン有無で right を動的調整
                    // menu(32) + rightMargin(11) = 43px
                    // hideCommentBar 時はコメントバー分を詰めて中央寄りに(Figma 4947:10749)。
                    Positioned(
                      left: cardWidth * (11 / 363),
                      top: contentHeight * ((_effHideCommentBar ? 79 : 63) / 294),
                      right: _showMoreButton
                          ? cardWidth * (43 / 363)
                          : cardWidth * (12 / 363),
                      child: _buildTrackInfo(theme),
                    ),

                    // 共有ボタン（3点メニューのすぐ左・自分の投稿のみ）
                    if (_isOwner && !widget.hideShareButton)
                      Positioned(
                        right: cardWidth * (47 / 363),
                        top: contentHeight * (63 / 294),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onShare ?? _handleShare,
                          child: () {
                            final hsl = HSLColor.fromColor(theme.gradientEnd);
                            final newL = hsl.lightness > 0.5
                                ? (hsl.lightness - 0.1).clamp(0.0, 1.0)
                                : (hsl.lightness + 0.1).clamp(0.0, 1.0);
                            return Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: hsl.withLightness(newL).toColor(),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Image.asset(
                                  'assets/icons/share_button.png',
                                  width: 36,
                                  height: 36,
                                  color: theme.textColor,
                                  colorBlendMode: BlendMode.srcIn,
                                ),
                              ),
                            );
                          }(),
                        ),
                      ),

                    // 3点メニューボタン
                    if (_showMoreButton)
                    Positioned(
                      right: cardWidth * (11 / 363),
                      top: contentHeight * (63 / 294),
                      child: _buildMoreButton(theme),
                    ),

                    // リアクション行 - Figma 5111/4947: top 153px, スマイル left12 /
                    // プラス left82、リアクションアバターは右端 x348（right 15px）。
                    Positioned(
                      left: cardWidth * (12 / 363),
                      right: cardWidth * (15 / 363),
                      top: contentHeight * ((_effHideCommentBar ? 153 : 128) / 294),
                      child: _buildReactions(theme),
                    ),

                    // 音楽波形 - Figma 5111:10598: left 18px, top 205px（コメントバー無し時）
                    Positioned(
                      left: cardWidth * (18 / 363),
                      top: contentHeight * ((_effHideCommentBar ? 205 : 166) / 294),
                      child: _buildWaveform(theme),
                    ),

                    // コメント入力欄 - コメント機能を切っている間は非表示。
                    if (kCommentsEnabled && !widget.hideCommentBar)
                      Positioned(
                        left: cardWidth * (12 / 363),
                        right: cardWidth * (12 / 363),
                        top: contentHeight * (211 / 294),
                        child: _buildCommentButton(theme),
                      ),

                    // "Provided courtesy of Apple Music" - Figma: bottom: 12px → top: 282px (294-12), left: 17px
                    Positioned(
                      left: cardWidth * (17 / 363),
                      top: contentHeight * (268 / 294),
                      child: Text(
                        'Provided courtesy of Apple Music',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.secondaryTextColor.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
        },
      ),
    );
  }

  /// カード裏面（写真+アルバムカード+下部セクション）
  Widget _buildBack() {
    final theme = _getDynamicTheme();

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(pi),
      child: GestureDetector(
        onTap: _flipCard,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth > 0 ? constraints.maxWidth : 363.0;
            final cardHeight = constraints.maxHeight > 0 ? constraints.maxHeight : 645.0;
            return _buildBackCardBody(cardWidth, cardHeight, theme);
          },
        ),
      ),
    );
  }

  /// 裏面カード本文（トランスフォームなし）- キャプチャ・表示共用
  Widget _buildBackCardBody(double cardWidth, double cardHeight, PostTheme theme) {
    // hideBackOverlays: 写真自体にプレビュー全体 (歌詞カード / ユーザー badge / 楽曲情報) が
    // 焼き込まれているケース (Vibe ストーリー写真なし投稿)。二重描画を避けるため、
    // ユーザー情報・歌詞カード・楽曲情報等の overlay を一切乗せず、写真だけ全面表示。
    if (widget.post.hideBackOverlays) {
      return Container(
        width: cardWidth,
        height: cardHeight,
        color: const Color(0xFF121212),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PostCardConstants.cardBorderRadius),
          child: _buildPhotoArea(cardWidth, cardHeight),
        ),
      );
    }

    final isLiked = _isLikedOptimistic ??
        (widget.currentUserId != null && widget.post.isLikedBy(widget.currentUserId!));

    return Container(
      width: cardWidth,
      height: cardHeight,
      color: const Color(0xFF121212),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PostCardConstants.cardBorderRadius),
        child: Stack(
          children: [
            // 写真（カード全体に高さ基準でフィット）
            Positioned.fill(
              child: _buildPhotoArea(cardWidth, cardHeight),
            ),

            // ユーザー情報（左上）
            Positioned(
              left: 23,
              top: 18,
              child: _buildUserInfoTopLeft(theme),
            ),

            // 班ハンドル（右上）- ユーザーアイコンと垂直中央を揃える
            Positioned(
              right: 23,
              top: 18,
              height: 32,
              child: Align(
                alignment: Alignment.centerRight,
                child: _buildTeamHandleTopRight(),
              ),
            ),

            // 歌詞カード
            _buildLyricsCardOverlay(),

            // 下部グラデーション（テキスト可読性）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: cardHeight * (174.0 / 645.0),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x80000000)],
                  ),
                ),
              ),
            ),

            // 曲名とアーティスト名。共有・3点メニューと同じ高さ(88)に揃える。
            Positioned(
              left: cardWidth * (11 / 363),
              right: _isOwner
                  ? cardWidth * (84 / 363)
                  : cardWidth * (12 / 363),
              bottom: cardHeight * ((_effHideCommentBar ? 88 : 110) / 645),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  MarqueeText(
                    textSpan: _buildWeightAdjustedSpan(
                      widget.post.track.trackName,
                      baseStyle: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    width: _isOwner
                        ? cardWidth * (268 / 363)
                        : cardWidth * (340 / 363),
                  ),
                  const SizedBox(height: 1.198),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ArtistProfileScreen(
                          artistName: widget.post.track.artistName,
                          spotifyArtistId: widget.post.track.spotifyArtistId,
                        ),
                      ),
                    ),
                    child: Opacity(
                      opacity: 0.8,
                      child: _buildWeightAdjustedText(
                        widget.post.track.artistName,
                        fontSize: 11,
                        baseWeight: FontWeight.w400,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // リアクション（スマイル＝絵文字リアクション ＋ 追加/保存）
            Positioned(
              left: cardWidth * (12 / 363),
              bottom: cardHeight * ((_effHideCommentBar ? 42 : 80) / 645),
              child: Row(
                children: [
                  _buildSmileyButton(
                      size: cardWidth * (28 / 363), color: Colors.white),
                  SizedBox(width: cardWidth * (34 / 363)),
                  // コメント機能は接続を切っている（kCommentsEnabled=false で復活可）。
                  if (kCommentsEnabled) ...[
                    _buildCommentReactionBack(
                      count: widget.post.commentCount,
                      onTap: widget.disableInteractions
                          ? () => RestrictionNotification.show(context,
                              message: 'コメントができません')
                          : widget.onComment,
                    ),
                    SizedBox(width: cardWidth * (34 / 363)),
                  ],
                  _buildSaveButton(
                      theme: theme,
                      color: Colors.white,
                      size: cardWidth * (28 / 363)),
                ],
              ),
            ),

            // リアクションしたユーザーのアバター＋絵文字（右側）
            if (!widget.hideReactionCounts)
              Positioned(
                right: cardWidth * (12 / 363),
                bottom: cardHeight * ((_effHideCommentBar ? 42 : 80) / 645),
                child: _buildReactorAvatarsFront(cardWidth, cardHeight),
              ),

            // コメントボタン（半透明黒背景）— コメント機能を切っている間は非表示。
            if (kCommentsEnabled && !widget.hideCommentBar)
              Positioned(
                left: cardWidth * (12 / 363),
                right: cardWidth * (12 / 363),
                bottom: cardHeight * (28 / 645),
                child: _buildCommentButtonBack(),
              ),

            // "Provided courtesy of Apple Music"
            Positioned(
              left: cardWidth * (17 / 363),
              bottom: cardHeight * (9 / 645),
              child: const Text(
                'Provided courtesy of Apple Music',
                style: TextStyle(fontSize: 10, color: Color(0xFFB0B0B0)),
              ),
            ),

            // 共有ボタン（自分の投稿のみ）。タイトルと同じ高さ(88)。
            if (_isOwner && !widget.hideShareButton)
              Positioned(
                right: cardWidth * (47 / 363),
                bottom: cardHeight * ((_effHideCommentBar ? 88 : 110) / 645),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onShare ?? _handleShare,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/icons/share_button.png',
                        width: 36,
                        height: 36,
                        color: Colors.white,
                        colorBlendMode: BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),

            // 3点メニューボタン（裏面）。タイトル・共有と同じ高さ(88)。
            if (_showMoreButton)
              Positioned(
                right: cardWidth * (11 / 363),
                bottom: cardHeight * ((_effHideCommentBar ? 88 : 110) / 645),
                child: _buildMoreButton(theme, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  /// 裏面用コメントボタン（半透明黒背景・白テキスト）
  Widget _buildCommentButtonBack() {
    if (widget.disableInteractions) {
      return GestureDetector(
        onTap: () => RestrictionNotification.show(context, message: 'コメントができません'),
        child: Opacity(
          opacity: 0.35,
          child: Container(
            height: 43,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                SizedBox(width: 12),
                Text(
                  'コメントする',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: widget.onComment,
      child: Container(
        height: 43,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Text(
              'コメントする',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            Image.asset(
              'assets/icons/comment_send_button.png',
              width: 20,
              height: 20,
              color: Colors.white.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  /// アルバムアート表示。ネットワークURLは従来通り [CachedNetworkImage]、
  /// data URI / ローカルファイル（今再生中のローカル/取り込み曲の埋め込みアート）は
  /// [Image] で描画する。
  Widget _buildAlbumArt(String url,
      {required BoxFit fit, required Widget errorWidget}) {
    if (isLocalAlbumArt(url)) {
      return Image(
        image: albumImageProvider(url),
        fit: fit,
        errorBuilder: (_, __, ___) => errorWidget,
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      errorWidget: (_, __, ___) => errorWidget,
    );
  }

  /// アルバムプレースホルダー
  Widget _buildAlbumPlaceholder() {
    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: Icon(
          Icons.album,
          size: 120,
          color: Colors.white54,
        ),
      ),
    );
  }

  /// 写真エリア（画像のオフセット・スケール・元サイズを考慮）
  Widget _buildPhotoArea(double cardWidth, double frameHeight) {
    // 「気分で投稿」は編集画面を経ないため、カードサイズに合わせた自動レイアウトのみ。
    // 横幅フィット + 縦中央、上下の余白は真っ黒 (#000000) で埋める。
    if (widget.post.isMoodPost) {
      return ColoredBox(
        color: const Color(0xFF000000),
        child: _buildPhotoImage(BoxFit.fitWidth),
      );
    }

    final imgScale = widget.post.imageScale != 0 ? widget.post.imageScale : 1.0;
    final natW = widget.post.imageNaturalWidth;
    final natH = widget.post.imageNaturalHeight;
    final hasNaturalDims = natW > 0 && natH > 0;

    if (hasNaturalDims) {
      // 高さ基準でフィット: 縦幅がカード高さになるまで等比拡大し、横幅は363でクリップ
      final scaleFactor = cardWidth / 363.0;
      final baseScale = frameHeight / natH;
      final displayW = natW * baseScale;
      final displayH = natH * baseScale;

      // ローディングインジケーターをカード中央に表示するための
      // SizedBox ローカル座標（Transform.scale 前）でのカード中心位置
      final indicatorCenter = Offset(
        (cardWidth / 2 - widget.post.imageOffsetX * scaleFactor) / imgScale,
        (frameHeight / 2 - widget.post.imageOffsetY * scaleFactor) / imgScale,
      );

      final imageWidget = _buildPhotoImage(BoxFit.fill, indicatorCenter: indicatorCenter);

      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: widget.post.imageOffsetX * scaleFactor,
            top: widget.post.imageOffsetY * scaleFactor,
            child: Transform.scale(
              scale: imgScale,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: displayW,
                height: displayH,
                child: imageWidget,
              ),
            ),
          ),
        ],
      );
    } else {
      // 旧方式（後方互換）: BoxFit.cover + Transform
      final imageWidget = _buildPhotoImage(BoxFit.cover);
      return Transform.translate(
        offset: Offset(widget.post.imageOffsetX, widget.post.imageOffsetY),
        child: Transform.scale(
          scale: imgScale,
          child: imageWidget,
        ),
      );
    }
  }

  /// 写真画像ウィジェット（Base64 / ネットワーク / アセット / アルバムアート）
  Widget _buildPhotoImage(BoxFit fit, {Offset? indicatorCenter}) {
    if (_hasBackPhoto) {
      if (_isPhotoUrlDataUrl) {
        return Builder(
          builder: (context) {
            try {
              // キャッシュ済みならそれを使う
              if (_decodedPhotoBytes == null || _decodedPhotoUrl != widget.post.photoUrl) {
                final String base64String = widget.post.photoUrl!.split(',')[1];
                _decodedPhotoBytes = base64Decode(base64String);
                _decodedPhotoUrl = widget.post.photoUrl;
              }
              return Image.memory(
                _decodedPhotoBytes!,
                fit: fit,
                errorBuilder: (context, error, stackTrace) {
                  if (kDebugMode) {
                    print('❌ Failed to decode Base64 photo: $error');
                  }
                  return _displayAlbumArtUrl.isNotEmpty
                      ? _buildAlbumArt(
                          _displayAlbumArtUrl,
                          fit: fit,
                          errorWidget: _buildPhotoPlaceholder(),
                        )
                      : _buildPhotoPlaceholder();
                },
              );
            } catch (e) {
              if (kDebugMode) {
                print('❌ Error parsing Base64: $e');
              }
              return _buildPhotoPlaceholder();
            }
          },
        );
      } else if (_isPhotoUrlNetwork) {
        return CachedNetworkImage(
          imageUrl: widget.post.photoUrl!,
          fit: fit,
          progressIndicatorBuilder: (context, url, progress) {
            if (indicatorCenter != null) {
              // 大きなSizedBox内でも、カード中央にインジケーターを配置する
              const double radius = 14;
              return Stack(
                children: [
                  Positioned(
                    left: indicatorCenter.dx - radius,
                    top: indicatorCenter.dy - radius,
                    child: const CupertinoActivityIndicator(
                      color: Colors.white,
                      radius: radius,
                    ),
                  ),
                ],
              );
            }
            return const Center(
              child: CupertinoActivityIndicator(
                color: Colors.white,
                radius: 14,
              ),
            );
          },
          errorWidget: (context, url, error) {
            if (kDebugMode) {
              print('❌ Failed to load photo: $error');
              print('   URL: ${PhotoHelper.formatPhotoUrlForLog(widget.post.photoUrl)}');
            }
            return _displayAlbumArtUrl.isNotEmpty
                ? _buildAlbumArt(
                    _displayAlbumArtUrl,
                    fit: fit,
                    errorWidget: _buildPhotoPlaceholder(),
                  )
                : _buildPhotoPlaceholder();
          },
        );
      } else {
        return Image.asset(
          widget.post.photoUrl!,
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            return _displayAlbumArtUrl.isNotEmpty
                ? _buildAlbumArt(
                    _displayAlbumArtUrl,
                    fit: fit,
                    errorWidget: _buildPhotoPlaceholder(),
                  )
                : _buildPhotoPlaceholder();
          },
        );
      }
    } else {
      return _displayAlbumArtUrl.isNotEmpty
          ? _buildAlbumArt(
              _displayAlbumArtUrl,
              fit: fit,
              errorWidget: _buildPhotoPlaceholder(),
            )
          : _buildPhotoPlaceholder();
    }
  }

  /// 写真プレースホルダー
  Widget _buildPhotoPlaceholder() {
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Icon(
          Icons.photo,
          size: 120,
          color: Colors.white54,
        ),
      ),
    );
  }

  /// ユーザー情報（裏面の左上）
  Widget _buildUserInfoTopLeft(PostTheme theme) {
    // Vibeの場合は「Vibe【お題名】」または「Vibe」、それ以外は感情タグを表示
    String? displayText;

    if (widget.post.isVibe) {
      // Vibe投稿の場合
      if (widget.post.vibeTopicTitle != null && widget.post.vibeTopicTitle!.isNotEmpty) {
        displayText = '#${widget.post.vibeTopicTitle!}';
      } else {
        // vibeTopicTitleがない古い投稿の場合はVibeのみ表示
        displayText = 'Vibe';
      }
    } else if (widget.post.emotionTag != null) {
      displayText = widget.post.emotionTag;
    }
    // Vibeでも感情タグでもない場合は2行目を表示しない

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OtherUserProfileScreen(
              userId: widget.post.userId,
            ),
          ),
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[400],
            ),
            child: ClipOval(
              child: ProfileImage(
                imageUrl: widget.post.userIconUrl,
                size: 32,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildWeightAdjustedText(
                  widget.post.username,
                  fontSize: 12,
                  baseWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                if (displayText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    displayText,
                    style: const TextStyle(
                      fontSize: 7,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 裏面・右上の班ハンドル（@◯◯）
  /// 左のユーザー情報と同じ高さに揃え、右端に配置する。
  /// 同日2投稿目以降（countsForAdl == false）はハンドル非表示。
  Widget _buildTeamHandleTopRight() {
    if (!_showAdlTeamHandle) return const SizedBox.shrink();
    final teamId = widget.post.adlTeamId;
    if (teamId == null || teamId.isEmpty) return const SizedBox.shrink();
    if (widget.post.countsForAdl == false) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdlTeamPlaylistScreen(teamId: teamId),
          ),
        );
      },
      child: Text(
        '@${AdlTeamDefinitions.displayNameOf(teamId)}',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFFD9D9D9),
        ),
      ),
    );
  }

  /// 歌詞カードオーバーレイ（裏面の写真上）
  Widget _buildLyricsCardOverlay() {
    // 投稿時に保存されたレイアウト情報を取得
    final layoutIndex = widget.post.selectedLayoutIndex;
    final positionX = widget.post.cardPositionX;
    final positionY = widget.post.cardPositionY;
    final scale = widget.post.cardScale;
    final rotation = widget.post.cardRotation;

    // レイアウトタイプを取得
    final layoutType = LyricsCardLayout.getLayoutType(layoutIndex);

    // 歌詞テキストを決定（保存済み > 動的取得 > null）
    final lyricsText = widget.post.lyricsText ?? _fetchedLyricsText;

    // 歌詞がない場合は動的に取得を試みる
    if (lyricsText == null && !_lyricsFetchAttempted) {
      // 非同期で歌詞を取得（UIはブロックしない）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchLyricsIfNeeded();
      });
    }

    return Positioned(
      left: positionX,
      top: positionY,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: Transform.rotate(
          angle: rotation,
          alignment: Alignment.center,
          child: LyricsCardLayout(
            layoutType: layoutType,
            track: widget.post.track,
            lyricsText: _isLyricsFetching ? '歌詞を取得中...' : lyricsText,
          ),
        ),
      ),
    );
  }

  /// MarqueeText 用: 文字単位で日本語 +200 補正を行った InlineSpan を返す
  /// テキストを TextSpan として返す（補正なし、指定ウェイトをそのまま適用）
  static InlineSpan _buildWeightAdjustedSpan(
    String text, {
    required TextStyle baseStyle,
  }) {
    return TextSpan(text: text, style: baseStyle);
  }

  /// テキストを Text ウィジェットとして返す（補正なし、指定ウェイトをそのまま適用）
  static Widget _buildWeightAdjustedText(
    String text, {
    required double fontSize,
    required FontWeight baseWeight,
    required Color color,
    int maxLines = 1,
    TextOverflow overflow = TextOverflow.ellipsis,
  }) {
    {
      return Text(
        text,
        style: TextStyle(fontSize: fontSize, fontWeight: baseWeight, color: color),
        maxLines: maxLines,
        overflow: overflow,
      );
    }
  }

  /// リアクションボタン（いいね、コメント、追加）
  Widget _buildReactionButton({
    required IconData icon,
    required Color color,
    required int? count,
    required VoidCallback? onTap,
    required Color textColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 24,
            color: color,
          ),
          if (count != null) ...[
            const SizedBox(width: 4),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 12,
                color: textColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// コメントリアクションボタン（裏面用・SVGアイコン使用）
  Widget _buildCommentReactionBack({
    required int count,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: widget.disableInteractions ? null : onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/icons/message_circle.svg',
            width: 24,
            height: 24,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
          if (!widget.hideReactionCounts) ...[
            const SizedBox(width: 4),
            Text(
              count.toString(),
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  /// コメントボタン
  Widget _buildCommentButton(PostTheme theme) {
    if (widget.disableInteractions) {
      // 制限中：グレーアウト表示してタップ時に通知
      return GestureDetector(
        onTap: () => RestrictionNotification.show(context, message: 'コメントができません'),
        child: Opacity(
          opacity: 0.35,
          child: Container(
            height: 43,
            decoration: BoxDecoration(
              color: theme.commentButtonColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Text(
                  'コメントする',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: theme.textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: widget.onComment,
      child: Container(
        height: 43,
        decoration: BoxDecoration(
          color: theme.commentButtonColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Text(
              'コメントする',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: theme.textColor,
              ),
            ),
            const Spacer(),
            Image.asset(
              'assets/icons/comment_send_button.png',
              width: 20,
              height: 20,
              color: theme.textColor.withOpacity(0.6),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  /// 音楽波形
  /// 大、小、大のパターン（各投稿でpostIdをシードとして微妙に異なるパターン）
  Widget _buildWaveform(PostTheme theme) {
    return RepaintBoundary(
      child: AnimatedWaveform(
        postId: widget.post.postId,
        barColor: theme.iconColor,
        audioService: widget.audioService,
        previewUrl: _cachedPreviewUrl ?? widget.externalPreviewUrl,
        tempo: _tempo,
      ),
    );
  }

  /// 曲名とアーティスト名（表面）
  Widget _buildTrackInfo(PostTheme theme) {
    // Positionedで配置されているため、利用可能な幅を計算
    // left: 11px, right: 66px → 利用可能幅: 363 - 11 - 66 = 286px
    const availableWidth = 286.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarqueeText(
          textSpan: _buildWeightAdjustedSpan(
            widget.post.track.trackName,
            baseStyle: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: theme.textColor,
            ),
          ),
          width: availableWidth,
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ArtistProfileScreen(
                artistName: widget.post.track.artistName,
                spotifyArtistId: widget.post.track.spotifyArtistId,
              ),
            ),
          ),
          child: Opacity(
            opacity: 0.8,
            child: _buildWeightAdjustedText(
              widget.post.track.artistName,
              fontSize: 11,
              baseWeight: FontWeight.w400,
              color: theme.textColor,
            ),
          ),
        ),
      ],
    );
  }

  /// リアクション（スマイル＝絵文字リアクション、追加）
  Widget _buildReactions(PostTheme theme) {
    // Figma 5111:10598: スマイル left12・プラス left82（ともに 32×32）。
    // 行の起点は left12 なので、スマイル(32)→隙間(38)→プラス(32) で left82 に合う。
    return Row(
      children: [
        // スマイル（絵文字リアクション）。背景に応じて白/黒が切り替わる。
        _buildSmileyButton(size: 32, color: theme.iconColor),
        const SizedBox(width: 38),

        // コメント（接続を切っている。kCommentsEnabled=false で復活可）
        if (kCommentsEnabled) ...[
          _buildCommentReaction(
            count: widget.post.commentCount,
            onTap: widget.onComment,
            theme: theme,
          ),
          const SizedBox(width: 38),
        ],

        // 追加（保存ボタン）
        _buildSaveButton(theme: theme, size: 32),

        if (!widget.hideReactionCounts) ...[
          const Spacer(),
          // リアクションしたユーザーのアバター＋絵文字（最大2人）
          _buildReactorAvatars(),
        ],
      ],
    );
  }

  /// リアクションアイテム
  Widget _buildReactionItem({
    required IconData icon,
    required int count,
    VoidCallback? onTap,
    bool isActive = false,
    required PostTheme theme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            icon,
            size: 25,
            color: isActive ? Colors.red : theme.iconColor,
          ),
          if (!widget.hideReactionCounts) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isActive ? Colors.red : theme.textColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// コメントリアクションアイテム（SVGアイコン使用）
  Widget _buildCommentReaction({
    required int count,
    VoidCallback? onTap,
    required PostTheme theme,
  }) {
    return GestureDetector(
      onTap: widget.disableInteractions ? null : onTap,
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/icons/message_circle.svg',
            width: 25,
            height: 25,
            colorFilter: ColorFilter.mode(
              theme.iconColor,
              BlendMode.srcIn,
            ),
          ),
          if (!widget.hideReactionCounts) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.textColor,
              ),
            ),
          ],
        ],
      ),
    );
  }


  /// いいねしたユーザーのアイコン（裏面用 - 固定サイズ）
  Widget _buildLikedUsersIcons() {
    return _buildLikedUsersIconsCommon(
      iconSize: PostCardConstants.likedUserIconSize,
      margin: PostCardConstants.likedUserIconMargin,
    );
  }

  /// いいねしたユーザーのアイコン（表面用 - 相対サイズ）
  Widget _buildLikedUsersIconsFront(double cardWidth, double cardHeight) {
    return _buildLikedUsersIconsCommon(
      iconSize: cardWidth * (PostCardConstants.likedUserIconSize / PostCardConstants.cardBaseWidth),
      margin: cardWidth * (PostCardConstants.likedUserIconMargin / PostCardConstants.cardBaseWidth),
    );
  }

  /// いいねしたユーザーのアイコン（共通ロジック）
  Widget _buildLikedUsersIconsCommon({
    required double iconSize,
    required double margin,
  }) {
    final iconUrls = _likedByUserIconUrlsOptimistic ?? widget.post.likedByUserIconUrls;
    final displayCount = iconUrls.length > PostCardConstants.maxLikedUsersToShow
        ? PostCardConstants.maxLikedUsersToShow
        : iconUrls.length;

    if (displayCount == 0) {
      return const SizedBox.shrink();
    }

    return Row(
      children: List.generate(
        displayCount,
        (index) => GestureDetector(
          onTap: () {
            if (index < widget.post.likedUserIds.length) {
              _navigateToUserProfile(widget.post.likedUserIds[index]);
            }
          },
          child: Container(
            width: iconSize,
            height: iconSize,
            margin: EdgeInsets.only(left: index > 0 ? margin : 0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[400],
            ),
            child: ClipOval(
              child: ProfileImage(
                imageUrl: iconUrls[index],
                size: 25,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// スマイル（リアクション）ボタン。タップで絵文字ピッカーを開く。
  /// [color] を渡すと白黒の PNG を srcIn で着色（他アイコンと同じく背景に応じて
  /// 白/黒が切り替わるよう、表面では theme.iconColor を渡す）。
  Widget _buildSmileyButton({required double size, Color? color}) {
    return Builder(
      builder: (btnCtx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showReactionPicker(btnCtx),
        child: Image.asset(
          'assets/icons/reaction_smile.png',
          width: size,
          height: size,
          color: color,
          colorBlendMode: color != null ? BlendMode.srcIn : null,
        ),
      ),
    );
  }

  /// リアクションしたユーザーのアイコン＋絵文字バッジ（共通ロジック）。
  /// Figma 4947:10749 準拠: アバター 32×32・間隔0（隣接）・右下に 15px の絵文字。
  Widget _buildReactorAvatarsCommon({required double iconSize}) {
    final reactions = effectiveReactions;
    if (widget.hideReactionCounts || reactions.isEmpty) {
      return const SizedBox.shrink();
    }
    const maxShow = 3;
    final displayCount =
        reactions.length > maxShow ? maxShow : reactions.length;
    final emojiSize = iconSize * (15 / 32); // Figma: 32アバターに 15絵文字

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(displayCount, (index) {
        final r = reactions[index];
        return GestureDetector(
          onTap: () => _navigateToUserProfile(r.userId),
          child: SizedBox(
            width: iconSize,
            height: iconSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[400],
                  ),
                  child: ClipOval(
                    child: ProfileImage(imageUrl: r.iconUrl, size: iconSize),
                  ),
                ),
                // 絵文字バッジ: 右下角に合わせる（Figma: 右端・下端をアバターに揃える）
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Text(
                    r.emoji,
                    style: TextStyle(fontSize: emojiSize, height: 1.0),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  /// リアクションアバター（裏面用 - 相対サイズ 32/363）
  Widget _buildReactorAvatars() {
    return _buildReactorAvatarsCommon(iconSize: 32);
  }

  /// リアクションアバター（表面用 - 相対サイズ 32/363）
  Widget _buildReactorAvatarsFront(double cardWidth, double cardHeight) {
    return _buildReactorAvatarsCommon(
      iconSize: cardWidth * (32 / PostCardConstants.cardBaseWidth),
    );
  }

  /// ユーザー情報（表面の下部）
  Widget _buildUserInfo(PostTheme theme) {
    final teamId = widget.post.adlTeamId;
    // 同日2投稿目以降（countsForAdl == false）はハンドル非表示。
    final hasTeam = teamId != null &&
        teamId.isNotEmpty &&
        widget.post.countsForAdl != false;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ユーザーアイコン + 名前（タップでユーザープロフィール）
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => OtherUserProfileScreen(
                  userId: widget.post.userId,
                ),
              ),
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[400],
                ),
                child: ClipOval(
                  child: ProfileImage(
                    imageUrl: widget.post.userIconUrl,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(width: 9), // Figma: アイコン right44 → 名前 left53
              _buildWeightAdjustedText(
                widget.post.username,
                fontSize: 12,
                baseWeight: FontWeight.w600,
                color: theme.textColor,
              ),
            ],
          ),
        ),

        // 班ハンドル（@◯◯班）。タップで班プロフィールへ。ADLハンドルは非表示。
        if (hasTeam && _showAdlTeamHandle) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdlTeamPlaylistScreen(teamId: teamId),
                ),
              );
            },
            child: Text(
              '@${AdlTeamDefinitions.displayNameOf(teamId)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                // 背景色に合わせて黒/白が切り替わる（ユーザー名と同じ規則）
                // ややトーンダウンさせて補助情報として馴染ませる
                color: theme.textColor.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// ADL班ハンドル（@hiphop 等）は投稿カード上で非表示にする。
  bool get _showAdlTeamHandle => false;

  /// 3点メニューボタン（削除 or 通報）
  bool get _showMoreButton =>
      widget.currentUserId != null &&
      (widget.post.userId != widget.currentUserId ||
          widget.onDelete != null);

  bool get _isOwner =>
      widget.currentUserId != null &&
      widget.post.userId == widget.currentUserId;

  Widget _buildMoreButton(PostTheme theme, {Color? color}) {
    final _moreButtonColor = color;
    return NativePullDownButton(
      items: [
        if (_isOwner && widget.onDelete != null)
          const NativeMenuItem(id: 'delete', title: '削除', type: 'destructive', icon: 'trash'),
        if (!_isOwner)
          const NativeMenuItem(id: 'report', title: '通報', type: 'destructive', icon: 'exclamationmark.triangle'),
      ],
      onSelected: (id) async {
        if (id == 'delete') widget.onDelete?.call();
        if (id == 'report') {
          await showReportDialog(
            context,
            reportedUserId: widget.post.userId,
            postId: widget.post.postId,
          );
        }
      },
      child: SizedBox(
        width: 32,
        height: 36,
        child: Icon(Icons.more_vert, color: _moreButtonColor ?? theme.iconColor, size: 22),
      ),
    );
  }

  Widget _buildSaveButton({
    required PostTheme theme,
    Color? color,
    double size = 32,
  }) {
    return GestureDetector(
      onTap: widget.onAdd,
      child: widget.isSaved
          ? _buildSavedIcon(size: size)
          : Icon(
              Icons.add_circle_outline,
              size: size,
              color: color ?? theme.iconColor,
            ),
    );
  }

  /// 保存済みアイコン（緑色の円 + 灰色のチェックマーク）
  Widget _buildSavedIcon({double size = 32}) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 背景：明るい緑色の塗りつぶし円
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.lightGreen,
            shape: BoxShape.circle,
          ),
        ),
        // 前景：灰色のチェックマーク
        Icon(
          Icons.check,
          size: size * 0.72,
          color: Colors.grey[700],
        ),
      ],
    );
  }

  /// ユーザープロフィール画面へ遷移
  void _navigateToUserProfile(String userId) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    // 自分自身の場合はProfileScreenへ
    if (currentUserId == userId) {
      Navigator.pushNamed(context, '/profile');
      return;
    }

    // 他のユーザーの場合はOtherUserProfileScreenへ
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OtherUserProfileScreen(
          userId: userId,
        ),
      ),
    );
  }

  /// 外部から共有を実行（CardShareScreenのボタンから呼び出す）
  void shareCard() => _handleShare();

  /// 角丸マスクを適用してPNGバイト列を返す（角を透明にする）
  Future<Uint8List?> _applyRoundedMask(Uint8List pngBytes, double pixelRatio) async {
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final radius = PostCardConstants.cardBorderRadius * pixelRatio;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
        Radius.circular(radius),
      ),
    );
    canvas.drawImage(src, Offset.zero, Paint());
    final picture = recorder.endRecording();
    final result = await picture.toImage(src.width, src.height);
    final data = await result.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  /// カードをPNG画像として返す（Instagram Stories共有等に使用）
  Future<Uint8List?> captureAsImage() async {
    try {
      final boundary = _cardRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      const pixelRatio = 3.0;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final raw = byteData?.buffer.asUint8List();
      if (raw == null) return null;
      return await _applyRoundedMask(raw, pixelRatio);
    } catch (_) {
      return null;
    }
  }

  /// カードをPNG画像として写真ライブラリに保存
  Future<void> _handleShare() async {
    final ctx = context;
    try {
      final boundary = _cardRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      const pixelRatio = 3.0;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final raw = byteData.buffer.asUint8List();
      final bytes = await _applyRoundedMask(raw, pixelRatio) ?? raw;

      // 写真ライブラリのパーミッション確認
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) {
        if (ctx.mounted) AppToast.show(ctx, '写真へのアクセスを許可してください');
        return;
      }

      // ギャラリーに保存
      final asset = await PhotoManager.editor.saveImage(
        bytes,
        filename: 'fifteen_card_${DateTime.now().millisecondsSinceEpoch}.png',
      );

      if (!ctx.mounted) return;
      AppToast.show(ctx, '写真に保存しました');
    } catch (e) {
      if (kDebugMode) print('❌ Save error: $e');
      if (ctx.mounted) AppToast.show(ctx, '保存に失敗しました');
    }
  }
}

