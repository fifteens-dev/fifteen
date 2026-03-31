import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import '../models/track_model.dart';
import '../models/post_edit_state.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/lyrics_service.dart';
import '../utils/color_extractor.dart';
import '../utils/current_user_helper.dart';
import '../widgets/post_creation/post_card_back_view.dart';
import '../widgets/post_creation/lyrics_card_layouts.dart';
import 'post_final_preview_screen.dart';
import 'music_selection_screen.dart';

/// 歌詞カード編集 + 音楽再生位置設定の統合画面
class PostCardEditScreen extends StatefulWidget {
  final TrackModel track;
  final XFile? selectedImage;
  final Offset imageOffset;
  final double imageScale;
  final Size? imageNaturalSize;
  final LyricsData? lyricsData;
  final Future<LyricsData?>? lyricsFuture;
  final bool isVibe;
  final String? vibeTopicId;
  final String? vibeTopicTitle;
  // 写真選択画面で事前取得済みのキャッシュ（アニメーション中の setState を防ぐ）
  final String? cachedPreviewUrl;
  final Color? cachedGradientStart;
  final Color? cachedGradientEnd;

  const PostCardEditScreen({
    super.key,
    required this.track,
    this.selectedImage,
    this.imageOffset = Offset.zero,
    this.imageScale = 1.0,
    this.imageNaturalSize,
    this.lyricsData,
    this.lyricsFuture,
    this.isVibe = false,
    this.vibeTopicId,
    this.vibeTopicTitle,
    this.cachedPreviewUrl,
    this.cachedGradientStart,
    this.cachedGradientEnd,
  });

  @override
  State<PostCardEditScreen> createState() => _PostCardEditScreenState();
}

