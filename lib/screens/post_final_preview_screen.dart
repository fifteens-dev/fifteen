import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/track_model.dart';
import '../services/post_service.dart';
import 'home_screen.dart';

/// 投稿カード最終プレビュー画面
class PostFinalPreviewScreen extends StatefulWidget {
  final TrackModel track;
  final XFile? selectedImage;
  final int selectedLayoutIndex;
  final Offset cardPosition;

  const PostFinalPreviewScreen({
    super.key,
    required this.track,
    this.selectedImage,
    required this.selectedLayoutIndex,
    this.cardPosition = Offset.zero,
  });

  @override
  State<PostFinalPreviewScreen> createState() =>
      _PostFinalPreviewScreenState();
}

class _PostFinalPreviewScreenState extends State<PostFinalPreviewScreen> {
  final PostService _postService = PostService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isPosting = false;

  /// 投稿を完了
  Future<void> _onPost() async {
    if (_isPosting) return;

    setState(() => _isPosting = true);

    try {
      final currentUser = _auth.currentUser;
      final userId = currentUser?.uid ?? 'test_user_temp';
      final username = currentUser?.displayName ?? 'taroooooda';
      final userIconUrl = currentUser?.photoURL;

      print('📝 投稿作成開始...');
      print('  ユーザーID: $userId');
      print('  ユーザー名: $username');
      print('  楽曲: ${widget.track.trackName} - ${widget.track.artistName}');

      // 投稿を作成
      final postId = await _postService.createPost(
        userId: userId,
        username: username,
        userIconUrl: userIconUrl,
        trackData: widget.track.toMap(),
        photoUrl: null, // 写真アップロード機能は後で実装
        selectedLayoutIndex: widget.selectedLayoutIndex,
        cardPositionX: widget.cardPosition.dx,
        cardPositionY: widget.cardPosition.dy,
      );

      print('✅ 投稿を作成しました: $postId');
      print('📤 Firestoreに保存されました');

      // ホーム画面に戻る（全てのスタックをクリア）
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );

        // 投稿成功メッセージを表示
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('投稿しました'),
                backgroundColor: Color(0xFF4CAF50),
                duration: Duration(seconds: 2),
              ),
            );
          }
        });
      }
    } catch (e) {
      print('投稿作成エラー: $e');
      if (mounted) {
        setState(() => _isPosting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('投稿の作成に失敗しました'),
            backgroundColor: Color(0xFFE53935),
          ),
        );
      }
    }
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
                    child: _buildPostCard(),
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

          // 投稿するボタン
          GestureDetector(
            onTap: _isPosting ? null : _onPost,
            child: _isPosting
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF5D8FFF),
                    ),
                  )
                : const Text(
                    '投稿する',
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

  /// 投稿カード
  Widget _buildPostCard() {
    return Container(
      width: 363,
      height: 644,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFA0A0A0),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          // カード上部（写真 + 歌詞カード部分）
          _buildPhotoSection(),

          // カード下部（楽曲情報部分）
          _buildInfoSection(),
        ],
      ),
    );
  }

  /// 写真セクション（歌詞カードオーバーレイ付き）
  Widget _buildPhotoSection() {
    return Container(
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

                    // 選択された歌詞カードレイアウトを表示
                    _buildLyricsCardOverlay(),
                  ],
                ),
              ),
            ),
          ),

          // ユーザー情報
          Positioned(
            left: 15,
            top: 15,
            child: _buildUserInfo(),
          ),
        ],
      ),
    );
  }

  /// 歌詞カードオーバーレイ
  Widget _buildLyricsCardOverlay() {
    Widget lyricsCard;

    switch (widget.selectedLayoutIndex) {
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

    // 歌詞カードを指定位置に配置
    return Positioned(
      left: widget.cardPosition.dx,
      top: widget.cardPosition.dy,
      child: lyricsCard,
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

  /// ユーザー情報
  Widget _buildUserInfo() {
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
    );
  }

  /// 情報セクション
  Widget _buildInfoSection() {
    return Expanded(
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
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 7),
            // Apple Music クレジット
            _buildAppleMusicCredit(),

            const Spacer(),

            // 楽曲情報
            _buildTrackInfo(),

            const SizedBox(height: 4),

            // リアクション欄
            _buildReactions(),

            const SizedBox(height: 7),

            // コメント入力欄
            _buildCommentInput(),

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  /// Apple Music クレジット
  Widget _buildAppleMusicCredit() {
    return const Padding(
      padding: EdgeInsets.only(left: 15),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Provided courtesy of Apple Music',
          style: TextStyle(
            fontSize: 10,
            color: Color(0xFFB0B0B0),
          ),
        ),
      ),
    );
  }

  /// 楽曲情報
  Widget _buildTrackInfo() {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Align(
        alignment: Alignment.centerLeft,
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
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.track.artistName,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// リアクション欄
  Widget _buildReactions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // いいねボタン
          _buildReactionButton(
            icon: Icons.favorite_border,
            count: '3',
          ),
          const SizedBox(width: 12),

          // コメントボタン
          _buildCommentButton(
            count: '3',
          ),
          const SizedBox(width: 12),

          // 追加ボタン
          Container(
            width: 23,
            height: 23,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.add,
              color: Colors.white,
              size: 14,
            ),
          ),

          const Spacer(),

          // いいねした人のアバター
          _buildLikeAvatars(),
        ],
      ),
    );
  }

  /// リアクションボタン
  Widget _buildReactionButton({
    required IconData icon,
    required String count,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: Colors.white,
          size: 25,
        ),
        const SizedBox(width: 6),
        Text(
          count,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  /// コメントボタン
  Widget _buildCommentButton({
    required String count,
  }) {
    return Row(
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
        Text(
          count,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  /// いいねした人のアバター
  Widget _buildLikeAvatars() {
    return Row(
      children: [
        _buildAvatar(0),
        Transform.translate(
          offset: const Offset(-5, 0),
          child: _buildAvatar(1),
        ),
        Transform.translate(
          offset: const Offset(-10, 0),
          child: _buildAvatar(2),
        ),
      ],
    );
  }

  /// アバター
  Widget _buildAvatar(int index) {
    return Container(
      width: 25,
      height: 25,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF9F9F9F),
        border: Border.all(
          color: const Color(0xFF030303),
          width: 1,
        ),
      ),
    );
  }

  /// コメント入力欄
  Widget _buildCommentInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        height: 43,
        decoration: BoxDecoration(
          color: const Color(0xFF313131),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'コメントする',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
            // 送信ボタン
            Padding(
              padding: EdgeInsets.only(right: 10),
              child: Icon(
                Icons.send,
                color: Colors.white,
                size: 23,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
