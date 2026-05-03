import 'package:flutter/material.dart';

import 'tutorial_album_carousel.dart';

/// Figma node `65:4201` (Frame 628) のFlutter実装。
///
/// 構造:
/// - 半透明黒（rgba(0,0,0,0.8)）の全画面ディムレイヤー
/// - 👋 絵文字（中央上部、64px）
/// - タイトル「今の気分に一番近い曲は？」（20px, bold, white）
/// - ハッシュタグ「#ドライブで聴きたい曲」（16px, bold, white）
/// - [TutorialAlbumCarousel]（402×270 の3アルバム無限カルーセル）
/// - OK チェックボタン（33×33 円形 + ✓）
///
/// Figma 上の絶対座標は 402×874 のキャンバスを前提にしている。
/// 端末サイズに合わせて等倍で配置するため、`SafeArea` + `LayoutBuilder` で
/// 縦方向は割合 (top/874) で配置する。
class TutorialFrame628Overlay extends StatelessWidget {
  /// OK ボタン or カード中央タップで「現在のアクティブな曲」を確定したときに呼ばれる
  final ValueChanged<TutorialAlbumItem> onConfirm;

  /// アクティブカードの変更通知（外部で「次は xxx を選ぼう」と表示する用途）
  final ValueChanged<int>? onActiveChanged;

  /// カルーセルに表示するアルバム群（指定しなければデフォルト3曲）
  final List<TutorialAlbumItem>? items;

  /// タイトルとサブタイトルを差し替えたい場合
  final String title;
  final String hashtag;

  const TutorialFrame628Overlay({
    super.key,
    required this.onConfirm,
    this.onActiveChanged,
    this.items,
    this.title = '今の気分に一番近い曲は？',
    this.hashtag = '#ドライブで聴きたい曲',
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 80% black ディム + 背景のタップを吸収
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {}, // 何もしないが、背景に抜けないように吸収
          child: const ColoredBox(color: Color(0xCC000000)),
        ),
        // コンテンツ
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Figma 基準: 874px 中の各要素 top
              const double figmaH = 874;
              final h = constraints.maxHeight;
              final scale = h / figmaH;

              // 各要素の top（縦方向のみ Figma 比率で配置）
              final emojiTop = 99.0 * scale;
              final titleTop = 186.0 * scale;
              final hashtagTop = 218.0 * scale;
              final carouselTop = 302.0 * scale;
              final okButtonTop = 636.0 * scale;

              return Stack(
                children: [
                  // 👋 emoji
                  Positioned(
                    left: 0,
                    right: 0,
                    top: emojiTop,
                    child: const _WavingHand(),
                  ),
                  // タイトル
                  Positioned(
                    left: 0,
                    right: 0,
                    top: titleTop,
                    child: Center(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                  // ハッシュタグ
                  Positioned(
                    left: 0,
                    right: 0,
                    top: hashtagTop,
                    child: Center(
                      child: Text(
                        hashtag,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                  // アルバムカルーセル
                  Positioned(
                    left: 0,
                    right: 0,
                    top: carouselTop,
                    child: _CarouselSection(
                      items: items,
                      onConfirm: onConfirm,
                      onActiveChanged: onActiveChanged,
                    ),
                  ),
                  // OK ボタン
                  Positioned(
                    left: 0,
                    right: 0,
                    top: okButtonTop,
                    child: Center(
                      child: _OkButton(
                        onPressed: () {
                          // カードカルーセルから現在の選択を取得して確定
                          _CarouselSection.currentSelection.value?.let((item) {
                            onConfirm(item);
                          });
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 揺れる👋 emoji
class _WavingHand extends StatefulWidget {
  const _WavingHand();

  @override
  State<_WavingHand> createState() => _WavingHandState();
}

class _WavingHandState extends State<_WavingHand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // 軽いなびき: -0.3rad..0.3rad
        final angle = 0.3 * (t < 0.5 ? (t * 4 - 1) : (3 - t * 4));
        return Transform.rotate(
          angle: angle,
          child: const Text(
            '👋',
            style: TextStyle(fontSize: 64, height: 1.0),
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }
}

/// カルーセル + 現在選択の Notifier を保持するセクション
class _CarouselSection extends StatefulWidget {
  final List<TutorialAlbumItem>? items;
  final ValueChanged<TutorialAlbumItem> onConfirm;
  final ValueChanged<int>? onActiveChanged;

  /// 同一画面で1個だけ存在する前提で OK ボタンと共有する
  static final ValueNotifier<TutorialAlbumItem?> currentSelection =
      ValueNotifier<TutorialAlbumItem?>(null);

  const _CarouselSection({
    this.items,
    required this.onConfirm,
    this.onActiveChanged,
  });

  @override
  State<_CarouselSection> createState() => _CarouselSectionState();
}

class _CarouselSectionState extends State<_CarouselSection> {
  @override
  void initState() {
    super.initState();
    final list = widget.items ?? TutorialAlbumCarousel.defaultItems;
    if (list.isNotEmpty) {
      _CarouselSection.currentSelection.value = list.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.items ?? TutorialAlbumCarousel.defaultItems;
    return TutorialAlbumCarousel(
      items: list,
      onActiveChanged: (i) {
        _CarouselSection.currentSelection.value = list[i];
        widget.onActiveChanged?.call(i);
      },
    );
  }
}

/// 円形 OK ボタン（チェック）
class _OkButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _OkButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 33,
          height: 33,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child: const Center(
            child: Icon(
              Icons.check,
              color: Colors.black,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

/// `let` 拡張（Kotlin 風）
extension _Let<T> on T {
  R let<R>(R Function(T it) block) => block(this);
}
