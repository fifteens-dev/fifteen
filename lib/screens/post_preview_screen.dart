import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/track_model.dart';

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

class _PostPreviewScreenState extends State<PostPreviewScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;

  /// 写真を追加
  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
      );
      if (image != null) {
        setState(() {
          _selectedImage = image;
        });
      }
    } catch (e) {
      // エラー処理
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('画像の選択に失敗しました: $e'),
            backgroundColor: const Color(0xFFE53935),
          ),
        );
      }
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

            // 投稿カードプレビュー
            Expanded(
              child: Center(
                child: _buildPostCard(),
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
          // カード上部（写真アップロード部分）
          _buildPhotoSection(),

          // カード下部（楽曲情報部分）
          _buildInfoSection(),
        ],
      ),
    );
  }

  /// 写真セクション
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
                child: _selectedImage != null
                    ? Image.file(
                        File(_selectedImage!.path),
                        fit: BoxFit.cover,
                      )
                    : _buildAddPhotoButton(),
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

  /// 写真追加ボタン
  Widget _buildAddPhotoButton() {
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
                Container(
                  width: 25,
                  height: 25,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF121212),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '写真を追加',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
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
            const SizedBox(height: 9),
            // Apple Music クレジット
            _buildAppleMusicCredit(),

            const Spacer(),

            // 楽曲情報
            _buildTrackInfo(),

            const SizedBox(height: 5),

            // リアクション欄
            _buildReactions(),

            const SizedBox(height: 9),

            // コメント入力欄
            _buildCommentInput(),

            const SizedBox(height: 12),
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
          _buildReactionButton(
            icon: Icons.chat_bubble_outline,
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
