import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// 音楽再生を管理するサービス（Singleton）
class AudioPlayerService {
  // Singleton instance
  static final AudioPlayerService _instance = AudioPlayerService._internal();

  // Factory constructor
  factory AudioPlayerService() {
    return _instance;
  }

  // Private constructor
  AudioPlayerService._internal() {
    _configureAudioSession();
  }

  /// オーディオセッションを設定（他のアプリの音楽を止めない）
  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
    ));
  }

  AudioPlayer? _audioPlayer;
  String? _currentUrl;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  Duration _startFrom = Duration.zero;
  int _durationSeconds = 15;

  // 再生オーナー。playPreview(owner: this) を呼んだ画面/オブジェクトが所有者となる。
  // 他画面の dispose() で誤って stopIfOwner(this) されても再生は止めない。
  Object? _currentOwner;

  // 次カード用プリローダー (setUrl 済みで待機)
  AudioPlayer? _preloader;
  String? _preloadedUrl;
  Duration _preloadStartFrom = Duration.zero;
  int _preloadDurationSec = 15;

  /// AudioPlayerのインスタンスを取得（必要に応じて作成）
  AudioPlayer get _player {
    _audioPlayer ??= AudioPlayer();
    return _audioPlayer!;
  }

  /// ループ監視を開始（startFrom〜startFrom+duration区間）
  void _startLoopMonitor() {
    _positionSubscription?.cancel();
    _stateSubscription?.cancel();

    final loopEnd = _startFrom + Duration(seconds: _durationSeconds);

    // ポジションベースのループ（区間終端を超えたらシーク）
    _positionSubscription = _player.positionStream.listen((position) {
      if (position >= loopEnd && _player.playing) {
        _player.seek(_startFrom);
      }
    });

    // ステートベースのループ（ファイル終端まで再生された場合の補完）
    // loopEnd がファイル長と一致する場合（例: 最後の15秒を切り取った場合）、
    // positionStream の更新前に playing=false になりループが発動しないため、
    // processingState.completed を監視して確実にシーク＆再生する
    _stateSubscription = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed &&
          _currentUrl != null) {
        _player.seek(_startFrom).then((_) {
          if (_currentUrl != null) {
            _player.play().catchError((e) {
              if (kDebugMode) print('❌ Loop re-play error: $e');
            });
          }
        });
      }
    });
  }

  /// プレビューURLから音楽を再生（指定区間ループ）
  ///
  /// [owner] を渡すと再生の所有者が記録され、他画面の dispose() による
  /// stopIfOwner() で巻き添えに止められなくなる（チュートリアル等で利用）。
  Future<void> playPreview(
    String url, {
    Duration startFrom = Duration.zero,
    int durationSeconds = 15,
    Object? owner,
  }) async {
    try {
      if (kDebugMode) print('🎵 Attempting to play: $url');

      // URLの妥当性チェック
      if (url.isEmpty) {
        if (kDebugMode) print('❌ Empty URL provided');
        return;
      }

      // 所有者を更新（null の場合は所有者なし＝従来挙動）
      _currentOwner = owner;

      // 既に同じURLが再生中 or ロード中の場合は何もしない
      if (_currentUrl == url &&
          _startFrom == startFrom && _durationSeconds == durationSeconds) {
        final ps = _player.processingState;
        if (_player.playing ||
            ps == ProcessingState.loading ||
            ps == ProcessingState.buffering) {
          if (kDebugMode) print('⏭️ Already playing/loading this URL');
          return;
        }
      }

      // プリローダーが該当URLを既にsetUrl済みなら、スワップして即再生（最速パス）
      if (_promotePreloadedIfMatch(url, startFrom, durationSeconds)) {
        if (kDebugMode) print('⚡ Swapped from preloader, starting playback');
        _audioPlayer!.play().catchError((e) {
          if (kDebugMode) print('❌ Play error: $e');
        });
        return;
      }

      // 別のURLが再生中の場合: stop は fire-and-forget（await しない）
      // _currentUrl を先に更新してループモニターのレースを防ぐ
      final oldUrl = _currentUrl;
      _currentUrl = url;
      _startFrom = startFrom;
      _durationSeconds = durationSeconds;

      if (oldUrl != null && oldUrl != url && _player.playing) {
        if (kDebugMode) print('⏹️ Stopping current playback (fire-and-forget)');
        // 既存サブスクリプションは setUrl 後に再構築されるため先にキャンセル
        _positionSubscription?.cancel();
        _positionSubscription = null;
        _stateSubscription?.cancel();
        _stateSubscription = null;
        unawaited(_player.stop());
      }

      // 新しいURLをセット
      if (kDebugMode) print('📥 Loading audio from URL...');
      await _player.setUrl(url);

      // ループモードはoff（手動でループを制御）
      await _player.setLoopMode(LoopMode.off);

      // 開始位置にシーク
      if (startFrom > Duration.zero) {
        await _player.seek(startFrom);
      }

      // ループ監視を開始
      _startLoopMonitor();

      // 再生開始（awaitしない: ループはモニター内で管理するため、
      // play()の完了を待つ必要はなく、即座にreturnして呼び出し元をブロックしない）
      if (kDebugMode) print('▶️ Starting playback...');
      _player.play().catchError((e) {
        if (kDebugMode) print('❌ Play error: $e');
      });

      if (kDebugMode) print('✅ Successfully playing preview');
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ Error playing preview: $e');
        print('Stack trace: $stackTrace');
        print('Failed URL: $url');
      }

      // ユーザーにもエラーを通知
      rethrow;
    }
  }

  /// 次カードの音声を事前ロード（setUrl のみ、再生はしない）
  /// タップ時に playPreview() がプリローダーを検出して即スワップ→再生する。
  Future<void> preload(
    String url, {
    Duration startFrom = Duration.zero,
    int durationSeconds = 15,
  }) async {
    if (url.isEmpty) return;
    // 同じURLを再生中ならプリロード不要
    if (_currentUrl == url) return;
    // 既に同条件でプリロード済みならスキップ
    if (_preloadedUrl == url &&
        _preloadStartFrom == startFrom &&
        _preloadDurationSec == durationSeconds) {
      return;
    }

    // 既存プリローダーは破棄
    final old = _preloader;
    _preloader = null;
    _preloadedUrl = null;
    if (old != null) {
      unawaited(_disposeIsolatedPlayer(old));
    }

    final p = AudioPlayer();
    _preloader = p;
    _preloadedUrl = url;
    _preloadStartFrom = startFrom;
    _preloadDurationSec = durationSeconds;

    try {
      await p.setUrl(url);
      await p.setLoopMode(LoopMode.off);
      if (startFrom > Duration.zero) {
        await p.seek(startFrom);
      }
      if (kDebugMode) print('🧊 Preloaded: $url');
    } catch (e) {
      if (kDebugMode) print('⚠️ Preload failed: $e');
      // 失敗時は破棄。次回 playPreview は通常パスで取得する
      if (identical(_preloader, p)) {
        _preloader = null;
        _preloadedUrl = null;
      }
      unawaited(_disposeIsolatedPlayer(p));
    }
  }

  /// プリローダーがリクエストURLと一致すればメインプレイヤーに昇格してスワップ。
  /// 一致した場合 true を返し呼び出し側で play() を実行。
  bool _promotePreloadedIfMatch(
      String url, Duration startFrom, int durationSeconds) {
    if (_preloader == null || _preloadedUrl != url) return false;
    if (_preloadStartFrom != startFrom || _preloadDurationSec != durationSeconds) {
      return false;
    }

    // 古いメインプレイヤーは fire-and-forget で停止+破棄
    final oldMain = _audioPlayer;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _stateSubscription?.cancel();
    _stateSubscription = null;
    if (oldMain != null) {
      unawaited(_disposeIsolatedPlayer(oldMain));
    }

    // スワップ
    _audioPlayer = _preloader;
    _preloader = null;
    _currentUrl = url;
    _startFrom = startFrom;
    _durationSeconds = durationSeconds;
    _preloadedUrl = null;

    // 新しいプレイヤーでループ監視を再構築
    _startLoopMonitor();
    return true;
  }

  Future<void> _disposeIsolatedPlayer(AudioPlayer p) async {
    try {
      await p.stop();
    } catch (_) {}
    try {
      await p.dispose();
    } catch (_) {}
  }

  /// シーク
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// 楽曲の実際の長さ
  Duration? get totalDuration => _player.duration;

  /// 再生を一時停止
  Future<void> pause() async {
    try {
      await _player.pause();
      if (kDebugMode) print('Paused playback');
    } catch (e) {
      if (kDebugMode) print('Error pausing playback: $e');
    }
  }

  /// 再生を再開
  Future<void> resume() async {
    try {
      await _player.play();
      if (kDebugMode) print('Resumed playback');
    } catch (e) {
      if (kDebugMode) print('Error resuming playback: $e');
    }
  }

  /// 再生を停止（無条件）。
  ///
  /// 注意: 本サービスはシングルトンのため、画面の `dispose()` から無条件に呼ぶと
  /// 他画面が再生中の音声まで巻き添えで止まる。`dispose()` からは
  /// [stopIfOwner] を使い、ボタンタップなど明示的な停止意図がある場合のみ
  /// この `stop()` を直接呼ぶこと。
  Future<void> stop() async {
    try {
      _positionSubscription?.cancel();
      _positionSubscription = null;
      _stateSubscription?.cancel();
      _stateSubscription = null;
      _currentUrl = null; // 先にnullにしてループ再開を防ぐ
      _currentOwner = null;
      _startFrom = Duration.zero;
      _durationSeconds = 15;
      await _player.stop();
      if (kDebugMode) print('Stopped playback');
    } catch (e) {
      if (kDebugMode) print('Error stopping playback: $e');
    }
  }

  /// 所有権付き stop。dispose() から呼び出すことで、他画面が所有する再生を
  /// 巻き添えに止めるバグを防ぐ。
  ///
  /// 動作:
  /// - `_currentOwner` が null（未所有）→ そのまま stop（従来挙動）
  /// - `_currentOwner` が owner と同一 → stop
  /// - 別オーナーの再生中 → 何もしない
  Future<void> stopIfOwner(Object owner) async {
    if (_currentOwner != null && !identical(_currentOwner, owner)) {
      if (kDebugMode) {
        print('⏭️ stopIfOwner skipped: not the owner');
      }
      return;
    }
    await stop();
  }

  /// 現在再生中かどうか
  bool get isPlaying => _player.playing;

  /// 現在再生中または一時停止中のURL
  String? get currentUrl => _currentUrl;

  /// 現在一時停止中かどうか
  bool get isPaused => _player.processingState == ProcessingState.ready && !_player.playing;

  /// 現在のURLが指定されたURLかどうか
  bool isPlayingUrl(String url) => _currentUrl == url && _player.playing;

  /// プレビューの長さ
  Duration get previewDuration => Duration(seconds: _durationSeconds);

  /// プレイヤーの状態ストリーム
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// 再生位置のストリーム（区間内の相対位置）
  Stream<Duration> get positionStream =>
      _player.positionStream.map((pos) {
        final relative = pos - _startFrom;
        final limit = Duration(seconds: _durationSeconds);
        if (relative < Duration.zero) return Duration.zero;
        return relative > limit ? limit : relative;
      });

  /// 楽曲の長さのストリーム
  Stream<Duration?> get durationStream =>
      _player.durationStream.map((_) => Duration(seconds: _durationSeconds));

  /// 現在の楽曲の長さ
  Duration? get duration => Duration(seconds: _durationSeconds);

  /// 現在の再生位置（区間内の相対位置）
  Duration get position {
    final pos = _player.position - _startFrom;
    final limit = Duration(seconds: _durationSeconds);
    if (pos < Duration.zero) return Duration.zero;
    return pos > limit ? limit : pos;
  }

  /// リソースを解放
  Future<void> dispose() async {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _stateSubscription?.cancel();
    _stateSubscription = null;
    await _audioPlayer?.dispose();
    _audioPlayer = null;
    _currentUrl = null;
    _currentOwner = null;
    final pre = _preloader;
    _preloader = null;
    _preloadedUrl = null;
    if (pre != null) {
      await pre.dispose();
    }
  }
}
