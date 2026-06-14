import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/common/app_toast.dart';

/// 写真選択画面
///
/// プロフィール写真を選択・編集する画面。
/// ギャラリーから写真を選択し、円形プレビュー内でパン／ピンチで位置とサイズを調整できる。
/// 保存時には円形プレビューの領域を PNG として書き出す（円形クロップ済み）。
class PhotoPickerScreen extends StatefulWidget {
  const PhotoPickerScreen({super.key});

  @override
  State<PhotoPickerScreen> createState() => _PhotoPickerScreenState();
}

class _PhotoPickerScreenState extends State<PhotoPickerScreen> {
  final ImagePicker _picker = ImagePicker();
  final GlobalKey _previewKey = GlobalKey();
  Uint8List? _imageBytes;

  // パン/ピンチ操作用の状態
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  Offset _focalPointStart = Offset.zero;
  Offset _offsetStart = Offset.zero;
  double _scaleStart = 1.0;

  static const double _previewSize = 393.0;
  static const double _minScale = 0.5;
  static const double _maxScale = 4.0;

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
          _offset = Offset.zero;
          _scale = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '画像の選択に失敗しました: $e');
      }
    }
  }

  Future<void> _handleSave() async {
    if (_imageBytes == null) {
      AppToast.show(context, '写真を選択してください');
      return;
    }
    try {
      final cropped = await _captureCroppedBytes();
      if (!mounted) return;
      Navigator.pop(context, cropped ?? _imageBytes);
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context, _imageBytes);
    }
  }

  /// 円形プレビュー領域を PNG バイト列としてキャプチャする
  Future<Uint8List?> _captureCroppedBytes() async {
    final boundary = _previewKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _focalPointStart = details.focalPoint;
    _offsetStart = _offset;
    _scaleStart = _scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _scale = (_scaleStart * details.scale).clamp(_minScale, _maxScale);
      final delta = details.focalPoint - _focalPointStart;
      _offset = _offsetStart + delta;
    });
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
              SizedBox(
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
  /// パン/ピンチで位置とサイズを調整可能。
  Widget _buildPreviewArea() {
    return GestureDetector(
      onScaleStart: _imageBytes == null ? null : _onScaleStart,
      onScaleUpdate: _imageBytes == null ? null : _onScaleUpdate,
      child: Container(
        width: _previewSize,
        height: _previewSize,
        color: const Color(0xFF050505),
        alignment: Alignment.center,
        child: RepaintBoundary(
          key: _previewKey,
          child: SizedBox(
            width: _previewSize,
            height: _previewSize,
            child: ClipOval(
              child: Container(
                color: const Color(0xFF1A1A1A),
                child: _imageBytes != null
                    ? _buildTransformedImage()
                    : _buildPlaceholder(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransformedImage() {
    return Transform.translate(
      offset: _offset,
      child: Transform.scale(
        scale: _scale,
        child: Image.memory(
          _imageBytes!,
          fit: BoxFit.cover,
          width: _previewSize,
          height: _previewSize,
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Column(
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
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.photo_library,
                      size: 80,
                      color: Colors.white54,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'ギャラリーから選択',
                      style: TextStyle(
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
              _imageBytes == null
                  ? '写真をタップして選択してください'
                  : '円の中で写真をドラッグ・ピンチして位置を調整',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
