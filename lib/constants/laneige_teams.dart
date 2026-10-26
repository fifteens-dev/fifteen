/// Laneige 対抗バトルイベントのチーム定義。
///
/// コード = チームID = `laneige_a` 〜 `laneige_h`（表示名 A〜H）。
/// チーム数/名はこの [all] 配列1箇所で増減できる（確定後に調整）。
class LaneigeTeamDefinitions {
  LaneigeTeamDefinitions._();

  /// 8チーム（A〜H）。順序はランキング表示や管理パネルの並び順に使う。
  static const List<LaneigeTeamDef> all = [
    LaneigeTeamDef(id: 'laneige_a', displayName: 'A'),
    LaneigeTeamDef(id: 'laneige_b', displayName: 'B'),
    LaneigeTeamDef(id: 'laneige_c', displayName: 'C'),
    LaneigeTeamDef(id: 'laneige_d', displayName: 'D'),
    LaneigeTeamDef(id: 'laneige_e', displayName: 'E'),
    LaneigeTeamDef(id: 'laneige_f', displayName: 'F'),
    LaneigeTeamDef(id: 'laneige_g', displayName: 'G'),
    LaneigeTeamDef(id: 'laneige_h', displayName: 'H'),
  ];

  static final Set<String> _idSet = all.map((t) => t.id).toSet();

  /// 全チームIDのリスト（定義順）。
  static List<String> get allIds => all.map((t) => t.id).toList();

  /// 入力コードが有効なチームコードか（大文字小文字・前後空白を許容）。
  static bool isValidCode(String code) => _idSet.contains(_normalize(code));

  /// users/{uid} の uid がチームアカウント（8チームのいずれか）に一致するか。
  /// users コレクションでの id 完全一致のため正規化はしない。
  static bool isTeamAccountUid(String uid) => _idSet.contains(uid);

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

class LaneigeTeamDef {
  final String id;
  final String displayName;
  const LaneigeTeamDef({required this.id, required this.displayName});
}
