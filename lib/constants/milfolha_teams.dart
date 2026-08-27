/// Milfolha 対抗バトルイベントのチーム定義。
///
/// コード = チームID = `waterfalls_A` 〜 `waterfalls_H`（表示名 A〜H）。
/// チーム数/名はこの [all] 配列1箇所で増減できる（確定後に調整）。
class MilfolhaTeamDefinitions {
  MilfolhaTeamDefinitions._();

  /// 8チーム（A〜H）。順序はランキング表示や管理パネルの並び順に使う。
  static const List<MilfolhaTeamDef> all = [
    MilfolhaTeamDef(id: 'waterfalls_a', displayName: 'A'),
    MilfolhaTeamDef(id: 'waterfalls_b', displayName: 'B'),
    MilfolhaTeamDef(id: 'waterfalls_c', displayName: 'C'),
    MilfolhaTeamDef(id: 'waterfalls_d', displayName: 'D'),
    MilfolhaTeamDef(id: 'waterfalls_e', displayName: 'E'),
    MilfolhaTeamDef(id: 'waterfalls_f', displayName: 'F'),
    MilfolhaTeamDef(id: 'waterfalls_g', displayName: 'G'),
    MilfolhaTeamDef(id: 'waterfalls_h', displayName: 'H'),
  ];

  static final Set<String> _idSet = all.map((t) => t.id).toSet();

  /// 全チームIDのリスト（定義順）。
  static List<String> get allIds => all.map((t) => t.id).toList();

  /// 入力コードが有効なチームコードか（大文字小文字・前後空白を許容）。
  static bool isValidCode(String code) => _idSet.contains(_normalize(code));

  /// 入力コードを正規化（小文字化・トリム）。一致しなければ null。
  static String? normalizeCode(String code) {
    final n = _normalize(code);
    return _idSet.contains(n) ? n : null;
  }

  static String _normalize(String code) => code.trim().toLowerCase();

  /// id から表示名を引く。未知の id は id をそのまま返す。
  static String displayNameOf(String id) {
    for (final t in all) {
      if (t.id == id) return t.displayName;
    }
    return id;
  }
}

class MilfolhaTeamDef {
  final String id;
  final String displayName;
  const MilfolhaTeamDef({required this.id, required this.displayName});
}
