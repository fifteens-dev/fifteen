import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/post_model.dart';
import 'music_memory_cycle_service.dart';
import 'post_service.dart';
import 'user_service.dart';

/// Live Activity の 3 パターン（Figma 5305:12537 / 12623 / 12685）。
enum LiveActivityPhase {
  /// 通知は来たが、フォロー中の誰もまだ投稿していない。
  waiting('waiting'),

  /// 通知が来ていて、かつフォロー中の誰かが投稿済み（＝友達が待っている）。
  friendsWaiting('friendsWaiting'),

  /// このサイクルの投稿が完了した。
  posted('posted');

  const LiveActivityPhase(this.wire);

  /// ネイティブ / APNs とやり取りする文字列表現。
  final String wire;
}

/// iOS の Live Activity（ロック画面・通知センターの「今日のMusic Memory」）を
/// 制御するサービス。Android では全メソッドが no-op。
///
/// # 構成
/// - 状態（phase / 締切）は ContentState としてネイティブへ渡す。APNs push でも
///   同じ形が飛んでくるため、サーバは phase だけ差し替えれば良い。
/// - 曜日ストリップ（過去4日＋今日のアートワーク）は push では送らず、
///   App Group の共有コンテナへ本サービスが書き出す。ウィジェットが描画時に読む。
///
/// # 更新タイミング
/// - アプリ起動 / フォアグラウンド復帰 → [refresh]
/// - Music Memory 通知の受信 → [refresh]
/// - 投稿完了 → [markPosted]
/// - 締切（25:00）到達 → [refresh] が終了させる
/// - フォロー中の誰かが投稿 → Cloud Functions が APNs push で phase を差し替え
class LiveActivityService {
  LiveActivityService._();
  static final LiveActivityService _instance = LiveActivityService._();
  factory LiveActivityService() => _instance;

  static const MethodChannel _channel =
      MethodChannel('com.fifteen.liveactivity');

  final PostService _postService = PostService();
  final UserService _userService = UserService();
  final MusicMemoryCycleService _cycle = MusicMemoryCycleService();

  bool _handlerAttached = false;
  bool _refreshing = false;

  /// 直近に [refresh] が Firestore を引いた時刻。フォアグラウンド復帰の連打で
  /// 毎回 5 クエリ投げないよう間隔を空ける。
  DateTime? _lastRefreshAt;
  static const Duration _minRefreshInterval = Duration(seconds: 60);

  bool get _supportedPlatform => !kIsWeb && Platform.isIOS;

  /// アプリ起動時に一度呼ぶ。push トークンのコールバックを受け取れるようにする。
  void start() {
    if (!_supportedPlatform || _handlerAttached) return;
    _handlerAttached = true;
    _channel.setMethodCallHandler(_onNativeCall);
  }

  Future<void> _onNativeCall(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
    switch (call.method) {
      case 'onPushToken':
        await _saveUpdateToken(args['token'] as String?, args['activityId'] as String?);
        break;
      case 'onPushToStartToken':
        await _savePushToStartToken(args['token'] as String?);
        break;
    }
  }

  // ─────────────────────────────────────────────────────────
  // 公開 API
  // ─────────────────────────────────────────────────────────

  /// 現在の状況を評価して Live Activity を開始 / 更新 / 終了する。
  ///
  /// - 通知がまだ発火していない、または締切を過ぎている → 終了
  /// - 未投稿 → [LiveActivityPhase.waiting] / [LiveActivityPhase.friendsWaiting]
  /// - 投稿済み → [LiveActivityPhase.posted]
  ///
  /// [force] が false のときは [_minRefreshInterval] 以内の再呼び出しを無視する。
  Future<void> refresh({bool force = false}) async {
    if (!_supportedPlatform || _refreshing) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final last = _lastRefreshAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _minRefreshInterval) {
      return;
    }
    _lastRefreshAt = DateTime.now();

