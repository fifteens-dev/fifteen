/// Campus Vibe の日付・表示条件に関するユーティリティ
/// PostService などのサービスクラスと独立させることで単体テスト可能
class CampusVibeUtils {
  CampusVibeUtils._();

  /// 今週の Campus Vibe 対象大学
  /// プレリリース期間は固定。将来的には週替わりで切り替える。
  static const String targetUniversity = '青山学院大学';

  /// 今日が Campus Vibe 表示期間（金・土・日）かどうか
  static bool isWeekend([DateTime? now]) {
    final w = (now ?? DateTime.now()).weekday;
    return w == DateTime.friday || w == DateTime.saturday || w == DateTime.sunday;
  }

  /// 直近の金曜 00:00:00 〜 日曜 23:59:59 の範囲を返す（現地時間）
  static ({DateTime start, DateTime end}) weekendRange([DateTime? now]) {
    final today = now ?? DateTime.now();
    final daysFromFriday = (today.weekday - DateTime.friday) % 7;
    final friday = DateTime(today.year, today.month, today.day - daysFromFriday);
    final sundayEnd = DateTime(friday.year, friday.month, friday.day + 2, 23, 59, 59);
    return (start: friday, end: sundayEnd);
  }

  /// Campus Vibe カードの表示条件
  /// 閲覧は全ユーザー対象のため、所属大学を問わず週末であれば true
  static bool shouldShow([DateTime? now]) => isWeekend(now);

  /// Campus Vibe への投稿可否
  /// 対象大学に所属しており、かつ週末のみ投稿可能
  static bool canPost(String? university, [DateTime? now]) =>
      university == targetUniversity && isWeekend(now);
}
