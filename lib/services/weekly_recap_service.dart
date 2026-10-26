import '../models/post_model.dart';
import 'post_service.dart';

/// Weekly Recap の 1 週間ぶん。
class WeeklyRecap {
  /// 週の始まり（日曜 0:00）。
  final DateTime start;

  /// 週の終わり（翌週日曜 0:00。この時刻は含まない）。
  final DateTime end;

  /// 各日の代表 1 件（その日の最新）。古い→新しい順。
  final List<PostModel> posts;

  const WeeklyRecap({required this.start, required this.end, required this.posts});

  /// 週の最終日（土曜）。表示用。
  DateTime get lastDay => end.subtract(const Duration(days: 1));

  /// "Oct 19 - Oct 25, 2026"。年をまたぐ週は始まりにも年を付ける。
  /// [withYear] が false なら年を省く（"Oct 19 - Oct 25"）。
  String rangeLabel({bool withYear = true}) {
    final s = start;
    final e = lastDay;
    String md(DateTime d) => '${_kMonths[d.month - 1]} ${d.day}';
    if (!withYear) return '${md(s)} - ${md(e)}';
    final startLabel = s.year == e.year ? md(s) : '${md(s)}, ${s.year}';
    return '$startLabel - ${md(e)}, ${e.year}';
  }
}

const List<String> _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Weekly Recap の期間計算と投稿の取得。
///
/// 週は日曜はじまり・土曜おわり。土曜が終わるまでは前の週を見せるので、
/// 表示するのは「いま進行中の週の 1 つ前」の週になる。
/// 通知（日曜 12:00）も同じ週を指す。
class WeeklyRecapService {
  final PostService _postService = PostService();

  /// [now] から見た、直近で終わった週の日曜 0:00。
  static DateTime lastCompletedWeekStart(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    // DateTime.weekday は 月=1 … 日=7。日曜からの経過日数にする。
    final daysSinceSunday = today.weekday % 7;
    final thisWeekStart = DateTime(today.year, today.month, today.day - daysSinceSunday);
    return DateTime(thisWeekStart.year, thisWeekStart.month, thisWeekStart.day - 7);
  }

  /// 通知の data にある週の開始日（"YYYY-MM-DD"）を読む。読めなければ null。
  static DateTime? parseWeekKey(String? key) {
    if (key == null) return null;
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  Future<WeeklyRecap> load(String userId, {DateTime? weekStart}) async {
    final start = weekStart ?? lastCompletedWeekStart(DateTime.now());
    final end = DateTime(start.year, start.month, start.day + 7);
    final all = await _postService.getUserPostsInRange(userId, start, end);

    // Music Memory のカレンダーと同じく、各日の最新 1 件を代表にする。
    final repByDay = <String, PostModel>{};
    for (final p in all) {
      final key = '${p.createdAt.year}-${p.createdAt.month}-${p.createdAt.day}';
      final ex = repByDay[key];
      if (ex == null || p.createdAt.isAfter(ex.createdAt)) repByDay[key] = p;
    }
    final posts = repByDay.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return WeeklyRecap(start: start, end: end, posts: posts);
  }
}
