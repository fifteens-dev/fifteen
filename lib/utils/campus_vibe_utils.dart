/// Campus Vibe の日付・表示条件に関するユーティリティ
/// PostService などのサービスクラスと独立させることで単体テスト可能
class CampusVibeUtils {
  CampusVibeUtils._();

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

  /// 大学名が設定されており、かつ今週末であれば Campus Vibe を表示すべきか判定
  static bool shouldShow(String? university) {
    return university != null && university.isNotEmpty && isWeekend();
  }
}
