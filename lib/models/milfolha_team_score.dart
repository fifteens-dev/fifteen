/// Milfolha ランキングの1チーム分の集計結果。
class MilfolhaTeamScore {
  final String teamId;
  final String displayName;

  /// メンバー登録 +1pt の合計。
  final int regPt;

  /// メンバー投稿 +3pt（1日1投稿まで）の合計。
  final int memberPostPt;

  /// 招待した外部ユーザー登録 +3pt の合計。
  final int extRegPt;

  /// 招待した外部ユーザーの投稿 +5pt（1日1投稿まで）の合計。
  final int extPostPt;

  /// チームの参加メンバー数（表示用）。
  final int memberCount;

  const MilfolhaTeamScore({
    required this.teamId,
    required this.displayName,
    this.regPt = 0,
    this.memberPostPt = 0,
    this.extRegPt = 0,
    this.extPostPt = 0,
    this.memberCount = 0,
  });

  int get total => regPt + memberPostPt + extRegPt + extPostPt;
}