class _PostCardEditScreenState extends State<PostCardEditScreen>
    with SingleTickerProviderStateMixin {
  // ---- Audio ----
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();

  String? _previewUrl;
  bool _isPlaying = false;
  bool _isDragging = false;
  double _playbackProgress = 0.0;
  double _pausedProgress = 0.0;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription? _playerStateSubscription;

  final int _durationSeconds = 15;
  double _startPosition = 0.0; // ローカルのみ（_onNext で _editState に同期）
  final Duration _totalDuration = const Duration(seconds: 30);
  late List<double> _waveformData;

  // ---- Shared edit state（カードの位置・レイアウト等）----
  late PostEditState _editState;

  // ---- 幕フェードアウトアニメーション ----
  late AnimationController _curtainController;
  late Animation<double> _curtainOpacity; // 1.0=幕あり → 0.0=幕なし

  // ---- 拡大アニメーション完了後にオーバーレイを表示するフラグ ----
  bool _overlayVisible = false;

  // ---- アルバムアートから抽出した色（PostFinalPreviewScreen に渡す）----
  Color? _gradientStart;
  Color? _gradientEnd;

  // ---- 現在のトラック（楽曲追加後に更新される）----
  late TrackModel _currentTrack;

  // ---- Lyrics / user info ----
  LyricsData? _lyricsData;
  String _currentUsername = '';
  String? _currentUserIconUrl;
  String? _currentUniversity;

  // ---- アルバムアート透明度 ----
  double _albumArtOpacity = 1.0;

  @override
  void initState() {
    super.initState();

    // 幕フェードアウトアニメーション（0.0=幕なし, 1.0=幕あり）
    _curtainController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
      value: 1.0, // 最初は幕あり
    );
    _curtainOpacity = CurvedAnimation(
      parent: _curtainController,
      curve: Curves.easeOut,
    );

    _currentTrack = widget.track;
    _lyricsData = widget.lyricsData;

    // 事前取得済みの値を同期的に設定（initState 中は setState 不要）
    _previewUrl = widget.cachedPreviewUrl;
    _gradientStart = widget.cachedGradientStart;
    _gradientEnd = widget.cachedGradientEnd;

    final hasTrack = _currentTrack.trackId.isNotEmpty;

    if (hasTrack) {
      // 歌詞・色・プレビューURLの非同期ロードはアニメーション完了後に行う
      // → アニメーション中の setState を避けてカクつきを防止
    }

    _loadCurrentUserInfo();

    // 波形データ生成
    final random = Random(_currentTrack.trackName.hashCode);
    _waveformData = List.generate(60, (_) => 0.15 + random.nextDouble() * 0.85);

    // 波形のピーク位置をデフォルト開始位置に
    int peakIndex = 0;
    double peakValue = 0.0;
    for (int i = 0; i < _waveformData.length; i++) {
      if (_waveformData[i] > peakValue) {
        peakValue = _waveformData[i];
        peakIndex = i;
      }
    }
    final maxStart = 1.0 - _durationSeconds / _totalDuration.inSeconds;
    _startPosition = (peakIndex / _waveformData.length).clamp(0.0, maxStart);

    // 共有編集状態を初期化（カード中心座標は写真エリアの定数から計算）
    _editState = PostEditState(
      selectedLayoutIndex: 1,
      cardCenter: Offset(
        PostCardBackView.cardWidth / 2,
        PostCardBackView.photoHeight * 0.45,
      ),
      cardScale: 1.0,
      cardRotation: 0.0,
      startPosition: _startPosition,
      audioDurationSec: _durationSeconds,
    );

    // 拡大アニメーション完了後にオーバーレイを表示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final animation = ModalRoute.of(context)?.animation;
      if (animation == null || animation.status == AnimationStatus.completed) {
        if (mounted) setState(() => _overlayVisible = true);
        _startDataLoading();
        return;
      }
      animation.addStatusListener(_onRouteAnimationStatus);
    });

    _positionSubscription = _audioService.positionStream.listen((position) {
      if (!mounted || !_isPlaying || _isDragging) return;
      final remainingMs = _durationSeconds * 1000 -
          (_pausedProgress * _durationSeconds * 1000);
      final progress = _pausedProgress +
          (position.inMilliseconds / remainingMs) * (1.0 - _pausedProgress);
      setState(() => _playbackProgress = progress.clamp(0.0, 1.0));
    });

    _playerStateSubscription = _audioService.playerStateStream.listen((state) {
      if (!mounted || _isDragging) return;
      if (state.playing != _isPlaying) setState(() => _isPlaying = state.playing);
    });

    // データロードはアニメーション完了後に _startDataLoading() で行う
  }

  @override
  void dispose() {
    _curtainController.dispose();
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _audioService.stop();
    _editState.dispose();
    super.dispose();
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _overlayVisible = true);
      _startDataLoading();
    }
  }

  /// アニメーション完了後に非同期データロードを開始
  /// （アニメーション中の setState によるカクつきを防ぐ）
  void _startDataLoading() {
    final hasTrack = _currentTrack.trackId.isNotEmpty;
    if (!hasTrack) return;

    // プレビューURL（キャッシュ済みなら再生のみ、未取得なら取得も）
    if (_previewUrl != null) {
      _playFromCurrentPosition();
    } else {
      _loadPreviewUrl();
    }

    // アルバムカラー（キャッシュ済みなら不要）
    if (_gradientStart == null) {
      _extractAlbumColors();
    }

    // 歌詞
    if (widget.lyricsFuture != null && _lyricsData == null) {
      widget.lyricsFuture!.then((data) {
        if (mounted) setState(() => _lyricsData = data);
      });
    } else if (_lyricsData == null) {
      _fetchLyrics();
    }
  }

  Future<void> _loadCurrentUserInfo() async {
    final userInfo = await CurrentUserHelper.load();
    if (mounted) {
      setState(() {
        _currentUsername = userInfo.username;
        _currentUserIconUrl = userInfo.iconUrl;
        _currentUniversity = userInfo.university;
      });
    }
  }

  Future<void> _extractAlbumColors() async {
    try {
      final imageUrl = _currentTrack.albumImageUrl;
      if (imageUrl.isNotEmpty) {
        final colors = await ColorExtractor.extractGradientColors(imageUrl);
        if (mounted) setState(() {
          _gradientStart = colors.$1;
          _gradientEnd = colors.$2;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchLyrics() async {
    try {
      final lyricsService = LyricsService();
      final appleDevToken = dotenv.env['APPLE_MUSIC_DEVELOPER_TOKEN'] ?? '';
      final data = await lyricsService.getLyrics(
        trackName: _currentTrack.trackName,
        artistName: _currentTrack.artistName,
        durationSeconds: null,
        appleDevToken: appleDevToken,
      );
      if (mounted) setState(() => _lyricsData = data);
    } catch (_) {}
  }

  Future<void> _loadPreviewUrl() async {
    String? url = _currentTrack.previewUrl;
    if (url == null || url.isEmpty) {
      url = await _itunesService.getPreviewUrl(
        trackName: _currentTrack.trackName,
        artistName: _currentTrack.artistName,
      );
    }
    if (mounted) {
      setState(() => _previewUrl = url);
      if (url != null) _playFromCurrentPosition();
    }
  }

  void _playFromCurrentPosition() async {
    if (_previewUrl == null) return;
    final resumeOffsetMs = (_pausedProgress * _durationSeconds * 1000).round();
    final startMs =
        (_startPosition * _totalDuration.inMilliseconds).round() + resumeOffsetMs;
    final remainingSeconds =
        _durationSeconds - (resumeOffsetMs / 1000).round();
    setState(() => _isPlaying = true);
    await _audioService.playPreview(
      _previewUrl!,
      startFrom: Duration(milliseconds: startMs),
      durationSeconds: remainingSeconds > 0 ? remainingSeconds : _durationSeconds,
    );
  }

  void _stopPlayback() async {
    setState(() { _isPlaying = false; _pausedProgress = _playbackProgress; });
    await _audioService.stop();
  }

  void _onSeekDragStart() {
    if (_isPlaying) _audioService.stop();
    setState(() {
      _isPlaying = false;
      _isDragging = true;
      _playbackProgress = 0.0;
      _pausedProgress = 0.0;
    });
  }

  void _onSeekDragEnd() {
    setState(() => _isDragging = false);
    _playFromCurrentPosition();
  }

  void _showOpacityPicker() {
    final opacities = [1.0, 0.7, 0.5, 0.3, 0.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ジャケットの透明度',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: opacities.map((opacity) {
                    final isSelected = (_albumArtOpacity - opacity).abs() < 0.01;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _albumArtOpacity = opacity);
                        Navigator.pop(ctx);
                      },
                      child: Column(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isSelected ? Colors.white : Colors.grey.shade700,
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white.withValues(alpha: opacity),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${(opacity * 100).toInt()}%',
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.grey,
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onNext() async {
    if (_curtainController.isAnimating) return;

    _audioService.stop();

    // _startPosition を _editState に同期
    _editState.updateAll(
      selectedLayoutIndex: _editState.selectedLayoutIndex,
      cardCenter: _editState.cardCenter,
      cardScale: _editState.cardScale,
      cardRotation: _editState.cardRotation,
      startPosition: _startPosition,
      audioDurationSec: _durationSeconds,
    );

    final cardSize = PostCardBackView.cardSizeForLayout(_editState.selectedLayoutIndex);
    final cardPos = _editState.cardPositionForSize(cardSize);

    // 幕をフェードアウト（350ms）
    await _curtainController.reverse(); // 1.0 → 0.0
    if (!mounted) return;

    // 幕が消えた後、下画面のカードをそのまま見せながら即座に遷移
    await Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false, // 下画面（PostCardEditScreen）を透過して残す
        pageBuilder: (_, __, ___) => PostFinalPreviewScreen(
          track: _currentTrack,
          selectedImage: widget.selectedImage,
          imageOffset: widget.imageOffset,
          imageScale: widget.imageScale,
          imageNaturalSize: widget.imageNaturalSize,
          selectedLayoutIndex: _editState.selectedLayoutIndex,
          cardPosition: cardPos,
          cardScale: _editState.cardScale,
          cardRotation: _editState.cardRotation,
          isVibe: widget.isVibe,
          vibeTopicId: widget.vibeTopicId,
          vibeTopicTitle: widget.vibeTopicTitle,
          lyricsData: _lyricsData,
          audioStartMs: _editState.audioStartMs,
          audioDurationSec: _durationSeconds,
          preExtractedGradientStart: _gradientStart,
          preExtractedGradientEnd: _gradientEnd,
          initialUsername: _currentUsername,
          initialUserIconUrl: _currentUserIconUrl,
          initialUniversity: _currentUniversity,
          albumArtOpacity: _albumArtOpacity,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (_, __, ___, child) => child,
      ),
    );

    // 戻ったときに幕を元に戻す
    if (mounted) _curtainController.forward();
  }

  /// 楽曲選択画面を開き、選択結果でトラックを更新する
  Future<void> _openMusicSelection() async {
    _audioService.stop();
    final result = await Navigator.push<TrackModel>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MusicSelectionScreen(isPickerMode: true),
        transitionsBuilder: (context, animation, _, child) {
          return SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeOutCubic))
                .animate(animation),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 250),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _currentTrack = result;
        _previewUrl = null;
        _isPlaying = false;
        _playbackProgress = 0.0;
        _pausedProgress = 0.0;
        // 新しいトラックの波形を生成
        final rng = Random(result.trackName.hashCode);
        _waveformData = List.generate(60, (_) => 0.15 + rng.nextDouble() * 0.85);
        int peak = 0;
        double peakVal = 0.0;
        for (int i = 0; i < _waveformData.length; i++) {
          if (_waveformData[i] > peakVal) { peakVal = _waveformData[i]; peak = i; }
        }
        final maxStart = 1.0 - _durationSeconds / _totalDuration.inSeconds;
        _startPosition = (peak / _waveformData.length).clamp(0.0, maxStart);
      });
      _loadPreviewUrl();
      _fetchLyrics();
      _extractAlbumColors();
    }
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // ① カード（横幅目一杯、両端1px余白）
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 50), // ヘッダー分
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final cardW = MediaQuery.of(context).size.width - 2;
                        final cardH = cardW * (PostCardBackView.cardHeight / PostCardBackView.cardWidth);
                        return Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: SizedBox(
                              width: cardW,
                              height: cardH,
                              child: FittedBox(
                                fit: BoxFit.fill,
                                child: SizedBox(
                                  width: PostCardBackView.cardWidth,
                                  height: PostCardBackView.cardHeight,
                                  child: PostCardBackView(
                              track: _currentTrack,
                              selectedImage: widget.selectedImage,
                              imageOffset: widget.imageOffset,
                              imageScale: widget.imageScale,
                              imageNaturalSize: widget.imageNaturalSize,
                              editState: _editState,
                              lyricsData: _lyricsData,
                              username: _currentUsername,
                              userIconUrl: _currentUserIconUrl,
                              isVibe: widget.isVibe,
                              vibeTopicTitle: widget.vibeTopicTitle,
                              preExtractedGradientStart: _gradientStart,
                              preExtractedGradientEnd: _gradientEnd,
                              showLyricsCard: false,
                              photoOverlaysBefore: [
                                Positioned.fill(
                                  child: GestureDetector(
                                    onTap: _showOpacityPicker,
                                    behavior: HitTestBehavior.translucent,
                                  ),
                                ),
                              ],
                              photoOverlaysAfter: const [],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ② 画面全体の薄暗幕（アニメーション後に表示、完了時にフェードアウト）
          if (_overlayVisible)
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: _curtainOpacity,
                  child: const ColoredBox(color: Color(0x80000000)),
                ),
              ),
            ),

          // ③ 歌詞カード（幕の上・カード座標→スクリーン座標変換）
          if (_overlayVisible)
            Builder(builder: (context) {
              final screenW = MediaQuery.of(context).size.width;
              final safeTop = MediaQuery.of(context).padding.top;
              final scale = (screenW - 2) / PostCardBackView.cardWidth;
              return ListenableBuilder(
                listenable: _editState,
                builder: (context, _) {
                  final lyricsText = _lyricsData != null
                      ? LyricsService().truncateLyrics(
                          _lyricsData!.plainLyrics, maxLines: 4)
                      : null;
                  final layoutType = LyricsCardLayout.getLayoutType(
                      _editState.selectedLayoutIndex);
                  final cardSize = PostCardBackView.cardSizeForLayout(
                      _editState.selectedLayoutIndex);
                  final cardPos = _editState.cardPositionForSize(cardSize);
                  return Positioned(
                    left: 1 + cardPos.dx * scale,
                    top: safeTop + 50 + cardPos.dy * scale,
                    child: IgnorePointer(
                      child: Transform.scale(
                          scale: _editState.cardScale * scale,
                          alignment: Alignment.topLeft,
                          child: Transform.rotate(
                            angle: _editState.cardRotation,
                            alignment: Alignment.center,
                            child: LyricsCardLayout(
                              layoutType: layoutType,
                              track: _currentTrack,
                              lyricsText: lyricsText,
                              albumArtOpacity: _albumArtOpacity,
                            ),
                          ),
                        ),
                      ),
                  );
                },
              );
            }),

          // ④ 選択コントロール（幕の上・写真エリア下端に配置）
          if (_overlayVisible)
            Builder(builder: (context) {
              final mq = MediaQuery.of(context);
              final screenW = mq.size.width;
              final screenH = mq.size.height;
              final safeTop = mq.padding.top;
              final scale = (screenW - 2) / PostCardBackView.cardWidth;
              // 写真エリア下端のスクリーン座標
              final photoAreaBottom = safeTop + 50 + PostCardBackView.photoHeight * scale;
              final bottomOffset = screenH - photoAreaBottom;
              return Positioned(
                left: 0,
                right: 0,
                bottom: bottomOffset,
                child: FadeTransition(
                  opacity: _curtainOpacity,
                  child: _buildEmbeddedControls(),
                ),
              );
            }),

          // ④ ヘッダーオーバーレイ（Hero で固定 — 常に表示）
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Hero(
                tag: 'post_flow_header',
                flightShuttleBuilder: (_, __, ___, ____, _____) =>
                    const Material(
                      color: Colors.transparent,
                      child: SizedBox(
                        height: 50,
                        child: Center(
                          child: Text(
                            '新規投稿',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                child: Material(
                  color: Colors.transparent,
                  child: _buildHeader(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Text(
              '新規投稿',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            Positioned.fill(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () {
                      _audioService.stop();
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'キャンセル',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  GestureDetector(
                    onTap: _onNext,
                    child: const Text(
                      '完了',
                      style: TextStyle(
                          color: Color(0xFF5D8FFF),
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// カードの写真エリア内に埋め込むコントロール（オーバーレイの上）
  Widget _buildEmbeddedControls() {
    final hasTrack = _currentTrack.trackId.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLayoutOptions(),
          const SizedBox(height: 28),
          if (hasTrack) ...[
            _buildTrimControls(),
            const SizedBox(height: 8),
            _buildWaveform(),
            const SizedBox(height: 4),
          ] else
            _buildAddMusicButton(),
        ],
      ),
    );
  }

  Widget _buildAddMusicButton() {
    return GestureDetector(
      onTap: _openMusicSelection,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white38, width: 1),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note, color: Colors.white70, size: 18),
            SizedBox(width: 8),
            Text(
              '音楽を追加',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayoutOptions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(4, (i) {
          final index = i + 1;
          final isSelected = _editState.selectedLayoutIndex == index;
          return GestureDetector(
            onTap: () {
              _editState.setLayout(index); // notifyListeners 内包
              setState(() {}); // コントロールパネルの選択状態を更新
            },
            child: SizedBox(
              width: 33,
              height: 33,
              child: SvgPicture.asset(
                'assets/icons/lyrics/layout_${index + 1}_${isSelected ? 'selected' : 'unselected'}.svg',
                width: 33,
                height: 33,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTrimControls() {
    final maxStart = 1.0 - (_durationSeconds / _totalDuration.inSeconds);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white54, width: 1.5),
            ),
            child: Center(
              child: Text(
                '$_durationSeconds',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              final selWidth =
                  barWidth * (_durationSeconds / _totalDuration.inSeconds);
              return GestureDetector(
                onHorizontalDragStart: (_) => _onSeekDragStart(),
                onHorizontalDragUpdate: (d) {
                  setState(() {
                    _startPosition =
                        (_startPosition + d.delta.dx / barWidth)
                            .clamp(0.0, maxStart.clamp(0.0, 1.0));
                  });
                },
                onHorizontalDragEnd: (_) => _onSeekDragEnd(),
                child: SizedBox(
                  height: 32,
                  child: CustomPaint(
                    size: Size(barWidth, 32),
                    painter: _SeekBarPainter(
                      startPosition: _startPosition,
                      selectionWidth: selWidth,
                      barWidth: barWidth,
                      playbackProgress:
                          _isPlaying ? _playbackProgress : _pausedProgress,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _isPlaying ? _stopPlayback : _playFromCurrentPosition,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white54, width: 1.5),
              ),
              child: Icon(
                _isPlaying ? Icons.stop : Icons.play_arrow,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveform() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 42,
        child: LayoutBuilder(builder: (context, constraints) {
          final barWidth = constraints.maxWidth;
          return CustomPaint(
            size: Size(barWidth, 42),
            painter: _WaveformPainter(
              waveformData: _waveformData,
              selectionStart: _startPosition * barWidth,
              selectionWidth:
                  (_durationSeconds / _totalDuration.inSeconds) * barWidth,
              totalWidth: barWidth,
            ),
          );
        }),
      ),
    );
  }
}

// ---- Painters ----

class _SeekBarPainter extends CustomPainter {
  final double startPosition;
  final double selectionWidth;
  final double barWidth;
  final double playbackProgress;

  _SeekBarPainter({
    required this.startPosition,
    required this.selectionWidth,
    required this.barWidth,
    required this.playbackProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    canvas.drawLine(
        Offset(0, cy),
        Offset(size.width, cy),
        Paint()
          ..color = const Color(0xFF3C3C3C)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);

    final selL = startPosition * barWidth;
    final selR = selL + selectionWidth;
    canvas.drawLine(
        Offset(selL, cy),
        Offset(selR, cy),
        Paint()
          ..color = const Color(0xFF666666)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);

    if (playbackProgress > 0) {
      final progressEnd = selL + selectionWidth * playbackProgress;
      canvas.drawLine(
          Offset(selL, cy),
          Offset(progressEnd, cy),
          Paint()
            ..shader = const LinearGradient(
                    colors: [Color(0xFFFF6B35), Color(0xFFFF3D9A)])
                .createShader(Rect.fromLTRB(selL, 0, selR, 0))
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round);
    }

    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(selL + selectionWidth / 2, cy),
                width: 28,
                height: 12),
            const Radius.circular(6)),
        Paint()..color = Colors.white);

    final dotPaint = Paint()..color = const Color(0xFFFF6B9D);
    canvas.drawCircle(Offset(selL, cy), 4, dotPaint);
    canvas.drawCircle(Offset(selR, cy), 4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _SeekBarPainter old) =>
      old.startPosition != startPosition ||
      old.selectionWidth != selectionWidth ||
      old.playbackProgress != playbackProgress;
}

class _WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double selectionStart;
  final double selectionWidth;
  final double totalWidth;

  _WaveformPainter({
    required this.waveformData,
    required this.selectionStart,
    required this.selectionWidth,
    required this.totalWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = waveformData.length;
    final barSpacing = totalWidth / barCount;
    final barW = barSpacing * 0.6;
    final maxH = size.height * 0.9;
    final cy = size.height / 2;
    final selEnd = selectionStart + selectionWidth;

    for (int i = 0; i < barCount; i++) {
      final x = i * barSpacing + barSpacing / 2;
      final h = waveformData[i] * maxH;
      final isInSel = x >= selectionStart && x <= selEnd;
      final paint = Paint()
        ..color = isInSel
            ? Color.lerp(
                const Color(0xFFFF6B35),
                const Color(0xFFFF3D9A),
                (x - selectionStart) / selectionWidth)!
            : const Color(0xFF4A4A4A);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x - barW / 2, cy - h / 2, barW, h),
              const Radius.circular(2)),
          paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.selectionStart != selectionStart ||
      old.selectionWidth != selectionWidth;
}

