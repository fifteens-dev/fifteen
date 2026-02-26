import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

/// プレビュー再生の長さ
const _previewDuration = Duration(seconds: 15);

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
              print('❌ Loop re-play error: $e');
            });
          }
        });
      }
    });
  }

  /// プレビューURLから音楽を再生（指定区間ループ）
  Future<void> playPreview(
    String url, {
    Duration startFrom = Duration.zero,
    int durationSeconds = 15,
  }) async {
    try {
      print('🎵 Attempting to play: $url');

      // URLの妥当性チェック
      if (url.isEmpty) {
        print('❌ Empty URL provided');
        return;
      }

      // 既に同じURLが再生中の場合は何もしない
      if (_currentUrl == url && _player.playing &&
          _startFrom == startFrom && _durationSeconds == durationSeconds) {
        print('⏭️ Already playing this URL');
        return;
      }

      // 別のURLが再生中の場合は停止
      if (_currentUrl != url && _player.playing) {
        print('⏹️ Stopping current playback');
        await stop();
      }

      // 区間を保存
      _startFrom = startFrom;
      _durationSeconds = durationSeconds;

      // 新しいURLをセット
      print('📥 Loading audio from URL...');
      _currentUrl = url;
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
      print('▶️ Starting playback...');
      _player.play().catchError((e) {
        print('❌ Play error: $e');
      });

      print('✅ Successfully playing preview');
    } catch (e, stackTrace) {
      print('❌ Error playing preview: $e');
      print('Stack trace: $stackTrace');
      print('Failed URL: $url');

      // ユーザーにもエラーを通知
      rethrow;
    }
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
      print('Paused playback');
    } catch (e) {
      print('Error pausing playback: $e');
    }
  }

  /// 再生を再開
  Future<void> resume() async {
    try {
      await _player.play();
      print('Resumed playback');
    } catch (e) {
      print('Error resuming playback: $e');
    }
  }

  /// 再生を停止
  Future<void> stop() async {
    try {
      _positionSubscription?.cancel();
      _positionSubscription = null;
      _stateSubscription?.cancel();
      _stateSubscription = null;
      _currentUrl = null; // 先にnullにしてループ再開を防ぐ
      _startFrom = Duration.zero;
      _durationSeconds = 15;
      await _player.stop();
      print('Stopped playback');
    } catch (e) {
      print('Error stopping playback: $e');
    }
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
  }
}
