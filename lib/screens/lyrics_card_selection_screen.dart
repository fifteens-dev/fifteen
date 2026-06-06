import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/track_model.dart';
import '../providers/current_user_provider.dart';
import '../services/lyrics_service.dart';
import '../widgets/shared/user_info_badge.dart';
import 'package:image_picker/image_picker.dart';
import 'post_final_preview_screen.dart';

/// 歌詞カード選択画面
class LyricsCardSelectionScreen extends StatefulWidget {
  final TrackModel track;
  final LyricsData? lyricsData;
  final XFile? selectedImage;
  final Offset imageOffset;
  final double imageScale;
  final Size? imageNaturalSize;
  final bool isVibe;
  final String? vibeTopicId;
  final String? vibeTopicTitle;
  final int audioStartMs;
  final int audioDurationSec;

  const LyricsCardSelectionScreen({
    super.key,
    required this.track,
    this.lyricsData,
    this.selectedImage,
    this.imageOffset = Offset.zero,
    this.imageScale = 1.0,
    this.imageNaturalSize,
    this.isVibe = false,
    this.vibeTopicId,
    this.vibeTopicTitle,
    this.audioStartMs = 0,
    this.audioDurationSec = 15,
  });

  @override
  State<LyricsCardSelectionScreen> createState() =>
      _LyricsCardSelectionScreenState();
}

