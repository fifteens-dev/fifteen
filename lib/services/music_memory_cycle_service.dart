import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Music Memory 投稿サイクルの状態を保持するシングルトン。
///
/// サーバ（Cloud Functions `musicMemoryDailyNotification`）が毎日 19:00〜23:30 JST の
/// ランダムな時刻に通知を発火し、その実発火時刻を Firestore
/// `music_memory_state/current.notifiedAt` に記録する。これが「投稿サイクルの境界」。
///
/// - タイムライン表示: `createdAt >= currentCycleStart`（＝直近 notifiedAt 以降）のみ。
/// - 投稿締切: notifiedAt の JST 日付の 24:00。以降は投稿できない（Late 投稿は廃止）。
class MusicMemoryCycleService {
  MusicMemoryCycleService._();
  static final MusicMemoryCycleService _instance =
      MusicMemoryCycleService._();
  factory MusicMemoryCycleService() => _instance;

  static const String _docPath = 'music_memory_state/current';

  /// 「15s Day」境界の履歴コレクション。ドキュメントID = JST の日付キー。
  static const String _cyclesCollection = 'music_memory_cycles';

  DateTime? _notifiedAt;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  /// アプリ起動時に一度呼ぶ。状態ドキュメントの購読を開始する。
  void start() {
    _sub ??= FirebaseFirestore.instance
        .doc(_docPath)
        .snapshots()
        .listen((snap) {
      final ts = snap.data()?['notifiedAt'];
      _notifiedAt = ts is Timestamp ? ts.toDate() : null;
    }, onError: (_) {});
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  /// 直近に発火した通知時刻（サイクル開始）。未取得/未発火なら null。
  DateTime? get notifiedAt => _notifiedAt;

  /// 購読が届く前でも確実に通知時刻が欲しいとき用の 1 回取得。
  /// 取得できた値はキャッシュにも反映する（Live Activity の起動判定などで使う）。
  Future<DateTime?> fetchNotifiedAt() async {
    try {
      final snap = await FirebaseFirestore.instance.doc(_docPath).get();
      final ts = snap.data()?['notifiedAt'];
      if (ts is Timestamp) {
        _notifiedAt = ts.toDate();
        return _notifiedAt;
      }
    } catch (_) {}
    return _notifiedAt;
  }

  /// 任意の [cycleStart] に対する通常投稿締切（JST 翌 01:00）。
  static DateTime deadlineFor(DateTime cycleStart) =>
      _deadlineForCycleStart(cycleStart);

  /// 直近 [limit] 件の「15s Day」を新しい→古い順で返す。
  ///
  /// 1 件目（最新）は現在進行中のサイクルで、[MusicMemoryDayWindow.end] は
  /// 「次の通知が来るまで」＝現時点では未確定なので `null` になる。
  /// 履歴が無い期間（通知が発火していない日）は要素として現れない。
  Future<List<MusicMemoryDayWindow>> loadDays({int limit = 40}) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_cyclesCollection)
          .orderBy('notifiedAt', descending: true)
          .limit(limit)
          .get();

      final starts = <({String key, DateTime start})>[];
      for (final d in snap.docs) {
        final ts = d.data()['notifiedAt'];
        if (ts is! Timestamp) continue;
        starts.add((key: d.id, start: ts.toDate()));
      }
      if (starts.isEmpty) return const [];

