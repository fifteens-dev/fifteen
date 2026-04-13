import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:image_picker/image_picker.dart';
import '../widgets/common/app_toast.dart';

/// 写真選択画面
///
/// プロフィール写真を選択・編集する画面
/// ギャラリーから写真を選択し、円形にクロップしてプレビュー表示
class PhotoPickerScreen extends StatefulWidget {
  const PhotoPickerScreen({super.key});

  @override
  State<PhotoPickerScreen> createState() => _PhotoPickerScreenState();
}

class _PhotoPickerScreenState extends State<PhotoPickerScreen> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _imageBytes;

  void _handleCancel() {
    Navigator.pop(context);
  }

  /// ギャラリーから画像を選択
  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _imageBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '画像の選択に失敗しました: $e');
      }
    }
  }

  void _handleSave() {
    if (_imageBytes != null) {
      // 選択した画像のバイトデータを返す
      Navigator.pop(context, _imageBytes);
    } else {
      AppToast.show(context, '写真を選択してください');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ヘッダー
              _buildHeader(),

              // メインプレビューエリア
              _buildPreviewArea(),

              // 写真グリッド
              Container(
                height: 300,
                child: _buildPhotoGrid(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ヘッダー（キャンセル、ライブラリ、保存）
  Widget _buildHeader() {
    return Container(
      height: 65,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF050505),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(25),
          topRight: Radius.circular(25),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // キャンセルボタン
          GestureDetector(
            onTap: _handleCancel,
            child: const Text(
              'キャンセル',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),

          // ライブラリタイトル
          const Text(
            'ライブラリ',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),

          // 保存ボタン
          GestureDetector(
            onTap: _handleSave,
            child: const Text(
              '保存',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// メインプレビューエリア（選択した写真の円形プレビュー）
  Widget _buildPreviewArea() {
    return Container(
      width: 393,
      height: 393,
      color: Colors.white,
      child: Stack(
        children: [
          // 背景画像（選択されている場合）
          if (_imageBytes != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.4,
                child: Image.memory(
                  _imageBytes!,
                  fit: BoxFit.cover,
                ),
              ),
            ),

          // 円形クロップオーバーレイ
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.5),
                  width: 2,
                ),
              ),
            ),
          ),

          // 円形にクロップされた画像プレビュー
          if (_imageBytes != null)
            Center(
              child: ClipOval(
                child: Container(
                  width: 393,
                  height: 393,
                  child: Image.memory(
                    _imageBytes!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),

          // 画像未選択時のプレースホルダー
          if (_imageBytes == null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '写真を選択してください',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 写真グリッド（ギャラリーボタンのみ）
  Widget _buildPhotoGrid() {
    return Container(
      color: const Color(0xFF050505),
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _pickImageFromGallery,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFF2B2B2B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white24,
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.photo_library,
                      size: 80,
                      color: Colors.white54,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'ギャラリーから選択',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '写真をタップして選択してください',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

}
