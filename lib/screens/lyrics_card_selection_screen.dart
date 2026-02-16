import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track_model.dart';
import '../services/lyrics_service.dart';
import '../utils/current_user_helper.dart';
import '../widgets/shared/user_info_badge.dart';
import 'package:image_picker/image_picker.dart';

/// 歌詞カード選択画面
class LyricsCardSelectionScreen extends StatefulWidget {
  final TrackModel track;
  final LyricsData? lyricsData;
  final XFile? selectedImage;
  final bool isVibe;
  final String? vibeTopicId;
  final String? vibeTopicTitle;

  const LyricsCardSelectionScreen({
    super.key,
    required this.track,
    this.lyricsData,
    this.selectedImage,
    this.isVibe = false,
    this.vibeTopicId,
    this.vibeTopicTitle,
  });

  @override
  State<LyricsCardSelectionScreen> createState() =>
      _LyricsCardSelectionScreenState();
}

class _LyricsCardSelectionScreenState
    extends State<LyricsCardSelectionScreen> {
  String _currentUsername = '';
  String? _currentUserIconUrl;

  int _selectedLayoutIndex = 0; // 選択されたレイアウト (0-4)
  Offset _cardCenter = const Offset(180, 200); // カード中央座標
  double _cardScale = 1.0; // 拡大率
  double _cardRotation = 0.0; // 回転角度（ラジアン）
  bool _isTwoFingerGesture = false; // 2本指操作中フラグ
  // ジェスチャー開始時の値保持
  double _startScale = 1.0;
  double _startRotation = 0.0;
  // スナップ補助線用
  static const List<double> _snapDegrees = [45, 135, 225, 315];
  static const double _snapThreshold = 3.0; // 度
  Set<double> _activeSnapAngles = {};
  Set<double> _prevSnapAngles = {};
  // ジェスチャー中のカード再描画用（setStateを避けて高速化）
  final ValueNotifier<int> _gestureNotifier = ValueNotifier<int>(0);

  LyricsData? _lyricsData; // 取得した歌詞データ
  bool _isLoadingLyrics = false; // 歌詞取得中フラグ

  @override
  void initState() {
    super.initState();
    _lyricsData = widget.lyricsData;
    _loadCurrentUserInfo();

    // 歌詞がまだ取得されていない場合はバックグラウンドで取得
    if (_lyricsData == null) {
      print('⚠️ 歌詞が未取得のため、歌詞カード画面で取得を開始します');
      _fetchLyrics();
    } else {
      print('✅ 既に取得済みの歌詞を使用します (${_lyricsData!.source})');
    }
  }

  @override
  void dispose() {
    _gestureNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserInfo() async {
    final userInfo = await CurrentUserHelper.load();
    if (mounted) {
      setState(() {
        _currentUsername = userInfo.username;
        _currentUserIconUrl = userInfo.iconUrl;
      });
    }
  }

  /// 歌詞を取得（バックグラウンド）
  Future<void> _fetchLyrics() async {
    setState(() {
      _isLoadingLyrics = true;
    });

    try {
      print('🎵 歌詞カード画面で歌詞取得を開始...');
      final lyricsService = LyricsService();
      final appleDevToken = dotenv.env['APPLE_MUSIC_DEVELOPER_TOKEN'] ?? '';

      final lyricsData = await lyricsService.getLyrics(
        trackName: widget.track.trackName,
        artistName: widget.track.artistName,
        durationSeconds: null,
        appleDevToken: appleDevToken,
      );

      if (mounted) {
        setState(() {
          _lyricsData = lyricsData;
          _isLoadingLyrics = false;
        });

        if (lyricsData != null) {
          print('✅ 歌詞取得完了: ${lyricsData.source}');
        } else {
          print('⚠️ 歌詞が見つかりませんでした');
        }
      }
    } catch (e) {
      print('⚠️ 歌詞取得エラー: $e');
      if (mounted) {
        setState(() {
          _isLoadingLyrics = false;
        });
      }
    }
  }

  /// 歌詞カードに表示する歌詞テキストを取得
  String get _displayLyrics {
    if (_isLoadingLyrics) {
      // 歌詞取得中
      return '歌詞を取得中...';
    }

    if (_lyricsData != null) {
      // 取得した歌詞を4行に短縮
      final lyricsService = LyricsService();
      return lyricsService.truncateLyrics(
        _lyricsData!.plainLyrics,
        maxLines: 4,
      );
    }

    // 歌詞が見つからなかった場合
    return '歌詞が見つかりませんでした';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            _buildHeader(),

            const SizedBox(height: 20),

            // メインコンテンツ
            Expanded(
              child: Stack(
                children: [
                  // 背景の投稿カードプレビュー
                  _buildBackgroundPreview(),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // 下部のレイアウト選択ツールバー
            _buildLayoutOptions(),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// ヘッダー
  Widget _buildHeader() {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 19),
      child: Row(
        children: [
          // 戻るボタン
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: 27,
                ),
              ),
            ),
          ),

          // タイトル
          const Text(
            '新規投稿',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),

          // スペーサー
          const Expanded(child: SizedBox()),
        ],
      ),
    );
  }

  /// 背景の投稿カードプレビュー
  Widget _buildBackgroundPreview() {
    const photoHeight = 484.0;

    return Center(
      child: Container(
        width: 363,
        height: photoHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          border: Border.all(color: Colors.white, width: 0.5),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
          ),
          child: Stack(
            children: [
              // 選択された写真を表示（静的・再構築不要）
              if (widget.selectedImage != null)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: kIsWeb
                        ? Image.network(
                            widget.selectedImage!.path,
                            fit: BoxFit.cover,
                          )
                        : Image.file(
                            File(widget.selectedImage!.path),
                            fit: BoxFit.cover,
                          ),
                  ),
                )
              else
                Container(
                  color: const Color(0xFF121212),
                ),

              // 歌詞カード + 補助線（ジェスチャー中はここだけ再描画）
              ValueListenableBuilder<int>(
                valueListenable: _gestureNotifier,
                builder: (context, _, child) {
                  // カード中央座標からPositionedの左上を計算
                  final cardSize = _getCardSize();
                  final paddedW = cardSize.width + 2 * _hitPadding;
                  final paddedH = cardSize.height + 2 * _hitPadding;

                  return Stack(
                    children: [
                      // 歌詞カードプレビュー
                      Positioned(
                        left: _cardCenter.dx - paddedW / 2,
                        top: _cardCenter.dy - paddedH / 2,
                        child: GestureDetector(
                          onScaleStart: _onGestureScaleStart,
                          onScaleUpdate: _onGestureScaleUpdate,
                          onScaleEnd: _onGestureScaleEnd,
                          child: Transform.scale(
                            scale: _cardScale,
                            alignment: Alignment.center,
                            child: Transform.rotate(
                              angle: _cardRotation,
                              alignment: Alignment.center,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: child!,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 補助線
                      if (_isTwoFingerGesture)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _GuideLinePainter(activeSnapAngles: _activeSnapAngles),
                          ),
                        ),
                    ],
                  );
                },
                // child は layout ウィジェット（ジェスチャーで再構築不要）
                child: _buildCurrentLayout(),
              ),

              // ユーザー情報（静的・再構築不要）
              Positioned(
                left: 15,
                top: 15,
                child: UserInfoBadge(
                  username: _currentUsername.isNotEmpty ? _currentUsername : 'ユーザー',
                  iconUrl: _currentUserIconUrl,
                  hashtagText: widget.isVibe && widget.vibeTopicTitle != null
                      ? '#${widget.vibeTopicTitle}'
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 当たり判定拡張パディング
  static const double _hitPadding = 40.0;

  /// カードサイズを取得（レイアウトごとに異なる）
  Size _getCardSize() {
    switch (_selectedLayoutIndex) {
      case 0:
        return const Size(196, 126);
      case 1:
        return const Size(105, 147);
      case 2:
        return const Size(172, 42);
      case 3:
        return const Size(140, 152);
      case 4:
        return const Size(130, 61);
      default:
        return const Size(196, 126);
    }
  }

  /// 現在選択中のレイアウトウィジェットを返す（当たり判定拡張付き）
  Widget _buildCurrentLayout() {
    Widget layout;
    switch (_selectedLayoutIndex) {
      case 0:
        layout = _buildLayout1();
        break;
      case 1:
        layout = _buildLayout2();
        break;
      case 2:
        layout = _buildLayout3();
        break;
      case 3:
        layout = _buildLayout4();
        break;
      case 4:
        layout = _buildLayout5();
        break;
      default:
        layout = _buildLayout1();
    }
    return Padding(
      padding: const EdgeInsets.all(_hitPadding),
      child: layout,
    );
  }

  /// ジェスチャーコールバック（setStateを使わず ValueNotifier で通知）
  void _onGestureScaleStart(ScaleStartDetails details) {
    _startScale = _cardScale;
    _startRotation = _cardRotation;
    if (details.pointerCount >= 2) {
      _isTwoFingerGesture = true;
      _gestureNotifier.value++;
    }
  }

  void _onGestureScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      _isTwoFingerGesture = true;
      _cardScale = (_startScale * details.scale).clamp(0.3, 3.0);
      _cardRotation = _startRotation + details.rotation;

      // スナップ角度の検知
      double deg = (_cardRotation * 180 / pi) % 360;
      if (deg < 0) deg += 360;
      final newSnaps = <double>{};
      for (final snapDeg in _snapDegrees) {
        double diff = (deg - snapDeg).abs();
        if (diff > 180) diff = 360 - diff;
        if (diff <= _snapThreshold) {
          newSnaps.add(snapDeg);
        }
      }
      if (newSnaps.isNotEmpty && !newSnaps.every((a) => _prevSnapAngles.contains(a))) {
        HapticFeedback.lightImpact();
      }
      _prevSnapAngles = newSnaps;
      _activeSnapAngles = newSnaps;
    }
    _cardCenter = Offset(
      _cardCenter.dx + details.focalPointDelta.dx,
      _cardCenter.dy + details.focalPointDelta.dy,
    );
    _gestureNotifier.value++;
  }

  void _onGestureScaleEnd(ScaleEndDetails details) {
    _isTwoFingerGesture = false;
    _activeSnapAngles = {};
    _prevSnapAngles = {};
    _gestureNotifier.value++;
  }

  /// レイアウト1：標準（歌詞 + トラック情報）
  Widget _buildLayout1() {
    return Container(
        width: 196,
        height: 126,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.52),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            // 上部：歌詞エリア
            Expanded(
              flex: 60,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color.fromRGBO(0, 0, 0, 0.29),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(10),
                    topRight: Radius.circular(10),
                  ),
                ),
                padding: const EdgeInsets.all(11),
                child: Center(
                  child: Text(
                    _displayLyrics,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
              ),
            ),

            // 下部：トラック情報エリア
            Expanded(
              flex: 40,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.52),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: Row(
                  children: [
                    // アルバムアートワーク
                    Container(
                      width: 36,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF9F9F9F),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: widget.track.albumImageUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: CachedNetworkImage(
                                imageUrl: widget.track.albumImageUrl,
                                fit: BoxFit.cover,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    // 楽曲情報
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.track.trackName,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.track.artistName,
                            style: const TextStyle(
                              fontSize: 7,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
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

  /// レイアウト2：アルバムアートワーク大
  Widget _buildLayout2() {
    return Container(
        width: 105,
        height: 147,
        child: Column(
          children: [
            // アルバムアートワーク
            Container(
              width: 105,
              height: 115,
              decoration: BoxDecoration(
                color: const Color(0xFF9F9F9F),
                borderRadius: BorderRadius.circular(3),
              ),
              child: widget.track.albumImageUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: CachedNetworkImage(
                        imageUrl: widget.track.albumImageUrl,
                        fit: BoxFit.cover,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 7),
            // トラック情報
            Column(
              children: [
                Text(
                  widget.track.trackName,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.388,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                Text(
                  widget.track.artistName,
                  style: const TextStyle(
                    fontSize: 7,
                    color: Colors.white,
                    height: 1.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ],
        ),
      );
  }

  /// レイアウト3：横長トラック情報バー
  Widget _buildLayout3() {
    return Container(
        width: 172,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.52),
          borderRadius: BorderRadius.circular(7),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            // アルバムアートワーク
            Container(
              width: 33,
              height: 35,
              decoration: BoxDecoration(
                color: const Color(0xFF9F9F9F),
                borderRadius: BorderRadius.circular(3),
              ),
              child: widget.track.albumImageUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: CachedNetworkImage(
                        imageUrl: widget.track.albumImageUrl,
                        fit: BoxFit.cover,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 9),
            // トラック情報
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.track.trackName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.track.artistName,
                    style: const TextStyle(
                      fontSize: 7,
                      color: Colors.white,
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

  /// レイアウト4：アルバムアートワークのみ
  Widget _buildLayout4() {
    return Container(
        width: 140,
        height: 152,
        decoration: BoxDecoration(
          color: const Color(0xFF9F9F9F),
          borderRadius: BorderRadius.circular(2),
        ),
        child: widget.track.albumImageUrl.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: CachedNetworkImage(
                  imageUrl: widget.track.albumImageUrl,
                  fit: BoxFit.cover,
                ),
              )
            : null,
      );
  }

  /// レイアウト5：音楽プレイヤーUI
  Widget _buildLayout5() {
    return Container(
        width: 130,
        height: 61,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            // アルバムアートワーク
            Positioned(
              left: 11,
              top: 8,
              child: Container(
                width: 41,
                height: 45,
                decoration: BoxDecoration(
                  color: const Color(0xFF9F9F9F),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: widget.track.albumImageUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: CachedNetworkImage(
                          imageUrl: widget.track.albumImageUrl,
                          fit: BoxFit.cover,
                        ),
                      )
                    : null,
              ),
            ),
            // トラック情報
            Positioned(
              left: 60,
              top: 6,
              right: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.track.trackName,
                    style: const TextStyle(
                      fontSize: 6,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.track.artistName,
                    style: const TextStyle(
                      fontSize: 5,
                      color: Color(0xFF999999),
                      height: 0.957,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 再生コントロール
            Positioned(
              left: 66,
              top: 28,
              child: Row(
                children: [
                  // スキップバック
                  Transform.rotate(
                    angle: 3.14159, // 180度回転
                    child: const Icon(
                      Icons.skip_next,
                      color: Colors.white,
                      size: 10,
                    ),
                  ),
                  const SizedBox(width: 7),
                  // 一時停止ボタン
                  Row(
                    children: [
                      Container(
                        width: 2.948,
                        height: 9.579,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(0.4),
                        ),
                      ),
                      const SizedBox(width: 1),
                      Container(
                        width: 2.948,
                        height: 9.579,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(0.4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 13),
                  // スキップフォワード
                  const Icon(
                    Icons.skip_next,
                    color: Colors.white,
                    size: 10,
                  ),
                ],
              ),
            ),
            // 再生バー
            Positioned(
              left: 61,
              bottom: 14,
              child: Stack(
                children: [
                  // 背景バー
                  Container(
                    width: 63,
                    height: 3,
                    decoration: BoxDecoration(
                      color: const Color(0xFF474747).withOpacity(0.8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  // 進行バー
                  Container(
                    width: 42.195,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(3),
                        bottomLeft: Radius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  /// レイアウト選択オプション
  Widget _buildLayoutOptions() {
    return Column(
      children: [
        // レイアウトオプション
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final isSelected = _selectedLayoutIndex == index;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedLayoutIndex = index;
                    _cardScale = 1.0; // レイアウト変更時はスケールをリセット
                  });
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
              ),
            );
          }),
        ),

        const SizedBox(height: 20),

        // 確認ボタン
        GestureDetector(
          onTap: () {
            // カード中央座標 → プレビュー画面用の左上座標に変換
            // プレビュー画面は Transform.scale(alignment: topLeft) を使用
            final cardSize = _getCardSize();
            final adjustedOffset = Offset(
              _cardCenter.dx - cardSize.width * _cardScale / 2,
              _cardCenter.dy - cardSize.height * _cardScale / 2,
            );
            Navigator.pop(context, {
              'image': widget.selectedImage,
              'layoutIndex': _selectedLayoutIndex,
              'cardPosition': adjustedOffset,
              'cardScale': _cardScale,
              'cardRotation': _cardRotation,
              'lyricsData': _lyricsData,
            });
          },
          child: Container(
            width: 45,
            height: 45,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              color: Colors.black,
              size: 27,
            ),
          ),
        ),
      ],
    );
  }
}

/// 補助線ペインター
/// - 0°(360°), 90°, 180°, 270° の白い線は常に表示
/// - 45°, 135°, 225°, 315° のオレンジ線はスナップ時のみ表示
class _GuideLinePainter extends CustomPainter {
  final Set<double> activeSnapAngles;

  _GuideLinePainter({required this.activeSnapAngles});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final length = sqrt(size.width * size.width + size.height * size.height);

    final basePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1.0;

    // 常に表示: 0°, 90°, 180°, 270°（0°と180°, 90°と270°は同じ線）
    for (final deg in [0.0, 90.0]) {
      final rad = deg * pi / 180;
      final dx = cos(rad) * length;
      final dy = sin(rad) * length;
      canvas.drawLine(
        Offset(centerX - dx, centerY - dy),
        Offset(centerX + dx, centerY + dy),
        basePaint,
      );
    }

    // スナップ時のみ表示: 斜め線（オレンジ）
    if (activeSnapAngles.isNotEmpty) {
      final snapPaint = Paint()
        ..color = Colors.orange.withValues(alpha: 0.5)
        ..strokeWidth = 1.0;

      final drawnAngles = <double>{};
      for (final deg in activeSnapAngles) {
        final normalized = deg % 180;
        if (drawnAngles.contains(normalized)) continue;
        drawnAngles.add(normalized);

        final rad = deg * pi / 180;
        final dx = cos(rad) * length;
        final dy = sin(rad) * length;
        canvas.drawLine(
          Offset(centerX - dx, centerY - dy),
          Offset(centerX + dx, centerY + dy),
          snapPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GuideLinePainter oldDelegate) =>
      oldDelegate.activeSnapAngles.length != activeSnapAngles.length ||
      !oldDelegate.activeSnapAngles.containsAll(activeSnapAngles);
}
