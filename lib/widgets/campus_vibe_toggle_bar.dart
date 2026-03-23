import 'package:flutter/material.dart';

/// 投稿フロー末尾に表示される Campus Vibe 参加トグルバー
/// 大学名が設定されており、かつ Campus Vibe 期間中（金土日）のみ表示される
class CampusVibeToggleBar extends StatelessWidget {
  final String university;
  final bool participating;
  final ValueChanged<bool> onChanged;

  const CampusVibeToggleBar({
    super.key,
    required this.university,
    required this.participating,
    required this.onChanged,
  });

  /// 「○○大学」→「○○」のように末尾の「大学」を除去した短縮名
  String get _shortName => university.replaceAll('大学', '');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Text('🔥', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_shortName Campus Vibeに参加中',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
          Switch(
            value: participating,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF5D8FFF),
          ),
        ],
      ),
    );
  }
}
