import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../models/track_model.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/lyrics_service.dart';
import 'lyrics_card_selection_screen.dart';

/// 音楽カット編集画面
/// 再生開始位置と再生時間(15/30秒)を編集する
class MusicTrimScreen extends StatefulWidget {
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

  const MusicTrimScreen({
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
  });

  @override
  State<MusicTrimScreen> createState() => _MusicTrimScreenState();
}

class _MusicTrimScreenState extends State<MusicTrimScreen> {
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();

  String? _previewUrl;
  bool _isPlaying = false;
  bool _isDragging = false; // ドラッグ中フラグ

  // 再生進捗（0.0〜1.0、選択区間内での比率）
  double _playbackProgress = 0.0;
  double _pausedProgress = 0.0; // 停止時の進捗を保持
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription? _playerStateSubscription;

  // 再生設定
  int _durationSeconds = 15; // 15 or 30
  double _startPosition = 0.0; // 0.0〜1.0（楽曲全体に対する比率）
  final Duration _totalDuration = const Duration(seconds: 30); // iTunes previewは30秒

  // 波形データ（ダミー）
  late List<double> _waveformData;

  // プレビュー用定数
  static const double _previewW = 363.0;
  static const double _previewH = 484.0;

  LyricsData? _lyricsData;

  @override
  void initState() {
    super.initState();
    _lyricsData = widget.lyricsData;

    if (widget.lyricsFuture != null) {
      widget.lyricsFuture!.then((data) {
        if (mounted) setState(() => _lyricsData = data);
      });
    }

    // ダミー波形データ生成
    final random = Random(widget.track.trackName.hashCode);
    _waveformData = List.generate(60, (_) => 0.15 + random.nextDouble() * 0.85);

    // 再生位置の監視
    _positionSubscription = _audioService.positionStream.listen((position) {
      if (!mounted || !_isPlaying || _isDragging) return;
      final remainingDurationMs = _durationSeconds * 1000 - (_pausedProgress * _durationSeconds * 1000);
      final progress = _pausedProgress +
          (position.inMilliseconds / remainingDurationMs) * (1.0 - _pausedProgress);
      setState(() {
        _playbackProgress = progress.clamp(0.0, 1.0);
      });
    });

    // 再生状態の監視（UIを常にリンク）
    _playerStateSubscription = _audioService.playerStateStream.listen((state) {
      if (!mounted || _isDragging) return;
      final playing = state.playing;
      if (playing != _isPlaying) {
        setState(() => _isPlaying = playing);
      }
    });

    _loadPreviewUrl();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _audioService.stop();
    super.dispose();
  }

  Future<void> _loadPreviewUrl() async {
    // まずTrackModelのpreviewUrlを試す
    String? url = widget.track.previewUrl;

    if (url == null || url.isEmpty) {
      url = await _itunesService.getPreviewUrl(
        trackName: widget.track.trackName,
        artistName: widget.track.artistName,
      );
    }

    if (mounted) {
      setState(() {
        _previewUrl = url;
      });

      // 自動再生
      if (url != null) {
        _playFromCurrentPosition();
      }
    }
  }

  void _playFromCurrentPosition() async {
    if (_previewUrl == null) return;

    // 保持した停止位置から再開
    final resumeOffsetMs = (_pausedProgress * _durationSeconds * 1000).round();
    final startMs = (_startPosition * _totalDuration.inMilliseconds).round() + resumeOffsetMs;
    final startFrom = Duration(milliseconds: startMs);
    final remainingSeconds = _durationSeconds - (resumeOffsetMs / 1000).round();

    setState(() {
      _isPlaying = true;
    });

    await _audioService.playPreview(
      _previewUrl!,
      startFrom: startFrom,
      durationSeconds: remainingSeconds > 0 ? remainingSeconds : _durationSeconds,
    );
  }

  void _stopPlayback() async {
    // 現在の進捗を保持
    setState(() {
      _isPlaying = false;
      _pausedProgress = _playbackProgress;
    });
    await _audioService.stop();
  }


  /// ドラッグ開始: 音楽を停止、進捗リセット
  void _onDragStart() {
    if (_isPlaying) {
      _audioService.stop();
      setState(() {
        _isPlaying = false;
        _isDragging = true;
        _playbackProgress = 0.0;
        _pausedProgress = 0.0;
      });
    } else {
      setState(() {
        _isDragging = true;
        _playbackProgress = 0.0;
        _pausedProgress = 0.0;
      });
    }
  }

