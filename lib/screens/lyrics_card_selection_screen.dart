import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/track_model.dart';
import '../services/lyrics_service.dart';
import 'package:image_picker/image_picker.dart';

/// 歌詞カード選択画面
class LyricsCardSelectionScreen extends StatefulWidget {
  final TrackModel track;
  final LyricsData? lyricsData;
  final XFile? selectedImage;
  final bool isVibe;
  final String? vibeTopicId;

  const LyricsCardSelectionScreen({
    super.key,
    required this.track,
    this.lyricsData,
    this.selectedImage,
    this.isVibe = false,
    this.vibeTopicId,
  });

  @override
  State<LyricsCardSelectionScreen> createState() =>
      _LyricsCardSelectionScreenState();
}

class _LyricsCardSelectionScreenState
    extends State<LyricsCardSelectionScreen> {
  int _selectedLayoutIndex = 0; // 選択されたレイアウト (0-4)
  Rect _rect = const Rect.fromLTWH(0, 0, 196, 126); // 歌詞カードの位置とサイズ
  Flip _flip = Flip.none; // 反転情報
  double _cardRotation = 0.0; // 回転角度（ラジアン）

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

    // デフォルト歌詞
    return '今宵涙こらえて奏でる愛のSerenade\n今も忘れない恋の歌';
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

            const SizedBox(height: 10),

            // 回転ボタン（写真の上）
            _buildRotationButtons(),

            const SizedBox(height: 10),

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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 戻るボタン
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.close,
              color: Colors.white,
              size: 20,
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

          // 次へボタン（プレースホルダー）
          const SizedBox(width: 60), // スペース確保
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
              // 選択された写真を表示
              if (widget.selectedImage != null)
                Positioned.fill(
                  child: kIsWeb
                      ? Image.network(
                          widget.selectedImage!.path,
                          fit: BoxFit.cover,
                        )
                      : Image.file(
                          File(widget.selectedImage!.path),
                          fit: BoxFit.cover,
                        ),
                )
              else
                // 写真が選択されていない場合
                Container(
                  color: const Color(0xFF121212),
                ),

              // 歌詞カードプレビュー
              _buildLyricsCard(),

              // ユーザー情報（左上）
              Positioned(
                left: 15,
                top: 15,
                child: Row(
                  children: [
                    // アバター
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF9F9F9F),
                      ),
                    ),
                    const SizedBox(width: 9),
                    // ユーザー名とハッシュタグ
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'taroooooda',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '#盛り上がる一曲は？',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 歌詞カードプレビュー（移動・拡大縮小可能）
  Widget _buildLyricsCard() {
    Widget lyricsCard;

    // レイアウトに応じて異なるプレビューを表示
    switch (_selectedLayoutIndex) {
      case 0:
        lyricsCard = _buildLayout1(); // 標準レイアウト：歌詞 + トラック情報
        break;
      case 1:
        lyricsCard = _buildLayout2(); // アルバムアートワーク大 + テキスト
        break;
      case 2:
        lyricsCard = _buildLayout3(); // 横長のトラック情報バー
        break;
      case 3:
        lyricsCard = _buildLayout4(); // アルバムアートワークのみ
        break;
      case 4:
        lyricsCard = _buildLayout5(); // 音楽プレイヤーUI
        break;
      default:
        lyricsCard = _buildLayout1();
    }

    // TransformableBoxでドラッグ・拡大縮小可能にする
    return TransformableBox(
      rect: _rect,
      flip: _flip,
      onChanged: (result, event) {
        setState(() {
          _rect = result.rect;
          _flip = result.flip;
        });
      },
      contentBuilder: (context, rect, flip) {
        return Transform.rotate(
          angle: _cardRotation,
          alignment: Alignment.center,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
            ),
            child: lyricsCard,
          ),
        );
      },
    );
  }

  /// カードサイズを取得（レイアウトごとに異なる）
  Size _getCardSize() {
    switch (_selectedLayoutIndex) {
      case 0:
        return const Size(196, 126); // レイアウト1
      case 1:
        return const Size(105, 147); // レイアウト2
      case 2:
        return const Size(172, 42); // レイアウト3
      case 3:
        return const Size(140, 152); // レイアウト4
      case 4:
        return const Size(130, 61); // レイアウト5
      default:
        return const Size(196, 126);
    }
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
                              child: Image.network(
                                widget.track.albumImageUrl,
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
                      child: Image.network(
                        widget.track.albumImageUrl,
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
                      child: Image.network(
                        widget.track.albumImageUrl,
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
                child: Image.network(
                  widget.track.albumImageUrl,
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
                        child: Image.network(
                          widget.track.albumImageUrl,
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

  /// 回転ボタン
  Widget _buildRotationButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 左回転ボタン
        GestureDetector(
          onTap: () {
            setState(() {
              _cardRotation -= 0.261799; // -15度（ラジアン）
            });
          },
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.rotate_left,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
        const SizedBox(width: 20),
        // 右回転ボタン
        GestureDetector(
          onTap: () {
            setState(() {
              _cardRotation += 0.261799; // +15度（ラジアン）
            });
          },
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.rotate_right,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ],
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
                    // レイアウト変更時にrectのサイズを更新
                    final newSize = _getCardSize();
                    _rect = Rect.fromLTWH(
                      _rect.left,
                      _rect.top,
                      newSize.width,
                      newSize.height,
                    );
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
            // 選択した写真、レイアウト、カード位置、スケール、回転、歌詞データをPostPreviewScreenに返す
            // rectから位置とスケールを抽出
            final cardPosition = Offset(_rect.left, _rect.top);
            final baseSize = _getCardSize();
            final cardScale = _rect.width / baseSize.width;

            Navigator.pop(context, {
              'image': widget.selectedImage,
              'layoutIndex': _selectedLayoutIndex,
              'cardPosition': cardPosition,
              'cardScale': cardScale,
              'cardRotation': _cardRotation,
              'lyricsData': _lyricsData, // 取得した歌詞データを渡す
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
