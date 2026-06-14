import 'package:flutter/material.dart';
import '../../constants/adl_teams.dart';

/// 投稿カード裏面・右上に表示する班ハンドルラベル。
/// ホーム画面の投稿カード（post_card.dart）と同じスタイルで `@◯◯` を表示する。
/// 「班」は付けない。
///
/// [enabled] を false にすると非表示。投稿フローのプレビューで、
/// 当該投稿が「1人1日1投稿」ルールで班員投稿として扱われない場合
/// （= 今日既に投稿済み）に false にする用途。
class TeamHandleLabel extends StatelessWidget {
  final String? teamId;
  final bool enabled;

  const TeamHandleLabel({
    super.key,
    required this.teamId,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || teamId == null || teamId!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      '@${AdlTeamDefinitions.displayNameOf(teamId!)}',
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFFD9D9D9),
      ),
    );
  }
}
