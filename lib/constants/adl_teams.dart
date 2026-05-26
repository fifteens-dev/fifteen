/// ADL イベントの固定9班定義。
///
/// 班ID = 招待コード = 班アカウント UID = 班名 はすべて同一文字列。
/// users/{teamId} に班アカウントを、adl_teams/{teamId} に班統計を持つ。
class AdlTeamDefinitions {
  AdlTeamDefinitions._();

  /// 9つの固定班。順序はランキング表示や管理パネルの並び順に使われる。
  static const List<AdlTeamDef> all = [
    AdlTeamDef(id: 'adl_house', displayName: 'House'),
    AdlTeamDef(id: 'adl_break', displayName: 'Break'),
    AdlTeamDef(id: 'adl_girls', displayName: 'Girls'),
    AdlTeamDef(id: 'adl_hiphop', displayName: 'HipHop'),
    AdlTeamDef(id: 'adl_new', displayName: 'New'),
    AdlTeamDef(id: 'adl_free', displayName: 'Free'),
    AdlTeamDef(id: 'adl_lock', displayName: 'Lock'),
    AdlTeamDef(id: 'adl_waack', displayName: 'Waack'),
    AdlTeamDef(id: 'adl_jazz', displayName: 'Jazz'),
  ];

  static final Set<String> _idSet = all.map((t) => t.id).toSet();

  /// 入力されたコード文字列が9つの固定コードのいずれかに一致するか。
  /// 大文字小文字・前後空白を許容する。
  static bool isValidCode(String code) {
    return _idSet.contains(_normalize(code));
  }

  /// users/{uid} の uid が 9班アカウントのいずれかに一致するか。
  /// users コレクションでの id 完全一致のため正規化はしない。
  static bool isTeamAccountUid(String uid) {
    return _idSet.contains(uid);
  }

  /// 入力コードを正規化（小文字化・トリム）。一致しない場合は null。
  static String? normalizeCode(String code) {
    final n = _normalize(code);
    return _idSet.contains(n) ? n : null;
  }

  static String _normalize(String code) => code.trim().toLowerCase();

  /// id から表示名を引く。未知のidの場合はidをそのまま返す。
  static String displayNameOf(String id) {
    for (final t in all) {
      if (t.id == id) return t.displayName;
    }
    return id;
  }
}

class AdlTeamDef {
  final String id;
  final String displayName;
  const AdlTeamDef({required this.id, required this.displayName});
}
