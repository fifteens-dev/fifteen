part of '../home_screen.dart';

/// ホーム画面の透明ピン留めヘッダー用デリゲート（15s タイトル + 通知ベル）。
class _HomeHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final double topPadding;
  final ValueNotifier<double> bellOpacity;
  final Widget bellButton;

  _HomeHeaderDelegate({
    required this.height,
    required this.topPadding,
    required this.bellOpacity,
    required this.bellButton,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.transparent,
      padding: EdgeInsets.only(left: 16, right: 16, top: topPadding),
      child: Stack(
        children: [
          const Center(
            child: Text(
              '15s',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFamily: 'SFPro',
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: bellOpacity,
              builder: (_, opacity, child) => Opacity(
                opacity: opacity,
                child: IgnorePointer(ignoring: opacity < 0.1, child: child),
              ),
              child: bellButton,
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_HomeHeaderDelegate old) =>
      old.height != height || old.topPadding != topPadding;
}
