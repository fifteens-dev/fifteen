import 'package:flutter/material.dart';

/// 投稿用のカメラ撮影 UI（ビュー本体のみ、カメラパッケージは未統合）。
///
/// 将来 `package:camera` を導入したらここの [previewBuilder] にライブプレビューを差し込む。
/// チュートリアル中はモックビューを使用する（[CameraCaptureView.demo] コンストラクタ）。
///
/// レイアウト:
///   - 上部: ハッシュタグタイトル + フラッシュトグル
///   - 中央: ビューファインダー（[previewBuilder] で差し替え可）
///   - 下部: シャッターボタン + ギャラリーサムネ + カメラ切替
class CameraCaptureView extends StatelessWidget {
  /// 上部に表示するハッシュタグ（例: "#ドライブで聴きたい曲"）。null なら非表示。
  final String? hashtag;

  /// シャッターボタンタップ時のコールバック
  final VoidCallback? onShutter;

  /// 戻るボタンタップ時のコールバック
  final VoidCallback? onClose;

  /// ライブプレビューを差し込むビルダー。null ならダーク背景。
  final WidgetBuilder? previewBuilder;

  /// ギャラリーサムネ（最近撮った写真）。null なら表示しない
  final ImageProvider? galleryThumbnail;
  final VoidCallback? onGalleryTap;

  /// シャッターアニメーション中のフラッシュエフェクト用
  final bool flashOnShutter;

  const CameraCaptureView({
    super.key,
    this.hashtag,
    this.onShutter,
    this.onClose,
    this.previewBuilder,
    this.galleryThumbnail,
    this.onGalleryTap,
    this.flashOnShutter = true,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // ビューファインダー
          Positioned.fill(
            child: previewBuilder != null
                ? previewBuilder!(context)
                : Container(color: const Color(0xFF111111)),
          ),
          // 上部ハッシュタグ
          if (hashtag != null)
            Positioned(
              left: 0,
              right: 0,
              top: topPadding + 8,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    hashtag!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          // 上部右: フラッシュ
          Positioned(
            right: 12,
            top: topPadding + 8,
            child: const _CircleIcon(icon: Icons.flash_off),
          ),
          // 上部左: 閉じる
          Positioned(
            left: 12,
            top: topPadding + 8,
            child: GestureDetector(
              onTap: onClose,
              child: const _CircleIcon(icon: Icons.close),
            ),
          ),
          // 下部: シャッター + ギャラリー + カメラ切替
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPadding + 24,
            child: SizedBox(
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // ギャラリー（左）
                  Positioned(
                    left: 32,
                    child: GestureDetector(
                      onTap: onGalleryTap,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2B2B2B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24, width: 1),
                          image: galleryThumbnail != null
                              ? DecorationImage(image: galleryThumbnail!, fit: BoxFit.cover)
                              : null,
                        ),
                        child: galleryThumbnail == null
                            ? const Icon(Icons.photo_library_outlined, color: Colors.white, size: 22)
                            : null,
                      ),
                    ),
                  ),
                  // シャッターボタン
                  GestureDetector(
                    onTap: onShutter,
                    child: const _ShutterButton(),
                  ),
                  // カメラ切替（右）
                  const Positioned(
                    right: 32,
                    child: _CircleIcon(icon: Icons.cameraswitch_outlined),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  const _CircleIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
      ),
      padding: const EdgeInsets.all(6),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// シャッター発火時の白フラッシュエフェクト。
/// 通常は [CameraCaptureView] と組み合わせて使う。
class CameraShutterFlash extends StatefulWidget {
  /// フラッシュ発生のトリガー（インクリメントするごとに発火）
  final int trigger;
  const CameraShutterFlash({super.key, required this.trigger});

  @override
  State<CameraShutterFlash> createState() => _CameraShutterFlashState();
}

class _CameraShutterFlashState extends State<CameraShutterFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void didUpdateWidget(covariant CameraShutterFlash old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // ベル型の不透明度カーブ
          final t = _controller.value;
          final opacity = t < 0.4 ? (t / 0.4) : (1 - (t - 0.4) / 0.6);
          return Opacity(
            opacity: opacity.clamp(0.0, 0.9),
            child: const ColoredBox(color: Colors.white),
          );
        },
      ),
    );
  }
}