      // 新しい→古い順。各サイクルの終端は「1つ新しいサイクルの開始」。
      return [
        for (var i = 0; i < starts.length; i++)
          MusicMemoryDayWindow(
            key: starts[i].key,
            start: starts[i].start,
            end: i == 0 ? null : starts[i - 1].start,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// [at] が属する「15s Day」のキー（＝直近の通知が発火した JST 暦日）。
  /// 対応するサイクルが [days] に無ければ null。
  static String? dayKeyAt(List<MusicMemoryDayWindow> days, DateTime at) {
    for (final d in days) {
      if (d.contains(at)) return d.key;
    }
    return null;
  }

  /// ホームタイムライン表示の下限（現サイクル開始＝直近 notifiedAt）。
  /// 投稿は24時間を超えても、次の通知が来るまで表示し続ける（次の通知で前サイクル分が外れる）。
  /// 状態未取得・未発火のときは now-24h をフォールバックにして空表示を防ぐ。
  DateTime get currentCycleStart =>
      _notifiedAt ?? DateTime.now().subtract(const Duration(hours: 24));

  /// 現サイクルの投稿締切（notifiedAt の JST 日付の 24:00 = 翌 0:00 JST）。
  /// notifiedAt が無いときは null（＝締切判定不能）。
  DateTime? get currentDeadline {
    final start = _notifiedAt;
    if (start == null) return null;
    return _deadlineForCycleStart(start);
  }

  /// 今が投稿できる時間帯か（通知 21:00 〜 24:00）。
  ///
  /// 締切を過ぎたら投稿そのものができない仕様なので、Late 投稿は発生しない。
  /// 通知がまだ来ていない（notifiedAt が無い）ときも投稿できない。
  bool get canPostNow {
    final start = _notifiedAt;
    final deadline = currentDeadline;
    if (start == null || deadline == null) return false;
    final now = DateTime.now();
    return !now.isBefore(start) && now.isBefore(deadline);
  }

  /// [canPostNow] と同じ判定。ただし通知時刻が未取得なら取りに行く。
  ///
  /// 投稿ボタンのように「アプリを開いた直後に押される」経路では
  /// [notifiedAt] がまだ null のことがあり、そのまま見ると
  /// 「通知前」と誤判定してしまう。
  Future<bool> ensureCanPostNow() async {
    if (_notifiedAt == null) await fetchNotifiedAt();
    return canPostNow;
  }

  /// [createdAt] が現サイクルの締切を過ぎているか。
  ///
  /// 21:00〜24:00 以外は投稿できないので、新しい投稿でこれが true になることは
  /// ない。締切が 25:00 だった頃の投稿を判定するために残している。
  bool isLate(DateTime createdAt) {
    final deadline = currentDeadline;
    if (deadline == null) return false;
    return createdAt.toUtc().isAfter(deadline);
  }

  /// サイクル開始（通知時刻）に対する投稿締切の instant を返す。
  /// JST 固定: notifiedAt の JST 暦日の 24:00（＝翌日 0:00 JST）。
  static DateTime _deadlineForCycleStart(DateTime cycleStart) {
    // instant を JST の壁時計（フィールドが JST 値の UTC DateTime）に変換。
    final jst = cycleStart.toUtc().add(const Duration(hours: 9));
    // JST 暦日の翌日 0:00（壁時計）を UTC フィールドとして構築し、9h 引いて instant 化。
    final wall = DateTime.utc(jst.year, jst.month, jst.day)
        .add(const Duration(days: 1));
    return wall.subtract(const Duration(hours: 9));
  }
}


/// 「15s Day」1 日分の時間窓。
///
/// 暦日（0:00 区切り）ではなく **通知が来てから次の通知が来るまで**を 1 日と数える。
/// 例: 9/2 の 15s Day = 9/2 の通知(19:00) 〜 9/3 の通知。
class MusicMemoryDayWindow {
  /// JST の日付キー（"2026-09-02"）。通知が発火した暦日。
  final String key;

  /// 開始（＝その日の通知発火時刻）。
  final DateTime start;

  /// 終了（＝次の通知発火時刻）。進行中のサイクルでは null。
  final DateTime? end;

  const MusicMemoryDayWindow({
    required this.key,
    required this.start,
    this.end,
  });

  bool get isCurrent => end == null;

  /// 表示用の短いラベル（"9/2"）。
  String get label {
    final parts = key.split('-');
    if (parts.length != 3) return key;
    return '${int.parse(parts[1])}/${int.parse(parts[2])}';
  }

  bool contains(DateTime at) =>
      !at.isBefore(start) && (end == null || at.isBefore(end!));
}