    _refreshing = true;
    try {
      final cycleStart = await _cycle.fetchNotifiedAt();
      // 通知がまだ来ていないサイクルでは何も出さない。
      if (cycleStart == null) {
        await _end();
        return;
      }
      final deadline = MusicMemoryCycleService.deadlineFor(cycleStart);
      if (!DateTime.now().isBefore(deadline)) {
        await _end();
        return;
      }

      final posted = await _postService.hasAnyPostInCurrentCycle(uid);
      LiveActivityPhase phase;
      if (posted) {
        phase = LiveActivityPhase.posted;
      } else {
        final me = await _userService.getUser(uid);
        final friendsPosted = await _postService
            .hasFollowingPostedInCurrentCycle(me?.following ?? const []);
        phase = friendsPosted
            ? LiveActivityPhase.friendsWaiting
            : LiveActivityPhase.waiting;
      }

      await _apply(
        uid: uid,
        phase: phase,
        cycleStart: cycleStart,
        deadline: deadline,
      );
    } catch (e) {
      if (kDebugMode) print('LiveActivity refresh error: $e');
    } finally {
      _refreshing = false;
    }
  }

  /// 投稿が完了したときに呼ぶ（フェーズを「投稿完了」へ、今日の枠にアートを入れる）。
  Future<void> markPosted() async {
    if (!_supportedPlatform) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final cycleStart = await _cycle.fetchNotifiedAt();
      if (cycleStart == null) return;
      final deadline = MusicMemoryCycleService.deadlineFor(cycleStart);
      if (!DateTime.now().isBefore(deadline)) return;
      await _apply(
        uid: uid,
        phase: LiveActivityPhase.posted,
        cycleStart: cycleStart,
        deadline: deadline,
      );
      _lastRefreshAt = DateTime.now();
    } catch (e) {
      if (kDebugMode) print('LiveActivity markPosted error: $e');
    }
  }

  /// サインアウト時などに、表示中のアクティビティを片付ける。
  Future<void> stop() async {
    if (!_supportedPlatform) return;
    _lastRefreshAt = null;
    await _end(immediately: true);
  }

  // ─────────────────────────────────────────────────────────
  // 内部
  // ─────────────────────────────────────────────────────────

  Future<void> _apply({
    required String uid,
    required LiveActivityPhase phase,
    required DateTime cycleStart,
    required DateTime deadline,
  }) async {
    final days = await _buildDays(uid);

    // 秒精度のエポックを版番号にする。ローカル更新と push 更新の前後関係を
    // ネイティブ / サーバの双方が同じ基準で判定できる。
    final revision = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final payload = <String, dynamic>{
      'phase': phase.wire,
      'cycleStartMs': cycleStart.millisecondsSinceEpoch,
      'deadlineMs': deadline.millisecondsSinceEpoch,
      'staleMs': deadline.millisecondsSinceEpoch,
      'revision': revision,
      'days': await _daysPayload(days),
    };

    try {
      final result = await _channel.invokeMethod<dynamic>('start', payload);
      final info = (result as Map?)?.cast<String, dynamic>();

      await _writeState(
        uid: uid,
        phase: phase,
        cycleStart: cycleStart,
        deadline: deadline,
        revision: revision,
        activityId: info?['activityId'] as String?,
        token: info?['token'] as String?,
      );
    } on PlatformException catch (e) {
      // ユーザーが Live Activity をオフにしている場合など。静かに諦める。
      if (kDebugMode) print('LiveActivity start failed: ${e.code} ${e.message}');
    }
  }

  Future<void> _end({bool immediately = false}) async {
    try {
      await _channel.invokeMethod('end', {'immediately': immediately});
    } catch (_) {}
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('live_activities')
          .doc(uid)
          .delete();
    } catch (_) {}
  }

  /// サーバ（Cloud Functions）が push 更新するのに必要な情報を書く。
  Future<void> _writeState({
    required String uid,
    required LiveActivityPhase phase,
    required DateTime cycleStart,
    required DateTime deadline,
    required int revision,
    String? activityId,
    String? token,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('live_activities')
          .doc(uid)
          .set({
        'userId': uid,
        'phase': phase.wire,
        'cycleStart': Timestamp.fromDate(cycleStart),
        'deadline': Timestamp.fromDate(deadline),
        'revision': revision,
        if (activityId != null) 'activityId': activityId,
        if (token != null) 'pushToken': token,
        'platform': 'ios',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) print('LiveActivity state write failed: $e');
    }
  }

  Future<void> _saveUpdateToken(String? token, String? activityId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || token == null || token.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('live_activities')
          .doc(uid)
          .set({
        'userId': uid,
        'pushToken': token,
        if (activityId != null) 'activityId': activityId,
        'platform': 'ios',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) print('LiveActivity token save failed: $e');
    }
  }

  /// push-to-start トークン（iOS 17.2+）。通知と同時にサーバから開始するのに使う。
  Future<void> _savePushToStartToken(String? token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || token == null || token.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'liveActivityPushToStartToken': token,
        'liveActivityTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) print('LiveActivity push-to-start token save failed: $e');
    }
  }

  // ── 曜日ストリップ ────────────────────────────────────────

  /// 過去 4 日 ＋ 今日（古い→新しい）の 5 枠を、自分の投稿から作る。
  Future<List<_DayEntry>> _buildDays(String uid) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(const Duration(days: 4));
    final end = today.add(const Duration(days: 1));

    var posts = <PostModel>[];
    try {
      posts = await _postService.getUserPostsInRange(uid, start, end);
    } catch (_) {}

    // 日ごとの代表（その日の最新）を選ぶ。
    final byDay = <String, PostModel>{};
    for (final p in posts) {
      if (p.isVibe) continue;
      final key = _dayKey(p.createdAt);
      final ex = byDay[key];
      if (ex == null || p.createdAt.isAfter(ex.createdAt)) byDay[key] = p;
    }

    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return [
      for (var i = 4; i >= 0; i--)
        () {
          final day = today.subtract(Duration(days: i));
          final post = byDay[_dayKey(day)];
          return _DayEntry(
            label: i == 0 ? '今日' : weekdays[day.weekday - 1],
            isToday: i == 0,
            imageId: post?.postId,
            imageUrl: post?.track.albumImageUrl,
          );
        }(),
    ];
  }

  /// ネイティブに渡す形へ。まだ共有コンテナに無いアートだけダウンロードする。
  Future<List<Map<String, dynamic>>> _daysPayload(List<_DayEntry> days) async {
    final ids = days
        .where((d) => (d.imageId ?? '').isNotEmpty && (d.imageUrl ?? '').isNotEmpty)
        .map((d) => d.imageId!)
        .toList();

    var missing = <String>{};
    if (ids.isNotEmpty) {
      try {
        final res = await _channel.invokeMethod<List<dynamic>>(
          'missingArtwork',
          {'ids': ids},
        );
        missing = (res ?? const []).map((e) => e.toString()).toSet();
      } catch (_) {
        missing = ids.toSet();
      }
    }

    final payload = <Map<String, dynamic>>[];
    for (final d in days) {
      final entry = <String, dynamic>{
        'label': d.label,
        'isToday': d.isToday,
      };
      if ((d.imageId ?? '').isNotEmpty) {
        entry['imageId'] = d.imageId;
        if (missing.contains(d.imageId)) {
          final bytes = await _download(d.imageUrl!);
          if (bytes != null) entry['imageBytes'] = bytes;
        }
      }
      payload.add(entry);
    }
    return payload;
  }

  Future<Uint8List?> _download(String url) async {
    if (url.isEmpty || !url.startsWith('http')) return null;
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
}

/// ストリップ 1 枠（ネイティブ送信前の中間表現）。
class _DayEntry {
  final String label;
  final bool isToday;

  /// 共有コンテナ上のファイル名の元。投稿の postId をそのまま使う。
  final String? imageId;
  final String? imageUrl;

  const _DayEntry({
    required this.label,
    required this.isToday,
    this.imageId,
    this.imageUrl,
  });
}