  /// ドラッグ終了: 再生を再開
  void _onDragEnd() {
    setState(() => _isDragging = false);
    // ドラッグ前に再生中だった、または常に再生再開
    _playFromCurrentPosition();
  }

  /// 「完了」→次の画面(LyricsCardSelectionScreen)へ
  Future<void> _onComplete() async {
    _audioService.stop();

    final audioStartMs = (_startPosition * _totalDuration.inMilliseconds).round();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LyricsCardSelectionScreen(
          track: widget.track,
          lyricsData: _lyricsData,
          selectedImage: widget.selectedImage,
          imageOffset: widget.imageOffset,
          imageScale: widget.imageScale,
          imageNaturalSize: widget.imageNaturalSize,
          isVibe: widget.isVibe,
          vibeTopicId: widget.vibeTopicId,
          vibeTopicTitle: widget.vibeTopicTitle,
          audioStartMs: audioStartMs,
          audioDurationSec: _durationSeconds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    _buildPhotoPreview(),
                    const SizedBox(height: 24),
                    _buildTrackInfo(),
                    const SizedBox(height: 20),
                    _buildTrimControls(),
                    const SizedBox(height: 16),
                    _buildWaveform(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ヘッダー
  Widget _buildHeader() {
    return SizedBox(
      height: 50,
      child: Stack(
        children: [
          // タイトル（画面幅の中央）
          const Center(
            child: Text(
              '音楽を追加',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // 左右ボタン
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                        color: Color(0xFF5D8FFF),
                        fontSize: 16,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _onComplete,
                    child: const Text(
                      '完了',
                      style: TextStyle(
                        color: Color(0xFF5D8FFF),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 写真プレビュー
  Widget _buildPhotoPreview() {
    return Container(
      width: _previewW,
      height: _previewH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF2B2B2B),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: widget.selectedImage != null && widget.imageNaturalSize != null
            ? _buildTransformedImage()
            : const Center(
                child: Icon(
                  Icons.photo,
                  size: 60,
                  color: Colors.white38,
                ),
              ),
      ),
    );
  }

  Widget _buildTransformedImage() {
    final baseScale = max(
      _previewW / widget.imageNaturalSize!.width,
      _previewH / widget.imageNaturalSize!.height,
    );
    final displayW = widget.imageNaturalSize!.width * baseScale;
    final displayH = widget.imageNaturalSize!.height * baseScale;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Container(color: Colors.black),
        Positioned(
          left: widget.imageOffset.dx,
          top: widget.imageOffset.dy,
          child: Transform.scale(
            scale: widget.imageScale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: displayW,
              height: displayH,
              child: kIsWeb
                  ? Image.network(widget.selectedImage!.path, fit: BoxFit.fill)
                  : Image.file(File(widget.selectedImage!.path), fit: BoxFit.fill, gaplessPlayback: true),
            ),
          ),
        ),
      ],
    );
  }

  /// 曲情報
  Widget _buildTrackInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // アルバムアート
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: Colors.grey[800],
            ),
            child: widget.track.albumImageUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: widget.track.albumImageUrl,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(Icons.album, color: Colors.white54, size: 24),
                    ),
                  )
                : const Icon(Icons.album, color: Colors.white54, size: 24),
          ),
          const SizedBox(width: 12),
          // 曲名・アーティスト
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.track.trackName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.track.artistName,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// カットコントロール（時間トグル + シークバー + 停止ボタン）
  Widget _buildTrimControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // 時間トグルボタン
          _buildDurationButton(_durationSeconds),
          const SizedBox(width: 12),
          // シークバー
          Expanded(child: _buildSeekBar()),
          const SizedBox(width: 12),
          // 再生/停止ボタン
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

  /// 再生時間ボタン（15秒固定）
  Widget _buildDurationButton(int seconds) {
    return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white54, width: 1.5),
        ),
        child: Center(
          child: Text(
            '$seconds',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
    );
  }

  /// シークバー（再生進捗ゲージ付き）
  Widget _buildSeekBar() {
    final maxStart = 1.0 - (_durationSeconds / _totalDuration.inSeconds);

    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.maxWidth;
        final selectionRatio = _durationSeconds / _totalDuration.inSeconds;
        final selectionWidth = barWidth * selectionRatio;

        return GestureDetector(
          onHorizontalDragStart: (_) => _onDragStart(),
          onHorizontalDragUpdate: (details) {
            setState(() {
              _startPosition = (_startPosition + details.delta.dx / barWidth)
                  .clamp(0.0, maxStart.clamp(0.0, 1.0));
            });
          },
          onHorizontalDragEnd: (_) => _onDragEnd(),
          child: SizedBox(
            height: 32,
            child: CustomPaint(
              size: Size(barWidth, 32),
              painter: _SeekBarPainter(
                startPosition: _startPosition,
                selectionWidth: selectionWidth,
                barWidth: barWidth,
                playbackProgress: _isPlaying ? _playbackProgress : _pausedProgress,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 波形ビジュアル
  Widget _buildWaveform() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        height: 48,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = constraints.maxWidth;
            final selectionRatio = _durationSeconds / _totalDuration.inSeconds;
            final selectionStartPx = _startPosition * barWidth;
            final selectionWidthPx = selectionRatio * barWidth;

            return CustomPaint(
              size: Size(barWidth, 48),
              painter: _WaveformPainter(
                waveformData: _waveformData,
                selectionStart: selectionStartPx,
                selectionWidth: selectionWidthPx,
                totalWidth: barWidth,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// シークバー描画（再生進捗ゲージ付き）
class _SeekBarPainter extends CustomPainter {
  final double startPosition;
  final double selectionWidth;
  final double barWidth;
  final double playbackProgress; // 0.0〜1.0

  _SeekBarPainter({
    required this.startPosition,
    required this.selectionWidth,
    required this.barWidth,
    required this.playbackProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;

    // 背景バー
    final bgPaint = Paint()
      ..color = const Color(0xFF3C3C3C)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), bgPaint);

    // 選択区間
    final selectionLeft = startPosition * barWidth;
    final selectionRight = selectionLeft + selectionWidth;

    // 選択区間ベース（白）
    final selectionPaint = Paint()
      ..color = const Color(0xFF666666)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(selectionLeft, cy), Offset(selectionRight, cy), selectionPaint);

    // 再生済み部分（グラデーションで色づく）
    if (playbackProgress > 0) {
      final progressEnd = selectionLeft + selectionWidth * playbackProgress;
      final gradient = const LinearGradient(
        colors: [Color(0xFFFF6B35), Color(0xFFFF3D9A)],
      ).createShader(Rect.fromLTRB(selectionLeft, 0, selectionRight, 0));
      final progressPaint = Paint()
        ..shader = gradient
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(selectionLeft, cy), Offset(progressEnd, cy), progressPaint);
    }

    // ドラッグハンドル（中央のつまみ）
    final handleX = selectionLeft + selectionWidth / 2;
    final handlePaint = Paint()..color = Colors.white;
    final handleRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(handleX, cy), width: 28, height: 12),
      const Radius.circular(6),
    );
    canvas.drawRRect(handleRect, handlePaint);

    // 選択区間の端のドット
    final dotPaint = Paint()..color = const Color(0xFFFF6B9D);
    canvas.drawCircle(Offset(selectionLeft, cy), 4, dotPaint);
    canvas.drawCircle(Offset(selectionRight, cy), 4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _SeekBarPainter oldDelegate) {
    return oldDelegate.startPosition != startPosition ||
        oldDelegate.selectionWidth != selectionWidth ||
        oldDelegate.playbackProgress != playbackProgress;
  }
}

/// 波形描画
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

    final selectionEnd = selectionStart + selectionWidth;

    // グラデーション色
    const gradientStart = Color(0xFFFF6B35); // オレンジ
    const gradientEnd = Color(0xFFFF3D9A); // ピンク

    for (int i = 0; i < barCount; i++) {
      final x = i * barSpacing + barSpacing / 2;
      final h = waveformData[i] * maxH;
      final top = cy - h / 2;

      final isInSelection = x >= selectionStart && x <= selectionEnd;

      Paint paint;
      if (isInSelection) {
        // 選択区間内: グラデーション
        final t = (x - selectionStart) / selectionWidth;
        paint = Paint()
          ..color = Color.lerp(gradientStart, gradientEnd, t)!;
      } else {
        // 選択区間外: グレー
        paint = Paint()..color = const Color(0xFF4A4A4A);
      }

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - barW / 2, top, barW, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.selectionStart != selectionStart ||
        oldDelegate.selectionWidth != selectionWidth;
  }
}
