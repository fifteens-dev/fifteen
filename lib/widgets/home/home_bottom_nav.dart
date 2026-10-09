import 'package:flutter/material.dart';

/// ホーム画面のボトムナビゲーション（3タブ: Music Memory / ホーム / プロフィール）
///
/// Figma 5189:10802「ナビバー」準拠:
///   - バー全体 200×61 / radius 30（両端フル丸）
///   - アイコン枠 40×40 を絶対配置: calender x=16, home x=80, profile x=143（y≈10）
class HomeBottomNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemTapped;

  const HomeBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Figma 5189:11199: ナビバーは画面底辺から 33px。
      padding: const EdgeInsets.only(bottom: 33),
      child: Center(
        child: Container(
          width: 200,
          height: 61,
          decoration: BoxDecoration(
            color: const Color(0xFF191919).withValues(alpha: 0.77),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 1,
                spreadRadius: 0,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 6,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 14,
                spreadRadius: 0,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Music Memory（カレンダー）枠 (16,10) / グリフ 25×23 @(7, 8.75)
              _buildNavItem(
                frameLeft: 16,
                frameTop: 10,
                assetPath: 'assets/icons/nav_music_memory.png',
                glyphLeft: 7,
                glyphTop: 8.75,
                glyphWidth: 25,
                glyphHeight: 23,
                index: 0,
              ),
              // ホーム 枠 (80,9)（中央） / グリフ 30×26.25 @(5, 7)
              _buildNavItem(
                frameLeft: 80,
                frameTop: 9,
                assetPath: 'assets/icons/nav_home.png',
                glyphLeft: 5,
                glyphTop: 7,
                glyphWidth: 30,
                glyphHeight: 26.25,
                index: 1,
              ),
              // プロフィール 枠 (143,10) / グリフ 23.5×23.5 @(7.75, 8.75)
              _buildNavItem(
                frameLeft: 143,
                frameTop: 10,
                assetPath: 'assets/icons/nav_profile.png',
                glyphLeft: 7.75,
                glyphTop: 8.75,
                glyphWidth: 23.5,
                glyphHeight: 23.5,
                index: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ナビゲーションアイテム。40×40 のタップ枠内に、Figma のグリフ実寸・実位置
  /// （素材=40枠を4xで書き出し → 中身÷4）で白グリフPNGを配置し、選択で着色する。
  Widget _buildNavItem({
    required double frameLeft,
    required double frameTop,
    required String assetPath,
    required double glyphLeft,
    required double glyphTop,
    required double glyphWidth,
    required double glyphHeight,
    required int index,
  }) {
    final isSelected = selectedIndex == index;
    return Positioned(
      left: frameLeft,
      top: frameTop,
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: () => onItemTapped(index),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Positioned(
              left: glyphLeft,
              top: glyphTop,
              width: glyphWidth,
              height: glyphHeight,
              child: Image.asset(
                assetPath,
                width: glyphWidth,
                height: glyphHeight,
                fit: BoxFit.fill,
                color: isSelected ? Colors.white : const Color(0xFF929292),
                colorBlendMode: BlendMode.srcIn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
