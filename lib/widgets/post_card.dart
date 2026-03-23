import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'animated_waveform.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import '../models/post_model.dart';
import '../models/post_theme.dart';
import '../screens/other_user_profile_screen.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/lyrics_service.dart';
import '../services/post_service.dart';
import '../utils/color_extractor.dart';
import '../utils/photo_helper.dart';
import 'profile_widgets.dart';
import 'post_creation/lyrics_card_layouts.dart';
import 'post_card/post_card_constants.dart';
import 'post_card/marquee_text.dart';
import 'dialogs/restriction_notification.dart';
import 'dialogs/report_dialog.dart';

/// 投稿カードウィジェット（表裏反転アニメーション付き）
class PostCard extends StatefulWidget {
  final PostModel post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onAdd;
  final VoidCallback? onDelete;
  final String? currentUserId;
  final String? currentUserIconUrl; // 現在のユーザーのアイコンURL（楽観的UI用）
  final AudioPlayerService audioService; // 音楽再生サービス（外部から注入）
  final bool showFrontOnly; // trueの場合、表面のみ表示（反転なし）
  final VoidCallback? onCardTap; // showFrontOnly時の外部タップハンドラ
  final bool isSaved; // 保存済みかどうか
  final bool hideReactionCounts; // trueの場合、リアクション数を非表示（プレビュー用）
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
  final bool persistentPlayButton; // trueの場合、停止中は再生ボタンを常時表示・再生中は非表示

  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onAdd,
    this.onDelete,
    this.currentUserId,
    this.currentUserIconUrl,
    required this.audioService, // 必須パラメータ
    this.showFrontOnly = false, // デフォルトは両面表示
    this.onCardTap, // 外部タップハンドラ（オプション）
    this.isSaved = false, // デフォルトは未保存
    this.hideReactionCounts = false, // デフォルトはカウント表示
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
    this.persistentPlayButton = false, // デフォルトはアニメーション表示
  });

  @override
  State<PostCard> createState() => PostCardState();
}

