import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Music Memory 投稿サイクルの状態を保持するシングルトン。
///
/// サーバ（Cloud Functions `musicMemoryDailyNotification`）が毎日 19:00〜23:30 JST の
/// ランダムな時刻に通知を発火し、その実発火時刻を Firestore
/// `music_memory_state/current.notifiedAt` に記録する。これが「投稿サイクルの境界」。
///
/// - タイムライン表示: `createdAt >= currentCycleStart`（＝直近 notifiedAt 以降）のみ。
/// - 通常投稿締切: notifiedAt の JST 日付 + 1 日 01:00（＝「25:00」）。以降は Late 投稿。
class MusicMemoryCycleService {
  MusicMemoryCycleService._();
  static final MusicMemoryCycleService _instance =
      MusicMemoryCycleService._();
  factory MusicMemoryCycleService() => _instance;

  static const String _docPath = 'music_memory_state/current';

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

  /// タイムライン表示の下限（現サイクル開始）。
  /// 状態未取得・未発火のときは従来どおり now-24h をフォールバックにして
  /// タイムラインが空にならないようにする。
  DateTime get currentCycleStart =>
      _notifiedAt ?? DateTime.now().subtract(const Duration(hours: 24));

  /// 現サイクルの通常投稿締切（notifiedAt の JST 日付 + 1 日 01:00 JST）。
  /// notifiedAt が無いときは null（＝締切判定不能）。
  DateTime? get currentDeadline {
    final start = _notifiedAt;
    if (start == null) return null;
    return _deadlineForCycleStart(start);
  }

  /// [createdAt] が現サイクルの締切を過ぎている（＝Late 投稿）か。
  /// 締切不明のときは false（＝通常投稿扱い）。
  bool isLate(DateTime createdAt) {
    final deadline = currentDeadline;
    if (deadline == null) return false;
    return createdAt.toUtc().isAfter(deadline);
  }

  /// サイクル開始（通知時刻）に対する通常投稿締切の instant を返す。
  /// JST 固定: notifiedAt の JST 暦日 + 1 日 01:00 JST。
  static DateTime _deadlineForCycleStart(DateTime cycleStart) {
    // instant を JST の壁時計（フィールドが JST 値の UTC DateTime）に変換。
    final jst = cycleStart.toUtc().add(const Duration(hours: 9));
    // JST 暦日の翌日 01:00（壁時計）を UTC フィールドとして構築し、9h 引いて instant 化。
    final wall = DateTime.utc(jst.year, jst.month, jst.day, 1)
        .add(const Duration(days: 1));
    return wall.subtract(const Duration(hours: 9));
  }
}
