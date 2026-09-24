import 'dart:async';
import 'dart:convert';
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
/// - 締切（24:00）到達 → [refresh] が終了させる
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
      // 閉じている間に push-to-start トークンが変わっていることがある。
      // サーバが古いトークンに送り続けると APNs は 200 を返すのに端末には
      // 何も出ないため、フォアグラウンドのたびに現在値を送り直す。
      await _syncPushToStartToken();

      final cycleStart = await _cycle.fetchNotifiedAt();
      await _log('refresh',
          'cycleStart=${cycleStart?.toIso8601String() ?? "なし"} now=${DateTime.now().toIso8601String()}');

      // 曜日ストリップは**アクティビティの有無に関わらず**書いておく。
      // アクティビティを出す条件（サイクル中であること）と、履歴を共有領域に
      // 用意しておくことは別の話で、一体にすると次の穴が開く:
      //  - サイクル外はデータが更新されず、次に push-to-start で出たときに古い
      //  - 締切後に投稿しても履歴に反映されない
      // アプリが前面に来たこのタイミングで最新にしておけば、21:00 に
      // サーバから開始されたときにも正しい内容で描画される。
      await _syncDaysOnly(uid, cycleStart);

      // 通知がまだ来ていないサイクルでは何も出さない。
      if (cycleStart == null) {
        await _log('refresh', '終了: 通知が未発火');
        await _end();
        return;
      }
      final deadline = MusicMemoryCycleService.deadlineFor(cycleStart);
      if (!DateTime.now().isBefore(deadline)) {
        await _log('refresh', '終了: 締切超過 deadline=${deadline.toIso8601String()}');
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

      await _log('refresh', 'phase=${phase.wire} で反映');
      await _apply(
        uid: uid,
        phase: phase,
        cycleStart: cycleStart,
        deadline: deadline,
      );
    } catch (e) {
      await _log('refresh', 'エラー: $e');
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

      // 締切後の投稿でもストリップ（過去5日の履歴）は更新しておく。
      // アクティビティを更新するかどうかとは別の話。
      await _syncDaysOnly(uid, cycleStart);

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

  /// 調査用ログに 1 行残す（ネイティブ側の共有ログに合流する）。
  /// 失敗しても本処理は止めない。
  Future<void> _log(String tag, String message) async {
    if (!_supportedPlatform) return;
    try {
      await _channel.invokeMethod('log', {'tag': tag, 'message': message});
    } catch (_) {}
  }

  /// アプリ側とウィジェット側のログを時刻順にマージして返す。
  Future<String> readLog() async {
    if (!_supportedPlatform) return 'iOS 以外では利用できません';
    try {
      return await _channel.invokeMethod<String>('logRead') ?? '';
    } catch (e) {
      return 'ログ取得に失敗: $e';
    }
  }

  Future<void> clearLog() async {
    if (!_supportedPlatform) return;
    try {
      await _channel.invokeMethod('logClear');
    } catch (_) {}
  }

  /// 端末側の共有コンテナの状態を取得する（管理者パネルの調査用）。
  /// 曜日ごとのファイル名・存在有無・サイズ・画像として読めるかを返す。
  Future<Map<String, dynamic>?> artworkDiagnostics() async {
    if (!_supportedPlatform) return null;
    try {
      final res = await _channel.invokeMethod<dynamic>('artworkDiagnostics');
      return (res as Map?)?.map((k, v) => MapEntry(k.toString(), v));
    } catch (e) {
      return {'error': e.toString()};
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

  /// 曜日ストリップだけを共有領域へ書き出す（アクティビティは触らない）。
  ///
  /// [cycleStart] が無い（通知が一度も発火していない）場合は、暦日を基準にする。
  Future<void> _syncDaysOnly(String uid, DateTime? cycleStart) async {
    try {
      final anchor = cycleStart ?? DateTime.now();
      final days = await _buildDays(uid, anchor);
      await _channel.invokeMethod('syncDays', {
        'days': await _daysPayload(days),
      });
    } catch (e) {
      if (kDebugMode) print('LiveActivity syncDays failed: $e');
    }
  }

  Future<void> _apply({
    required String uid,
    required LiveActivityPhase phase,
    required DateTime cycleStart,
    required DateTime deadline,
  }) async {
    final days = await _buildDays(uid, cycleStart);

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

  /// ネイティブに現在の push-to-start トークンを送り直させる。
  /// 結果は `onPushToStartToken` として返ってくる。
  Future<void> _syncPushToStartToken() async {
    try {
      await _channel.invokeMethod('syncPushToStartToken');
    } catch (_) {}
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

  /// 直近に Firestore へ書いた push-to-start トークン。同じ値の再書き込みを防ぐ。
  String? _lastSavedPushToStartToken;

  /// push-to-start トークン（iOS 17.2+）。通知と同時にサーバから開始するのに使う。
  Future<void> _savePushToStartToken(String? token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || token == null || token.isEmpty) return;
    if (_lastSavedPushToStartToken == token) return;
    _lastSavedPushToStartToken = token;
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
  ///
  /// 「今日」は暦日ではなく **15s Day**（通知が来てから次の通知まで）で決める。
  /// 暦日にすると深夜 0 時を回った瞬間に今日の枠が空になり、まだ進行中の
  /// サイクルで投稿したはずの 1 枚が「昨日」へずれてしまう。
  Future<List<_DayEntry>> _buildDays(String uid, DateTime cycleStart) async {
    // サイクルが始まった暦日を「今日」とみなす。
    final anchor =
        DateTime(cycleStart.year, cycleStart.month, cycleStart.day);
    final start = anchor.subtract(const Duration(days: 4));
    // 今日の枠にはサイクル中の投稿を入れたいので、翌日分まで拾う
    // （21:00 開始のサイクルは翌 01:00 まで続く）。
    final end = anchor.add(const Duration(days: 2));

    var posts = <PostModel>[];
    try {
      posts = await _postService.getUserPostsInRange(uid, start, end);
    } catch (_) {}

    // 日ごとの代表（その日の最新）を選ぶ。
    // サイクル開始以降の投稿は、暦日をまたいでいても「今日」に寄せる。
    final anchorKey = _dayKey(anchor);
    final byDay = <String, PostModel>{};
    for (final p in posts) {
      if (p.isVibe) continue;
      final key =
          p.createdAt.isBefore(cycleStart) ? _dayKey(p.createdAt) : anchorKey;
      final ex = byDay[key];
      if (ex == null || p.createdAt.isAfter(ex.createdAt)) byDay[key] = p;
    }

    await _log('buildDays',
        'anchor=${_dayKey(anchor)} 取得${posts.length}件 日別${byDay.length}件 '
        '[${byDay.keys.join(",")}]');

    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return [
      for (var i = 4; i >= 0; i--)
        () {
          final day = anchor.subtract(Duration(days: i));
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
      } catch (e) {
        await _log('daysPayload', 'missingArtwork 失敗: $e');
        missing = ids.toSet();
      }
    }
    await _log('daysPayload', '対象${ids.length}件 未取得${missing.length}件');

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
          await _log('download',
              '${d.label}: ${bytes?.length ?? -1}B ${d.imageUrl}');
        }
      }
      payload.add(entry);
    }
    return payload;
  }

  /// アートワークのバイト列を得る。
  ///
  /// `albumImageUrl` は http(s) とは限らない。端末ライブラリの取り込み曲では
  /// 埋め込みアートを `data:image/...;base64,...` で持たせている（[albumImageProvider]
  /// と同じ事情）。http だけを見ていると、それらが常に空＝グレー表示になる。
  /// 画像を取ってくる（http / data URI / ローカルパス）。
  /// ホーム画面ウィジェット側（[FriendWidgetService]）からも使う。
  Future<Uint8List?> downloadImage(String url) => _download(url);

  Future<Uint8List?> _download(String url) async {
    if (url.isEmpty) return null;

    // data URI はその場でデコードする（ネットワーク不要）。
    if (url.startsWith('data:')) {
      final i = url.indexOf(',');
      if (i < 0) return null;
      try {
        return base64Decode(url.substring(i + 1));
      } catch (_) {
        return null;
      }
    }

    // ローカルファイルパスはそのまま読む。
    if (url.startsWith('file://') || url.startsWith('/')) {
      try {
        final path = url.startsWith('file://') ? url.substring(7) : url;
        final file = File(path);
        if (!await file.exists()) return null;
        return await file.readAsBytes();
      } catch (_) {
        return null;
      }
    }

    if (!url.startsWith('http')) return null;
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