class PostCardState extends State<PostCard>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _showFront = true;

  // 再生ボタンアニメーション用
  late AnimationController _playButtonAnimationController;
  late Animation<double> _playButtonScaleAnimation;
  late Animation<double> _playButtonOpacityAnimation;

  // persistentPlayButton モード用の状態管理
  bool _lastPersistentPlayingState = false;
  IconData _persistentTransitionIcon = Icons.play_arrow;

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

    // 再生ボタンアニメーション
    _playButtonAnimationController = AnimationController(
      duration: PostCardConstants.playButtonAnimationDuration,
      vsync: this,
    );

    // スケールアニメーション（0.5秒で拡大→0.5秒で縮小）
    _playButtonScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_playButtonAnimationController);

    // 不透明度アニメーション（0.5秒で表示→0.5秒でフェードアウト）
    _playButtonOpacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_playButtonAnimationController);

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


  /// 色テーマの初期化
  void _initializeColors() {
    // 色の優先順位:
    // 1. 事前抽出パラメータ
    // 2. Firestoreに保存されたテーマ（デフォルトテーマでない場合）
    // 3. リアルタイム抽出
    if (widget.preExtractedGradientStart != null && widget.preExtractedGradientEnd != null) {
      debugPrint('✅ PostCard: 事前抽出された色を使用します');
      _extractedGradientStart = widget.preExtractedGradientStart;
      _extractedGradientEnd = widget.preExtractedGradientEnd;
    } else if (widget.post.theme != PostTheme.defaultTheme) {
      debugPrint('✅ PostCard: Firestoreのテーマを使用します');
      _extractedGradientStart = widget.post.theme.gradientStart;
      _extractedGradientEnd = widget.post.theme.gradientEnd;
    } else {
      debugPrint('⚠️ PostCard: 色が未抽出のため、抽出を開始します');
      _extractColorsFromAlbumArt();
    }
  }

  /// アルバムアートから色を抽出
  Future<void> _extractColorsFromAlbumArt() async {
    if (_isColorExtracting) return;

    setState(() {
      _isColorExtracting = true;
    });

    try {
      final imageUrl = _displayAlbumArtUrl;
      debugPrint('🎨 Extracting colors from: $imageUrl');

      if (imageUrl.isNotEmpty) {
        // グラデーション用の色ペアを抽出
        final (gradientStart, gradientEnd) =
            await ColorExtractor.extractGradientColors(imageUrl);

        debugPrint('✅ Color extraction successful!');
        debugPrint('  Gradient Start: $gradientStart');
        debugPrint('  Gradient End: $gradientEnd');

        if (mounted) {
          setState(() {
            _extractedGradientStart = gradientStart;
            _extractedGradientEnd = gradientEnd;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Color extraction error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isColorExtracting = false;
        });
      }
    }
  }

  /// 歌詞を動的に取得（lyricsTextがない場合のフォールバック）
  Future<void> _fetchLyricsIfNeeded() async {
    // 既に歌詞がある場合、または取得中/取得済みの場合はスキップ
    if (widget.post.lyricsText != null || _isLyricsFetching || _lyricsFetchAttempted) {
      return;
    }

    setState(() {
      _isLyricsFetching = true;
    });

    try {
      final lyricsData = await _lyricsService.getLyrics(
        trackName: widget.post.track.trackName,
        artistName: widget.post.track.artistName,
      );

      if (mounted && lyricsData != null) {
        final truncatedLyrics = _lyricsService.truncateLyrics(
          lyricsData.plainLyrics,
          maxLines: 4,
        );
        setState(() {
          _fetchedLyricsText = truncatedLyrics;
        });
        debugPrint('✅ PostCard: 歌詞を動的に取得しました');

        // Firebaseに保存（テスト投稿以外の場合）
        final postId = widget.post.postId;
        if (!postId.startsWith('test_post_') && !postId.startsWith('preview_')) {
          await _postService.updateLyricsText(
            postId: postId,
            lyricsText: truncatedLyrics,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ PostCard: 歌詞取得エラー: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLyricsFetching = false;
          _lyricsFetchAttempted = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _flipController.dispose();
    _playButtonAnimationController.dispose();
    _rejectController.dispose();
    super.dispose();
  }

  /// 表面に戻す（外部から呼び出し可能）
  void flipToFront() {
    if (!mounted || _showFront) return;
    setState(() { _showFront = true; });
    _flipController.reverse();
  }

  /// 裏面に戻す（外部から呼び出し可能）
  void flipToBack() {
    if (!mounted || !_showFront) return;
    setState(() { _showFront = false; });
    _flipController.forward();
  }

  /// カードをタップして裏返す
  void _flipCard() async {
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

      _flipController.forward().then((_) {
        // フリップアニメーション完了後、再生ボタンのアニメーションを表示
        if (mounted && !_showFront) {
          _playButtonAnimationController.forward(from: 0.0);
        }
      });

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

  /// 音楽を非同期で再生（UIをブロックしない）
  Future<void> _playAudioAsync() async {
    // 二重呼び出し防止（自動再生とフリップが競合するケース）
    if (_isPlayAudioInProgress) return;
    _isPlayAudioInProgress = true;

    try {
      String? previewUrl = _cachedPreviewUrl;

      // キャッシュがない場合、iTunes APIから取得
      if (previewUrl == null) {
        if (kDebugMode) print('🍎 Fetching preview URL from iTunes...');
        final result = await _itunesService.getPreviewUrlWithArt(
          trackName: widget.post.track.trackName,
          artistName: widget.post.track.artistName,
        );
        if (!mounted) return;

        if (result != null) {
          previewUrl = result['previewUrl'];
          // setState で更新し、波形ウィジェットにURLを反映
          setState(() { _cachedPreviewUrl = previewUrl; });
          if (kDebugMode) print('✅ iTunes preview URL obtained and cached');
        } else {
          // 1回目が失敗した場合、1秒後にリトライ
          if (kDebugMode) print('⚠️ iTunes returned null, retrying in 1s...');
          await Future.delayed(const Duration(seconds: 1));
          if (!mounted) return;
          final retryResult = await _itunesService.getPreviewUrlWithArt(
            trackName: widget.post.track.trackName,
            artistName: widget.post.track.artistName,
          );
          if (!mounted) return;
          if (retryResult != null) {
            previewUrl = retryResult['previewUrl'];
            setState(() { _cachedPreviewUrl = previewUrl; });
            if (kDebugMode) print('✅ iTunes retry succeeded');
          } else {
            if (kDebugMode) print('❌ iTunes retry also failed');
          }
        }
      } else {
        if (kDebugMode) print('📦 Using cached preview URL');
      }

      if (!mounted) return;

      // プレビューURLがあれば再生
      if (previewUrl != null && previewUrl.isNotEmpty) {
        if (kDebugMode) print('▶️  Starting playback...');
        try {
          await widget.audioService.playPreview(
            previewUrl,
            startFrom: Duration(milliseconds: widget.post.audioStartMs),
            durationSeconds: widget.post.audioDurationSec,
          );
        } catch (e) {
          if (kDebugMode) print('❌ Playback error: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('音楽の再生に失敗しました: ${e.toString()}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        if (kDebugMode) print('⚠️  No preview URL available');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('この曲のプレビューURLが見つかりません'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } finally {
      _isPlayAudioInProgress = false;
    }
  }

  /// いいねボタンが押された時の処理（楽観的UI更新）
  void _handleLikeTap() {
    if (widget.disableInteractions) {
      RestrictionNotification.show(context, message: 'いいねができません');
      return;
    }
    if (widget.onLike != null) {
      setState(() {
        final currentIsLiked = _isLikedOptimistic ??
            (widget.currentUserId != null &&
                widget.post.isLikedBy(widget.currentUserId!));
        final currentLikeCount = _likeCountOptimistic ?? widget.post.likeCount;
        final currentIconUrls = _likedByUserIconUrlsOptimistic ??
            List<String>.from(widget.post.likedByUserIconUrls);

        _isLikedOptimistic = !currentIsLiked;
        _likeCountOptimistic =
            currentIsLiked ? currentLikeCount - 1 : currentLikeCount + 1;

        // アイコンURLリストも楽観的に更新
        if (currentIsLiked) {
          // いいね解除：自分のアイコンを削除
          if (widget.currentUserIconUrl != null) {
            currentIconUrls.remove(widget.currentUserIconUrl);
          } else if (currentIconUrls.isNotEmpty) {
            // アイコンURLがない場合は最後の要素を削除
            currentIconUrls.removeLast();
          }
        } else {
          // いいね追加：自分のアイコンを追加
          final iconUrl = widget.currentUserIconUrl ?? '';
          currentIconUrls.add(iconUrl);
        }
        _likedByUserIconUrlsOptimistic = currentIconUrls;
      });

      widget.onLike!();
    }
  }

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.post.postId != widget.post.postId) {
      _isLikedOptimistic = null;
      _likeCountOptimistic = null;
      _likedByUserIconUrlsOptimistic = null;
    } else if (_isLikedOptimistic != null || _likeCountOptimistic != null || _likedByUserIconUrlsOptimistic != null) {
      final actualIsLiked = widget.currentUserId != null &&
          widget.post.isLikedBy(widget.currentUserId!);
      final actualLikeCount = widget.post.likeCount;

      if (_isLikedOptimistic == actualIsLiked &&
          _likeCountOptimistic == actualLikeCount) {
        _isLikedOptimistic = null;
        _likeCountOptimistic = null;
        _likedByUserIconUrlsOptimistic = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixinのために必要

    return Center(
      child: SizedBox(
        width: 363.0,
        height: 644.0,
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
    );
  }

  /// 動的にテーマを生成（抽出された色を優先、なければデフォルトテーマ）
  PostTheme _getDynamicTheme() {
    // 抽出された色がある場合は動的にテーマを生成
    if (_extractedGradientStart != null && _extractedGradientEnd != null) {
      return ColorExtractor.createThemeFromColors(
        _extractedGradientStart!,
        _extractedGradientEnd!,
      );
    }
    // デフォルトのテーマを使用
    return widget.post.theme;
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
          final cardHeight = constraints.maxHeight > 0 ? constraints.maxHeight : 644.0;
          final albumSize = cardWidth; // アルバムカバーは正方形（カード幅と同じ）
          final contentHeight = cardHeight * (294.0 / 644.0); // タイトルエリア

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
                      ? CachedNetworkImage(
                          imageUrl: _displayAlbumArtUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) {
                            return _buildAlbumPlaceholder();
                          },
                        )
                      : _buildAlbumPlaceholder(),
                ),
              ),

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
                    Positioned(
                      left: cardWidth * (11 / 363),
                      top: contentHeight * (63 / 294),
                      right: _showMoreButton
                          ? cardWidth * (43 / 363)
                          : cardWidth * (12 / 363),
                      child: _buildTrackInfo(theme),
                    ),

                    // 3点メニューボタン
                    if (_showMoreButton)
                    Positioned(
                      right: cardWidth * (11 / 363),
                      top: contentHeight * (63 / 294),
                      child: _buildMoreButton(theme),
                    ),

                    // リアクション - Figma: bottom: 141px → top: 153px (294-141), left: 12px, right: 12px
                    Positioned(
                      left: cardWidth * (12 / 363),
                      right: cardWidth * (12 / 363),
                      top: contentHeight * (128 / 294),
                      child: _buildReactions(theme),
                    ),

                    // 音楽波形 - Figma: bottom: 96px → top: 198px (294-96), left: 4px, right: 5px
                    Positioned(
                      left: cardWidth * (12 / 363),
                      top: contentHeight * (166 / 294),
                      child: _buildWaveform(theme),
                    ),

                    // コメント入力欄 - Figma: bottom: 40px → top: 254px (294-40), left: 12px, right: 12px
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
            final cardHeight = constraints.maxHeight > 0 ? constraints.maxHeight : 644.0;
            return _buildBackCardBody(cardWidth, cardHeight, theme);
          },
        ),
      ),
    );
  }

  /// 裏面カード本文（トランスフォームなし）- キャプチャ・表示共用
  Widget _buildBackCardBody(double cardWidth, double cardHeight, PostTheme theme) {
    final photoHeight = cardHeight * (484.0 / 644.0);
    final contentHeight = cardHeight * (174.0 / 644.0);

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
            // 写真エリア（上部）
            Positioned(
              left: 0,
              top: 0,
              child: ClipRect(
                child: SizedBox(
                  width: cardWidth,
                  height: photoHeight,
                  child: _buildPhotoArea(cardWidth, photoHeight),
                ),
              ),
            ),

            // ユーザー情報（左上）
            Positioned(
              left: 15,
              top: 15,
              child: _buildUserInfoTopLeft(theme),
            ),

            // 歌詞カード
            _buildLyricsCardOverlay(),

            // 再生ボタン（写真エリアの中央）
            Positioned(
              left: (cardWidth - PostCardConstants.playButtonSize) / 2,
              top: (photoHeight - PostCardConstants.playButtonSize) / 2,
              child: _buildPlayButton(),
            ),

            // 下部グラデーション背景
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
                      theme.gradientStart.withOpacity(0.0),
                      theme.gradientEnd,
                    ],
                    stops: const [0.0, 0.0805],
                  ),
                ),
              ),
            ),

            // 曲名とアーティスト名
            Positioned(
              left: cardWidth * (11 / 363),
              right: (widget.currentUserId != null && widget.post.userId == widget.currentUserId)
                  ? cardWidth * (84 / 363)
                  : cardWidth * (12 / 363),
              bottom: cardHeight * (110 / 644),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  MarqueeText(
                    textSpan: _buildWeightAdjustedSpan(
                      widget.post.track.trackName,
                      baseStyle: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: theme.textColor,
                      ),
                    ),
                    width: (widget.currentUserId != null && widget.post.userId == widget.currentUserId)
                        ? cardWidth * (268 / 363)
                        : cardWidth * (340 / 363),
                  ),
                  const SizedBox(height: 1.198),
                  _buildWeightAdjustedText(
                    widget.post.track.artistName,
                    fontSize: 13,
                    baseWeight: FontWeight.w400,
                    color: theme.secondaryTextColor,
                  ),
                ],
              ),
            ),

            // リアクション
            Positioned(
              left: cardWidth * (12 / 363),
              bottom: cardHeight * (80 / 644),
              child: Row(
                children: [
                  _buildReactionButton(
                    icon: _isLikedOptimistic ??
                            (widget.currentUserId != null &&
                                widget.post.isLikedBy(widget.currentUserId!))
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: _isLikedOptimistic ??
                            (widget.currentUserId != null &&
                                widget.post.isLikedBy(widget.currentUserId!))
                        ? Colors.red
                        : theme.iconColor,
                    count: widget.hideReactionCounts ? null : (_likeCountOptimistic ?? widget.post.likeCount),
                    onTap: _handleLikeTap,
                    textColor: _isLikedOptimistic ??
                            (widget.currentUserId != null &&
                                widget.post.isLikedBy(widget.currentUserId!))
                        ? Colors.red
                        : theme.iconColor,
                  ),
                  SizedBox(width: cardWidth * (15 / 363)),
                  _buildCommentReactionBack(
                    count: widget.post.commentCount,
                    onTap: widget.disableInteractions
                        ? () => RestrictionNotification.show(context, message: 'コメントができません')
                        : widget.onComment,
                    theme: theme,
                  ),
                  SizedBox(width: cardWidth * (15 / 363)),
                  _buildSaveButton(theme: theme),
                ],
              ),
            ),

            // ユーザーアバター（右側）
            Positioned(
              right: cardWidth * (12 / 363),
              bottom: cardHeight * (80 / 644),
              child: _buildLikedUsersIconsFront(cardWidth, cardHeight),
            ),

            // コメントボタン
            Positioned(
              left: cardWidth * (12 / 363),
              right: cardWidth * (12 / 363),
              bottom: cardHeight * (28 / 644),
              child: _buildCommentButton(theme),
            ),

            // "Provided courtesy of Apple Music"
            Positioned(
              left: cardWidth * (17 / 363),
              bottom: cardHeight * (9 / 644),
              child: Text(
                'Provided courtesy of Apple Music',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.secondaryTextColor.withOpacity(0.7),
                ),
              ),
            ),

            // 3点メニューボタン（裏面）
            if (_showMoreButton)
            Positioned(
              right: cardWidth * (11 / 363),
              bottom: cardHeight * (110 / 644),
              child: _buildMoreButton(theme),
            ),
          ],
        ),
      ),
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
  Widget _buildPhotoArea(double cardWidth, double photoHeight) {
    final imgScale = widget.post.imageScale != 0 ? widget.post.imageScale : 1.0;
    final natW = widget.post.imageNaturalWidth;
    final natH = widget.post.imageNaturalHeight;
    final hasNaturalDims = natW > 0 && natH > 0;

    final imageWidget = _buildPhotoImage(hasNaturalDims ? BoxFit.fill : BoxFit.cover);

    if (hasNaturalDims) {
      // 新方式: 画像の元サイズから枠を埋める表示サイズを計算
      final scaleFactor = cardWidth / 363.0;
      final baseScale = max(cardWidth / natW, photoHeight / natH);
      final displayW = natW * baseScale;
      final displayH = natH * baseScale;
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
  Widget _buildPhotoImage(BoxFit fit) {
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
                      ? CachedNetworkImage(
                          imageUrl: _displayAlbumArtUrl,
                          fit: fit,
                          errorWidget: (context, url, error) => _buildPhotoPlaceholder(),
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
            return Center(
              child: CircularProgressIndicator(
                value: progress.totalSize != null
                    ? progress.downloaded / progress.totalSize!
                    : null,
                color: Colors.white,
              ),
            );
          },
          errorWidget: (context, url, error) {
            if (kDebugMode) {
              print('❌ Failed to load photo: $error');
              print('   URL: ${PhotoHelper.formatPhotoUrlForLog(widget.post.photoUrl)}');
            }
            return _displayAlbumArtUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: _displayAlbumArtUrl,
                    fit: fit,
                    errorWidget: (context, url, error) => _buildPhotoPlaceholder(),
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
                ? CachedNetworkImage(
                    imageUrl: _displayAlbumArtUrl,
                    fit: fit,
                    errorWidget: (context, url, error) => _buildPhotoPlaceholder(),
                  )
                : _buildPhotoPlaceholder();
          },
        );
      }
    } else {
      return _displayAlbumArtUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: _displayAlbumArtUrl,
              fit: fit,
              errorWidget: (context, url, error) => _buildPhotoPlaceholder(),
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
        // ユーザープロフィール画面へ遷移
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // プロフィールアイコン
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

            // ユーザー名とハッシュタグ
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ユーザー名
                  _buildWeightAdjustedText(
                    widget.post.username,
                    fontSize: 14,
                    baseWeight: FontWeight.w600,
                    color: Colors.white,
                  ),

                  // ハッシュタグ/質問テキスト（感情タグの場合は非表示）
                  if (displayText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      displayText,
                      style: const TextStyle(
                        fontSize: 8,
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

  /// プレビューURLを取得（キャッシュまたはiTunes APIから）
  Future<String?> _fetchPreviewUrl() async {
    if (_cachedPreviewUrl != null) {
      return _cachedPreviewUrl;
    }

    final result = await _itunesService.getPreviewUrlWithArt(
      trackName: widget.post.track.trackName,
      artistName: widget.post.track.artistName,
    );

    if (result != null) {
      final url = result['previewUrl'];
      setState(() {
        _cachedPreviewUrl = url;
      });
      return url;
    }

    return null;
  }

  /// 再生ボタンタップ時の処理
  Future<void> _handlePlayButtonTap(bool isPlaying, String? previewUrl) async {
    // 通常モードのみタップ時アニメーション（persistentモードは状態変化で制御）
    if (!widget.persistentPlayButton) {
      _playButtonAnimationController.forward(from: 0.0);
    }

    // 再生/一時停止処理
    if (isPlaying) {
      widget.audioService.pause();
    } else if (widget.audioService.isPaused && previewUrl != null) {
      widget.audioService.resume();
    } else {
      widget.onPlayStarted?.call();
      final urlToPlay = await _fetchPreviewUrl();
      if (urlToPlay != null && urlToPlay.isNotEmpty) {
        await widget.audioService.playPreview(
          urlToPlay,
          startFrom: Duration(milliseconds: widget.post.audioStartMs),
          durationSeconds: widget.post.audioDurationSec,
        );
      }
    }
  }

  /// MarqueeText 用: 文字単位で日本語 +200 補正を行った InlineSpan を返す
  static InlineSpan _buildWeightAdjustedSpan(
    String text, {
    required TextStyle baseStyle,
  }) {
    const allWeights = [
      FontWeight.w100, FontWeight.w200, FontWeight.w300, FontWeight.w400,
      FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800, FontWeight.w900,
    ];
    final base = baseStyle.fontWeight ?? FontWeight.w400;
    final idx = allWeights.indexOf(base);
    final jaWeight = idx >= 0
        ? allWeights[(idx + 2).clamp(0, allWeights.length - 1)]
        : base;

    final japaneseRegex = RegExp(r'[\u3040-\u30FF\u4E00-\u9FFF\uF900-\uFAFF\u3000-\u303F]+');
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in japaneseRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: TextStyle(fontWeight: base),
        ));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(fontWeight: jaWeight),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: TextStyle(fontWeight: base),
      ));
    }

    if (spans.isEmpty) return TextSpan(text: text, style: baseStyle);
    return TextSpan(style: baseStyle, children: spans);
  }

  /// RichText 用: 日本語ランと英語ランを分割し、文字単位で fontWeight を補正する
  /// 日本語部分は baseWeight +200、英語部分は baseWeight をそのまま適用
  static Widget _buildWeightAdjustedText(
    String text, {
    required double fontSize,
    required FontWeight baseWeight,
    required Color color,
    int maxLines = 1,
    TextOverflow overflow = TextOverflow.ellipsis,
  }) {
    const allWeights = [
      FontWeight.w100, FontWeight.w200, FontWeight.w300, FontWeight.w400,
      FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800, FontWeight.w900,
    ];
    final idx = allWeights.indexOf(baseWeight);
    final jaWeight = idx >= 0
        ? allWeights[(idx + 2).clamp(0, allWeights.length - 1)]
        : baseWeight;

    final japaneseRegex = RegExp(r'[\u3040-\u30FF\u4E00-\u9FFF\uF900-\uFAFF\u3000-\u303F]+');
    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in japaneseRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: TextStyle(fontWeight: baseWeight),
        ));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(fontWeight: jaWeight),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: TextStyle(fontWeight: baseWeight),
      ));
    }

    // 日本語なし → 通常の Text で返す
    if (spans.isEmpty || spans.length == 1 && spans.first.style?.fontWeight == baseWeight) {
      return Text(
        text,
        style: TextStyle(fontSize: fontSize, fontWeight: baseWeight, color: color),
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: fontSize, color: color),
        children: spans,
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  /// 再生ボタン（裏面用 - タップ時のみ表示）
  Widget _buildPlayButton() {
    return StreamBuilder<PlayerState>(
      stream: widget.audioService.playerStateStream,
      builder: (context, snapshot) {
        // audioManagedExternally の場合 _cachedPreviewUrl は null のまま
        // なので externalPreviewUrl を fallback として使用する
        final previewUrl = _cachedPreviewUrl ?? widget.externalPreviewUrl;
        final isThisTrackPlaying = previewUrl != null &&
            widget.audioService.isPlayingUrl(previewUrl);

        return GestureDetector(
          onTap: () => _handlePlayButtonTap(isThisTrackPlaying, previewUrl),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: PostCardConstants.playButtonSize,
            height: PostCardConstants.playButtonSize,
            color: Colors.transparent,
            child: widget.persistentPlayButton
                // 常時表示モード:
                //   停止中 → ▶ を常に表示
                //   再生開始時 → ‖ がポップアップ後に非表示
                //   停止時 → ▶ がポップアップ後に常に表示
                ? Builder(
                    builder: (context) {
                      // 再生状態の変化を検知してアニメーションを制御
                      if (_lastPersistentPlayingState != isThisTrackPlaying) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          if (_lastPersistentPlayingState == isThisTrackPlaying) return;
                          setState(() {
                            _lastPersistentPlayingState = isThisTrackPlaying;
                            _persistentTransitionIcon =
                                isThisTrackPlaying ? Icons.pause : Icons.play_arrow;
                          });
                          _playButtonAnimationController.forward(from: 0.0);
                        });
                      }
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // 停止中は ▶ を常に表示
                          AnimatedOpacity(
                            opacity: isThisTrackPlaying ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 300),
                            child: Container(
                              width: PostCardConstants.playButtonSize,
                              height: PostCardConstants.playButtonSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withOpacity(PostCardConstants.playButtonBackgroundOpacity),
                                border: Border.all(
                                  color: Colors.white,
                                  width: PostCardConstants.playButtonBorderWidth,
                                ),
                              ),
                              child: const Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: PostCardConstants.playButtonIconSize,
                              ),
                            ),
                          ),
                          // 状態変化時のポップアニメーション（▶ or ‖）
                          AnimatedBuilder(
                            animation: _playButtonAnimationController,
                            builder: (context, child) {
                              return Opacity(
                                opacity: _playButtonOpacityAnimation.value,
                                child: Transform.scale(
                                  scale: _playButtonScaleAnimation.value,
                                  child: Container(
                                    width: PostCardConstants.playButtonSize,
                                    height: PostCardConstants.playButtonSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black.withOpacity(PostCardConstants.playButtonBackgroundOpacity),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: PostCardConstants.playButtonBorderWidth,
                                      ),
                                    ),
                                    child: Icon(
                                      _persistentTransitionIcon,
                                      color: Colors.white,
                                      size: PostCardConstants.playButtonIconSize,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  )
                // アニメーションモード（通常）
                : AnimatedBuilder(
                    animation: _playButtonAnimationController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _playButtonOpacityAnimation.value,
                        child: Transform.scale(
                          scale: _playButtonScaleAnimation.value,
                          child: Container(
                            width: PostCardConstants.playButtonSize,
                            height: PostCardConstants.playButtonSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withOpacity(PostCardConstants.playButtonBackgroundOpacity),
                              border: Border.all(
                                color: Colors.white,
                                width: PostCardConstants.playButtonBorderWidth,
                              ),
                            ),
                            child: Icon(
                              isThisTrackPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: PostCardConstants.playButtonIconSize,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
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
                fontSize: 14,
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
    required PostTheme theme,
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
            colorFilter: ColorFilter.mode(
              theme.iconColor,
              BlendMode.srcIn,
            ),
          ),
          if (!widget.hideReactionCounts) ...[
            const SizedBox(width: 4),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 14,
                color: theme.iconColor,
              ),
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
            Icon(
              Icons.send,
              size: 20,
              color: theme.textColor.withOpacity(0.7),
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
              fontSize: 25,
              fontWeight: FontWeight.w700,
              color: theme.textColor,
            ),
          ),
          width: availableWidth,
        ),
        const SizedBox(height: 4),
        _buildWeightAdjustedText(
          widget.post.track.artistName,
          fontSize: 13,
          baseWeight: FontWeight.w400,
          color: theme.textColor,
        ),
      ],
    );
  }

  /// リアクション（いいね、コメント、追加）
  Widget _buildReactions(PostTheme theme) {
    final isLiked = _isLikedOptimistic ??
        (widget.currentUserId != null &&
            widget.post.isLikedBy(widget.currentUserId!));
    final likeCount = _likeCountOptimistic ?? widget.post.likeCount;

    return Row(
      children: [
        // いいね
        _buildReactionItem(
          icon: isLiked ? Icons.favorite : Icons.favorite_border,
          count: likeCount,
          onTap: _handleLikeTap,
          isActive: isLiked,
          theme: theme,
        ),
        SizedBox(width: 15 ),

        // コメント
        _buildCommentReaction(
          count: widget.post.commentCount,
          onTap: widget.onComment,
          theme: theme,
        ),
        SizedBox(width: 15 ),

        // 追加（保存ボタン）
        _buildSaveButton(theme: theme),

        const Spacer(),

        // いいねしたユーザーのアイコン（最大2人）
        _buildLikedUsersIcons(),
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
    // 楽観的UIを使用するか、実際のデータを使用
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

  /// ユーザー情報（表面の下部）
  Widget _buildUserInfo(PostTheme theme) {
    return GestureDetector(
      onTap: () {
        // ユーザープロフィール画面へ遷移
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
        children: [
          // ユーザーアイコン
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

          // ユーザー名
          _buildWeightAdjustedText(
            widget.post.username,
            fontSize: 14,
            baseWeight: FontWeight.w600,
            color: theme.textColor,
          ),
        ],
      ),
    );
  }

  /// 3点メニューボタン（削除 or 通報）
  bool get _showMoreButton =>
      widget.currentUserId != null &&
      (widget.post.userId != widget.currentUserId ||
          widget.onDelete != null);

  bool get _isOwner =>
      widget.currentUserId != null &&
      widget.post.userId == widget.currentUserId;

  Widget _buildMoreButton(PostTheme theme) {
    return SizedBox(
      width: 32,
      height: 36,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_vert, color: theme.iconColor, size: 22),
        color: const Color(0xFF2D2D2D),
        onSelected: (value) async {
          if (value == 'delete') {
            widget.onDelete?.call();
          } else if (value == 'report') {
            await showReportDialog(
              context,
              reportedUserId: widget.post.userId,
              postId: widget.post.postId,
            );
          }
        },
        itemBuilder: (context) => [
          if (_isOwner && widget.onDelete != null)
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: Color(0xFFE53935), size: 20),
                  SizedBox(width: 8),
                  Text('削除', style: TextStyle(color: Color(0xFFE53935))),
                ],
              ),
            ),
          if (!_isOwner)
            const PopupMenuItem(
              value: 'report',
              child: Row(
                children: [
                  Icon(Icons.flag_outlined, color: Color(0xFFE53935), size: 20),
                  SizedBox(width: 8),
                  Text('通報', style: TextStyle(color: Color(0xFFE53935))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 保存ボタン（表面用）
  Widget _buildSaveButton({required PostTheme theme}) {
    return GestureDetector(
      onTap: widget.onAdd,
      child: widget.isSaved
          ? _buildSavedIcon()
          : Icon(
              Icons.add_circle_outline,
              size: 24,
              color: theme.iconColor,
            ),
    );
  }

  /// 保存済みアイコン（緑色の円 + 灰色のチェックマーク）
  Widget _buildSavedIcon() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 背景：明るい緑色の塗りつぶし円
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.lightGreen,
            shape: BoxShape.circle,
          ),
        ),
        // 前景：灰色のチェックマーク
        Icon(
          Icons.check,
          size: 18,
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
}

