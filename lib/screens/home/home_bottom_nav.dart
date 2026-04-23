import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// ホーム画面のボトムナビゲーション
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: Container(
          width: 301,
          height: 61,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ホームボタン
              _buildNavItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                index: 0,
              ),
              const SizedBox(width: 28),
              // 検索ボタン
              _buildNavItem(
                icon: Icons.search,
                index: 1,
              ),
              const SizedBox(width: 28),
              // 投稿ボタン
              _buildNavItemSvg(
                svgPath: 'assets/icons/post_icon.svg',
                index: 2,
              ),
              const SizedBox(width: 28),
              // アカウントボタン
              _buildNavItem(
                icon: Icons.account_circle_outlined,
                selectedIcon: Icons.account_circle,
                index: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ナビゲーションアイテム
  Widget _buildNavItem({
    required IconData icon,
    IconData? selectedIcon,
    required int index,
  }) {
    final isSelected = selectedIndex == index;
    return GestureDetector(
      onTap: () => onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: Icon(
            isSelected ? (selectedIcon ?? icon) : icon,
            color: isSelected ? Colors.white : const Color(0xFF929292),
            size: 28,
          ),
        ),
      ),
    );
  }

  /// SVG版ナビゲーションアイテム
  Widget _buildNavItemSvg({
    required String svgPath,
    required int index,
  }) {
    final isSelected = selectedIndex == index;
    return GestureDetector(
      onTap: () => onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SvgPicture.asset(
            svgPath,
            width: 28,
            height: 28,
            colorFilter: ColorFilter.mode(
              isSelected ? Colors.white : const Color(0xFF929292),
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }
}