class _LyricsCardSelectionScreenState
    extends State<LyricsCardSelectionScreen> {
  String get _currentUsername => context.read<CurrentUserProvider>().username;
  String? get _currentUserIconUrl =>
      context.read<CurrentUserProvider>().iconUrl;

  int _selectedLayoutIndex = 1; // 選択されたレイアウト (1-4、0=歌詞カードは非表示)
  Offset _cardCenter = const Offset(180, 200); // カード中央座標（固定）
  double _cardScale = 1.0; // 拡大率（固定）
  double _cardRotation = 0.0; // 回転角度（固定）
  double _albumArtOpacity = 1.0; // アルバムアートの透明度
  // タップ検出用
  Offset? _tapStartFocalPoint;

  LyricsData? _lyricsData; // 取得した歌詞データ
  bool _isLoadingLyrics = false; // 歌詞取得中フラグ

  @override
  void initState() {
    super.initState();
    _lyricsData = widget.lyricsData;

    // 歌詞がまだ取得されていない場合はバックグラウンドで取得
    if (_lyricsData == null) {
      print('⚠️ 歌詞が未取得のため、歌詞カード画面で取得を開始します');
      _fetchLyrics();
    } else {
      print('✅ 既に取得済みの歌詞を使用します (${_lyricsData!.source})');
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

  /// 歌詞カードに表示する歌詞テキストを取得（プレビュー画面と同じロジック）
  String get _displayLyrics {
    if (_isLoadingLyrics) {
      return '歌詞を取得中...';
    }

    if (_lyricsData != null) {
      return _lyricsData!.plainLyrics;
    }

    return '歌詞が見つかりませんでした';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ヘッダー
            _buildHeader(),

            // コンテンツ（最終プレビュー画面と同じ padding に合わせる）
            Expanded(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16),

                    // 背景の投稿カードプレビュー（垂直中央ではなく上揃え）
                    _buildBackgroundPreview(),

                    const SizedBox(height: 36),

                    // レイアウト選択ツールバー（Figma仕様: 写真から36px）
                    _buildLayoutOptions(),

                    const SizedBox(height: 30),
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
    return Hero(
      tag: 'post_flow_header',
      flightShuttleBuilder: (_, __, ___, ____, _____) => const Material(
        color: Colors.transparent,
        child: SizedBox(
          height: 50,
          child: Center(
            child: Text(
              '新規投稿',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: 50,
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
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),

              // スペーサー
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
  }

  /// 背景の投稿カードプレビュー
  Widget _buildBackgroundPreview() {
    const photoHeight = 484.0;
    const frameW = 363.0;

    // 画像表示サイズを事前計算
    double? _displayW, _displayH;
    if (widget.imageNaturalSize != null) {
      final natW = widget.imageNaturalSize!.width;
      final natH = widget.imageNaturalSize!.height;
      if (natW > 0 && natH > 0) {
        final baseScale = max(frameW / natW, photoHeight / natH);
        _displayW = natW * baseScale;
        _displayH = natH * baseScale;
      }
    }

    return Container(
      width: frameW,
      height: photoHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // 選択された写真を表示（静的・再構築不要）
              if (widget.selectedImage != null && _displayW != null)
                Positioned(
                  left: widget.imageOffset.dx,
                  top: widget.imageOffset.dy,
                  child: RepaintBoundary(
                    child: Transform.scale(
                      scale: widget.imageScale,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: _displayW,
                        height: _displayH!,
                        child: kIsWeb
                            ? Image.network(
                                widget.selectedImage!.path,
                                fit: BoxFit.fill,
                              )
                            : Image.file(
                                File(widget.selectedImage!.path),
                                fit: BoxFit.fill,
                              ),
                      ),
                    ),
                  ),
                )
              else if (widget.selectedImage != null)
                Positioned.fill(
                  child: kIsWeb
                      ? Image.network(widget.selectedImage!.path, fit: BoxFit.cover)
                      : Image.file(File(widget.selectedImage!.path), fit: BoxFit.cover),
                )
              else
                Container(
                  color: const Color(0xFF121212),
                ),

              // 歌詞カード（固定位置・固定スケール・固定回転）
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(
                    _cardCenter.dx - _photoWidth / 2,
                    _cardCenter.dy - _photoHeight / 2,
                  ),
                  child: Transform.scale(
                    scale: _cardScale,
                    child: Transform.rotate(
                      angle: _cardRotation,
                      child: Center(child: _buildCurrentLayout()),
                    ),
                  ),
                ),
              ),

              // タップ検出オーバーレイ（写真エリア全体をカバー）
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    if (_tapStartFocalPoint != null &&
                        _isTapOnCard(_tapStartFocalPoint!)) {
                      _showOpacityPicker();
                    }
                  },
                  onTapDown: (details) {
                    _tapStartFocalPoint = details.localPosition;
                  },
                  behavior: HitTestBehavior.translucent,
                ),
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
                  showBackground: false,
                  teamId: context.read<CurrentUserProvider>().adlTeamId,
                ),
              ),
            ],
          ),
        ),
    );
  }

  // 写真フレームサイズ
  static const double _photoWidth = 363.0;
  static const double _photoHeight = 484.0;

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

  /// 現在選択中のレイアウトウィジェットを返す
  Widget _buildCurrentLayout() {
    switch (_selectedLayoutIndex) {
      case 0:
        return _buildLayout1();
      case 1:
        return _buildLayout2();
      case 2:
        return _buildLayout3();
      case 3:
        return _buildLayout4();
      case 4:
        return _buildLayout5();
      default:
        return _buildLayout1();
    }
  }

  /// タップ位置がカードの範囲内か判定（回転は考慮しない近似）
  bool _isTapOnCard(Offset tapPoint) {
    final cardSize = _getCardSize();
    final halfW = cardSize.width * _cardScale / 2;
    final halfH = cardSize.height * _cardScale / 2;
    return (tapPoint.dx - _cardCenter.dx).abs() <= halfW &&
        (tapPoint.dy - _cardCenter.dy).abs() <= halfH;
  }

  /// アルバムアート透明度ピッカーを表示
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
                              color: Colors.white.withOpacity(opacity),
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
                    Opacity(
                      opacity: _albumArtOpacity,
                      child: Container(
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
            Opacity(
              opacity: _albumArtOpacity,
              child: Container(
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
            Opacity(
              opacity: _albumArtOpacity,
              child: Container(
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
    return Opacity(
      opacity: _albumArtOpacity,
      child: Container(
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
      ),
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
              child: Opacity(
                opacity: _albumArtOpacity,
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
        // レイアウトオプション（Figma: 左右37px余白、アイコン間gap30px）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 37),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final index = i + 1; // layout 0（歌詞カード）をスキップ
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
        ),

        // Figma: icons bottom から105px底スペース内にチェックマークを中央配置 → (105-45)/2 = 30px
        const SizedBox(height: 30),

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
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PostFinalPreviewScreen(
                  track: widget.track,
                  selectedImage: widget.selectedImage,
                  imageOffset: widget.imageOffset,
                  imageScale: widget.imageScale,
                  imageNaturalSize: widget.imageNaturalSize,
                  selectedLayoutIndex: _selectedLayoutIndex,
                  cardPosition: adjustedOffset,
                  cardScale: _cardScale,
                  cardRotation: _cardRotation,
                  isVibe: widget.isVibe,
                  vibeTopicId: widget.vibeTopicId,
                  vibeTopicTitle: widget.vibeTopicTitle,
                  lyricsData: _lyricsData,
                  audioStartMs: widget.audioStartMs,
                  audioDurationSec: widget.audioDurationSec,
                  albumArtOpacity: _albumArtOpacity,
                ),
              ),
            );
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
