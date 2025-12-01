import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/track_model.dart';
import 'lyrics_card_selection_screen.dart';

/// 投稿用写真選択画面
class PostPhotoSelectionScreen extends StatefulWidget {
  final TrackModel track;

  const PostPhotoSelectionScreen({
    super.key,
    required this.track,
  });

  @override
  State<PostPhotoSelectionScreen> createState() =>
      _PostPhotoSelectionScreenState();
}

class _PostPhotoSelectionScreenState extends State<PostPhotoSelectionScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  final List<XFile> _galleryImages = [];

  @override
  void initState() {
    super.initState();
    _loadGalleryImages();
  }

  /// ギャラリーから画像リストを読み込む（Web対応のためダミー実装）
  Future<void> _loadGalleryImages() async {
    // TODO: 実際のギャラリーから画像を読み込む実装
    // Webではimage_pickerのpickMultiImageを使用
    // モバイルではphoto_managerパッケージなどを使用
  }

  /// カメラで写真を撮影
  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
      );
      if (photo != null) {
        setState(() {
          _selectedImage = photo;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('カメラの起動に失敗しました: $e'),
            backgroundColor: const Color(0xFFE53935),
          ),
        );
      }
    }
  }

  /// ギャラリーから写真を選択
  Future<void> _pickFromGallery() async {
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

  /// 次へボタン押下
  void _onNext() {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('写真を選択してください'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
      return;
    }

    // 歌詞カード選択画面へ遷移
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LyricsCardSelectionScreen(
          track: widget.track,
          selectedImage: _selectedImage,
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
            // ヘッダー
            _buildHeader(),

            // メインコンテンツ（スクロール可能）
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    // 選択された写真のプレビュー
                    _buildPreviewImage(),

                    const SizedBox(height: 7),

                    // 写真グリッド
                    _buildPhotoGrid(),
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
            onTap: _onNext,
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

  /// プレビュー画像
  Widget _buildPreviewImage() {
    return Container(
      width: 363,
      height: 485,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.white,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: _selectedImage != null
            ? kIsWeb
                ? Image.network(
                    _selectedImage!.path,
                    fit: BoxFit.cover,
                  )
                : Image.file(
                    File(_selectedImage!.path),
                    fit: BoxFit.cover,
                  )
            : Container(
                color: const Color(0xFF2B2B2B),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate,
                        size: 80,
                        color: Colors.white38,
                      ),
                      SizedBox(height: 16),
                      Text(
                        '写真を選択してください',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  /// 写真グリッド
  Widget _buildPhotoGrid() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 1,
          crossAxisSpacing: 1,
        ),
        itemCount: 12, // カメラボタン + 11個の写真
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildCameraButton();
          }
          return _buildPhotoGridItem(index);
        },
      ),
    );
  }

  /// カメラボタン
  Widget _buildCameraButton() {
    return GestureDetector(
      onTap: _takePhoto,
      child: Container(
        width: 97,
        height: 97,
        color: const Color(0xFF2B2B2B),
        child: const Icon(
          Icons.camera_alt,
          size: 48,
          color: Colors.white54,
        ),
      ),
    );
  }

  /// 写真グリッドアイテム
  Widget _buildPhotoGridItem(int index) {
    // ダミー画像として2番目のアイテムを選択状態にする
    final bool isSelected = index == 1 && _selectedImage != null;

    return GestureDetector(
      onTap: () {
        // ギャラリーから選択
        _pickFromGallery();
      },
      child: Container(
        width: 97,
        height: 97,
        color: const Color(0xFF2B2B2B),
        child: Stack(
          children: [
            // ダミー画像（実際はギャラリーから取得した画像を表示）
            Container(
              color: Colors.grey[800],
              child: const Center(
                child: Icon(
                  Icons.image,
                  size: 40,
                  color: Colors.white24,
                ),
              ),
            ),

            // 選択状態のオーバーレイ
            if (isSelected)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white,
                    width: 1,
                  ),
                ),
                child: Stack(
                  children: [
                    // 半透明の白いオーバーレイ
                    Container(
                      color: Colors.white.withOpacity(0.5),
                    ),

                    // チェックマークアイコン
                    Center(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: Color(0xFF5D8FFF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 20,
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
  }
}
