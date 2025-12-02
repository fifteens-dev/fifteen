import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import '../models/track_model.dart';
import 'post_photo_selection_screen.dart';

/// 投稿プレビュー画面
class PostPreviewScreen extends StatefulWidget {
  final TrackModel track;

  const PostPreviewScreen({
    super.key,
    required this.track,
  });

  @override
  State<PostPreviewScreen> createState() => _PostPreviewScreenState();
}

class _PostPreviewScreenState extends State<PostPreviewScreen> with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;

  // 歌詞カード関連
  int _selectedLayoutIndex = 0; // 選択されたレイアウト (0-4)
  Offset _cardPosition = Offset.zero; // 歌詞カードの位置

  // 反転アニメーション用
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _showFront = true; // 初期状態は表面

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  /// カードを反転
  void _flipCard() {
    if (_showFront) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
    setState(() {
      _showFront = !_showFront;
    });
  }

  /// 写真を追加
  Future<void> _pickImage() async {
    // 写真選択画面へ遷移
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => PostPhotoSelectionScreen(track: widget.track),
      ),
    );

    // 選択された写真と歌詞カード情報を設定
    if (result != null) {
      setState(() {
        _selectedImage = result['image'] as XFile?;
        _selectedLayoutIndex = result['layoutIndex'] as int? ?? 0;
        _cardPosition = result['cardPosition'] as Offset? ?? Offset.zero;
      });
    }
  }

  /// 投稿を完了
  void _onPost() {
    // TODO: 投稿処理を実装
    Navigator.pop(context);
    Navigator.pop(context);
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

            // 投稿カードプレビュー（スクロール可能）
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _flipAnimation,
                      builder: (context, child) {
                        final angle = _flipAnimation.value * pi;
                        final isFront = angle < pi / 2;

                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(angle),
                          child: isFront ? _buildFrontCard() : _buildBackCard(),
                        );
                      },
                    ),
                  ),
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
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 19),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 閉じるボタン
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

          // 次へボタン
          GestureDetector(
            onTap: _onPost,
            child: const Text(
              '次へ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF5D8FFF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 投稿カード（表面）- Figmaデザインに基づく
  Widget _buildFrontCard() {
    return GestureDetector(
      onTap: _flipCard, // カード全体をタップで反転
      child: Container(
        width: 363,
        height: 644,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF030303),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              // アルバムカバー (333x363px, left: 15px, top: 0)
              Positioned(
                left: 15,
                top: 0,
                child: Container(
                  width: 333,
                  height: 363,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: widget.track.albumImageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Image.network(
                            widget.track.albumImageUrl,
                            width: 333,
                            height: 363,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildAlbumPlaceholder();
                            },
                          ),
                        )
                      : _buildAlbumPlaceholder(),
                ),
              ),

              // グラデーションオーバーレイ (top: 350px, height: 294px)
              Positioned(
                left: 0,
                top: 350,
                width: 363,
                height: 294,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00030303),
                        Color(0xFF030303),
                      ],
                      stops: [0.0377, 1.0],
                    ),
                  ),
                ),
              ),

              // コンテンツ (グラデーション内)
              // "Provided courtesy of Apple Music" (top: 362px = 350 + 12)
              const Positioned(
                left: 17,
                top: 362,
                child: Text(
                  'Provided courtesy of Apple Music',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFFB0B0B0),
                    fontFamily: 'Noto Sans',
                  ),
                ),
              ),

              // コメント入力欄 (top: 390px = 350 + 40)
              Positioned(
                left: 12,
                top: 390,
                child: _buildCommentInputFront(),
              ),

              // 波形 (top: 446px = 350 + 96)
              Positioned(
                left: 20,
                top: 446,
                child: _buildWaveformFront(),
              ),

              // リアクション (top: 491px = 350 + 141)
              Positioned(
                left: 11,
                top: 491,
                child: _buildReactionsFront(),
              ),

              // いいねした人のアバター (top: 491px = 350 + 141)
              Positioned(
                left: 296,
                top: 491,
                child: _buildLikedAvatarsFront(),
              ),

              // 曲名とアーティスト (top: 526px = 350 + 176)
              Positioned(
                left: 11,
                top: 526,
                width: 194,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.track.trackName,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.198,
                        fontFamily: 'Noto Sans JP',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.track.artistName,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        height: 2.0,
                        fontFamily: 'Noto Sans',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // ユーザー情報 (top: 588px = 350 + 238)
              Positioned(
                left: 12,
                top: 588,
                child: Row(
                  children: [
                    // アイコン
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF9F9F9F),
                      ),
                      child: const Icon(
                        Icons.person,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 9),
                    // ユーザー名
                    const Text(
                      'taroooooda',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontFamily: 'Noto Sans',
                      ),
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

  /// コメント入力欄 (表面用)
  Widget _buildCommentInputFront() {
    return Container(
      width: 338,
      height: 43,
      decoration: BoxDecoration(
        color: const Color(0xFF313131),
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
              fontFamily: 'Noto Sans',
            ),
          ),
          const Spacer(),
          Icon(
            Icons.send,
            size: 20,
            color: Colors.white.withOpacity(0.7),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  /// 波形 (表面用) - PostCardの実装を再利用
  Widget _buildWaveformFront() {
    // ダミーのpostIdを使用して波形を生成
    final seed = widget.track.trackId.hashCode;
    final random = Random(seed);
    const barWidth = 2.5;
    const barMargin = 1.2 * 2;
    const totalBarWidth = barWidth + barMargin;
    const availableWidth = 327.0;
    final barCount = (availableWidth / totalBarWidth).floor();

    return SizedBox(
      width: 327,
      height: 32,
      child: Row(
        children: List.generate(barCount, (index) {
          final normalizedIndex = index / (barCount - 1).toDouble();
          final angle = -pi / 4 + normalizedIndex * 1.5 * pi;
          final waveValue = sin(angle).abs();
          final baseHeight = 0.3 + waveValue * 0.7;
          final randomVariation = (random.nextDouble() - 0.5) * 6;
          final height = 15.0 + (baseHeight * 17.0) + randomVariation;

          return Container(
            width: barWidth,
            height: height.clamp(10.0, 32.0),
            margin: const EdgeInsets.symmetric(horizontal: 1.2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  /// リアクション (表面用)
  Widget _buildReactionsFront() {
    return Row(
      children: [
        // いいね
        Row(
          children: [
            Icon(
              Icons.favorite_border,
              size: 25,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            const Text(
              '3',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                fontFamily: 'Noto Sans',
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        // コメント
        Row(
          children: [
            SvgPicture.asset(
              'assets/icons/message_circle.svg',
              width: 25,
              height: 25,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              '3',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                fontFamily: 'Noto Sans',
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        // 追加ボタン
        Container(
          width: 23,
          height: 23,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
          child: const Icon(
            Icons.add,
            color: Colors.white,
            size: 14,
          ),
        ),
      ],
    );
  }

  /// いいねした人のアバター (表面用)
  Widget _buildLikedAvatarsFront() {
    return Row(
      children: List.generate(3, (index) {
        return Container(
          width: 25,
          height: 25,
          margin: EdgeInsets.only(left: index > 0 ? 4 : 0),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF9F9F9F),
          ),
          child: const Icon(
            Icons.person,
            size: 14,
            color: Colors.white,
          ),
        );
      }),
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

  /// 投稿カード（裏面） - Figmaデザインに基づく
  Widget _buildBackCard() {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(pi), // 裏面なので反転
      child: GestureDetector(
        onTap: _flipCard, // タップで表面に戻る
        child: Container(
          width: 363,
          height: 644,
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Stack(
            children: [
              // 上部エリア（写真選択部分）- 484px高さ
              Positioned(
                left: 0,
                top: 0,
                width: 363,
                height: 484,
                child: _buildPhotoSectionBack(),
              ),

              // 下部エリア（楽曲情報）- 174px高さ
              Positioned(
                left: 0,
                top: 470,
                width: 363,
                height: 174,
                child: _buildInfoSectionBack(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 写真セクション（裏面）
  Widget _buildPhotoSectionBack() {
    return Stack(
      children: [
        // 白い枠
        Positioned(
          left: 0,
          top: 0,
          width: 363,
          height: 474,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  // 選択された写真または写真追加ボタン
                  if (_selectedImage != null)
                    Positioned.fill(
                      child: kIsWeb
                          ? Image.network(
                              _selectedImage!.path,
                              fit: BoxFit.cover,
                            )
                          : Image.file(
                              File(_selectedImage!.path),
                              fit: BoxFit.cover,
                            ),
                    )
                  else
                    _buildAddPhotoButtonBack(),

                  // 選択した写真がある場合は暗いオーバーレイを表示
                  if (_selectedImage != null)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),

                  // 歌詞カードプレビュー（写真選択後）
                  if (_selectedImage != null) _buildLyricsCardBack(),
                ],
              ),
            ),
          ),
        ),

        // ユーザー情報（左上）
        Positioned(
          left: 15,
          top: 15,
          child: _buildUserInfoBack(),
        ),
      ],
    );
  }

  /// 写真追加ボタン（裏面）
  Widget _buildAddPhotoButtonBack() {
    return Container(
      color: const Color(0xFF121212),
      child: Center(
        child: GestureDetector(
          onTap: _pickImage,
          child: Container(
            width: 120,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // +アイコン
                Container(
                  width: 25,
                  height: 25,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                // テキスト
                const Text(
                  '写真を追加',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    fontFamily: 'Noto Sans',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ユーザー情報（裏面）
  Widget _buildUserInfoBack() {
    return Row(
      children: [
        // アバター
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF9F9F9F),
          ),
          child: const Icon(
            Icons.person,
            size: 18,
            color: Colors.white,
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
                fontFamily: 'Noto Sans',
                letterSpacing: -0.12,
              ),
            ),
            SizedBox(height: 2),
            Text(
              '#盛り上がる一曲は？',
              style: TextStyle(
                fontSize: 8,
                color: Colors.white,
                fontFamily: 'Noto Sans',
                letterSpacing: -0.08,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 情報セクション（裏面）
  Widget _buildInfoSectionBack() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00030303),
            Color(0xFF030303),
          ],
          stops: [0.0377, 1.0],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
      ),
      child: Stack(
        children: [
          // "Provided courtesy of Apple Music" (top: 9)
          const Positioned(
            left: 15,
            top: 9,
            child: Text(
              'Provided courtesy of Apple Music',
              style: TextStyle(
                fontSize: 10,
                color: Color(0xFFB0B0B0),
                fontFamily: 'Noto Sans',
              ),
            ),
          ),

          // コメント入力欄 (top: 28, 338x43px)
          Positioned(
            left: 12,
            top: 28,
            child: _buildCommentInputBack(),
          ),

          // リアクション (top: 80)
          Positioned(
            left: 12,
            top: 80,
            child: _buildReactionsBack(),
          ),

          // いいねした人のアバター (left: 296, top: 80)
          Positioned(
            left: 296,
            top: 80,
            child: _buildLikedAvatarsBack(),
          ),

          // 楽曲名とアーティスト (top: 110, width: 194)
          Positioned(
            left: 12,
            top: 110,
            width: 194,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.track.trackName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.198,
                    fontFamily: 'Noto Sans JP',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  widget.track.artistName,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    height: 1.5,
                    fontFamily: 'Noto Sans',
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

  /// コメント入力欄（裏面）
  Widget _buildCommentInputBack() {
    return Container(
      width: 338,
      height: 43,
      decoration: BoxDecoration(
        color: const Color(0xFF313131),
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
              fontFamily: 'Noto Sans',
            ),
          ),
          const Spacer(),
          Icon(
            Icons.send,
            size: 20,
            color: Colors.white.withOpacity(0.7),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  /// リアクション（裏面）
  Widget _buildReactionsBack() {
    return Row(
      children: [
        // いいね
        Row(
          children: [
            const Icon(
              Icons.favorite_border,
              size: 25,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            const Text(
              '3',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                fontFamily: 'Noto Sans',
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        // コメント
        Row(
          children: [
            SvgPicture.asset(
              'assets/icons/message_circle.svg',
              width: 25,
              height: 25,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              '3',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                fontFamily: 'Noto Sans',
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        // 追加ボタン
        Container(
          width: 23,
          height: 23,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
          child: const Icon(
            Icons.add,
            color: Colors.white,
            size: 14,
          ),
        ),
      ],
    );
  }

  /// いいねした人のアバター（裏面）
  Widget _buildLikedAvatarsBack() {
    return Row(
      children: List.generate(3, (index) {
        return Container(
          width: 25,
          height: 25,
          margin: EdgeInsets.only(left: index == 0 ? 0 : 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF9F9F9F),
            border: Border.all(
              color: const Color(0xFF030303),
              width: 1,
            ),
          ),
          child: const Icon(
            Icons.person,
            size: 14,
            color: Colors.white,
          ),
        );
      }),
    );
  }

  /// 歌詞カードプレビュー（裏面）
  Widget _buildLyricsCardBack() {
    Widget lyricsCard;

    // レイアウトに応じて異なるプレビューを表示
    switch (_selectedLayoutIndex) {
      case 0:
        lyricsCard = _buildLayout1Back();
        break;
      case 1:
        lyricsCard = _buildLayout2Back();
        break;
      case 2:
        lyricsCard = _buildLayout3Back();
        break;
      case 3:
        lyricsCard = _buildLayout4Back();
        break;
      case 4:
        lyricsCard = _buildLayout5Back();
        break;
      default:
        lyricsCard = _buildLayout1Back();
    }

    return Positioned(
      left: _cardPosition.dx,
      top: _cardPosition.dy,
      child: lyricsCard,
    );
  }

  /// レイアウト1：標準（歌詞 + トラック情報）
  Widget _buildLayout1Back() {
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
  Widget _buildLayout2Back() {
    return SizedBox(
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
  Widget _buildLayout3Back() {
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
  Widget _buildLayout4Back() {
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
  Widget _buildLayout5Back() {
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
}
