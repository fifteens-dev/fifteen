import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/track_model.dart';
import 'package:image_picker/image_picker.dart';
import 'post_final_preview_screen.dart';

/// 歌詞カード選択画面
class LyricsCardSelectionScreen extends StatefulWidget {
  final TrackModel track;
  final XFile? selectedImage;

  const LyricsCardSelectionScreen({
    super.key,
    required this.track,
    this.selectedImage,
  });

  @override
  State<LyricsCardSelectionScreen> createState() =>
      _LyricsCardSelectionScreenState();
}

class _LyricsCardSelectionScreenState
    extends State<LyricsCardSelectionScreen> {
  int _selectedLayoutIndex = 0; // 選択されたレイアウト (0-4)
  Offset _cardPosition = Offset.zero; // 歌詞カードの位置

  /// 投稿ボタン押下
  void _onPost() {
    // TODO: 投稿処理を実装
    // 選択した写真を持って投稿プレビュー画面に戻る（2つ戻る）
    Navigator.pop(context); // 歌詞カード選択画面を閉じる
    Navigator.pop(context, widget.selectedImage); // 写真選択画面を閉じて、プレビュー画面に画像を返す
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

            // メインコンテンツ
            Expanded(
              child: Stack(
                children: [
                  // 背景の投稿カードプレビュー
                  _buildBackgroundPreview(),
                ],
              ),
            ),

            // 下部のレイアウト選択ツールバー
            _buildLayoutSelector(),

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

          // 投稿ボタン
          GestureDetector(
            onTap: _onPost,
            child: const Text(
              '投稿する',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7F7F7F), // グレー表示
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 背景の投稿カードプレビュー
  Widget _buildBackgroundPreview() {
    return Center(
      child: Container(
        width: 363,
        height: 644,
        margin: const EdgeInsets.symmetric(vertical: 40),
        child: Container(
          height: 484,
          decoration: const BoxDecoration(
            color: Color(0xFF121212),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
            ),
          ),
          child: Stack(
            children: [
              // 白い枠
              Positioned(
                left: 7,
                top: 9,
                right: 7,
                bottom: 17,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
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

                        // 暗いオーバーレイ
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),

                        // 歌詞カードプレビュー
                        _buildLyricsCard(),
                      ],
                    ),
                  ),
                ),
              ),

              // ユーザー情報
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

  /// 歌詞カードプレビュー
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

    // 歌詞カードをドラッグ可能にする
    return Positioned(
      left: _cardPosition.dx,
      top: _cardPosition.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _cardPosition += details.delta;
          });
        },
        child: lyricsCard,
      ),
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
                child: const Center(
                  child: Text(
                    '今宵涙こらえて奏でる愛のSerenade\n今も忘れない恋の歌',
                    style: TextStyle(
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

  /// レイアウト選択ツールバー
  Widget _buildLayoutSelector() {
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
            // 投稿カード最終プレビュー画面へ遷移
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PostFinalPreviewScreen(
                  track: widget.track,
                  selectedImage: widget.selectedImage,
                  selectedLayoutIndex: _selectedLayoutIndex,
                  cardPosition: _cardPosition,
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
