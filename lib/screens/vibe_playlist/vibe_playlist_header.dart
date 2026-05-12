import 'package:flutter/material.dart';

/// Vibeプレイリストの上部ヘッダー（戻るボタン・タイトル・サブタイトル）。
/// Figma: header h=35
///   タイトル top=6 fontSize=13 bold center
///   サブタイトル top=23 fontSize=10 color=#B7BCC0 center
///   戻るボタン left=11 top=0 size=33
class VibePlaylistHeader extends StatelessWidget {
  final String topicTitle;
  final int totalUsers;
  final int trackCount;
  final VoidCallback onBack;

  const VibePlaylistHeader({
    super.key,
    required this.topicTitle,
    required this.totalUsers,
    required this.trackCount,
    required this.onBack,
  });

  String _fmt(int n) {
    if (n >= 10000) {
      return '${(n / 10000).toStringAsFixed(n % 10000 != 0 ? 1 : 0)}万';
    }
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 != 0 ? 1 : 0)}K';
    }
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 35,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 6,
            child: Text(
              '#$topicTitle',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.0,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 23,
            child: Text(
              '🔥${_fmt(totalUsers)}人が追加・$trackCount曲',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFFB7BCC0),
                height: 1.0,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Positioned(
            left: 11,
            top: 0,
            width: 33,
            height: 33,
            child: GestureDetector(
              onTap: onBack,
              behavior: HitTestBehavior.opaque,
              child: const Icon(
                Icons.chevron_left,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 投稿 / 曲リストのタブバー。
/// インジケーターのスライド位置を `tabPageController` のページ進捗に追従させる。
class VibePlaylistTabBar extends StatelessWidget {
  final TabController tabController;
  final PageController tabPageController;

  const VibePlaylistTabBar({
    super.key,
    required this.tabController,
    required this.tabPageController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 31,
          child: Stack(
            children: [
              Row(
                children: [
                  _buildTabButton(label: '投稿', index: 0),
                  _buildTabButton(label: '曲リスト', index: 1),
                ],
              ),
              // スライドインジケーター
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: tabPageController,
                  builder: (context, _) {
                    final screenWidth = MediaQuery.of(context).size.width;
                    final tabWidth = screenWidth / 2;
                    const indicatorWidth = 64.0;
                    final t = tabPageController.hasClients
                        ? (tabPageController.page ??
                                tabController.index.toDouble())
                            .clamp(0.0, 1.0)
                        : tabController.index.toDouble();
                    final left =
                        tabWidth * (0.625 + 0.75 * t) - indicatorWidth / 2;
                    return SizedBox(
                      height: 2,
                      child: Stack(
                        children: [
                          Positioned(
                            left: left,
                            width: indicatorWidth,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabButton({required String label, required int index}) {
    final align =
        index == 0 ? const Alignment(0.25, 0) : const Alignment(-0.25, 0);
    return Expanded(
      child: GestureDetector(
        onTap: () => tabController.animateTo(index),
        behavior: HitTestBehavior.opaque,
        child: Align(
          alignment: align,
          child: AnimatedBuilder(
            animation: tabPageController,
            builder: (context, _) {
              final t = tabPageController.hasClients
                  ? (tabPageController.page ??
                          tabController.index.toDouble())
                      .clamp(0.0, 1.0)
                  : tabController.index.toDouble();
              final opacity = index == 0 ? (1.0 - t) : t;
              return Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.4 + 0.6 * opacity),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
