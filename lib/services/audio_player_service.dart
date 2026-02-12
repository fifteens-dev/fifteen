import 'dart:async';
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
  AudioPlayerService._internal();

  AudioPlayer? _audioPlayer;
  String? _currentUrl;
  StreamSubscription<Duration>? _positionSubscription;

  /// AudioPlayerのインスタンスを取得（必要に応じて作成）
  AudioPlayer get _player {
    _audioPlayer ??= AudioPlayer();
    return _audioPlayer!;
  }

  /// 15秒ループ監視を開始
  void _startLoopMonitor() {
    _positionSubscription?.cancel();
    _positionSubscription = _player.positionStream.listen((position) {
      if (position >= _previewDuration && _player.playing) {
        _player.seek(Duration.zero);
      }
    });
  }

  /// プレビューURLから音楽を再生（冒頭15秒ループ）
  Future<void> playPreview(String url) async {
    try {
      print('🎵 Attempting to play: $url');

      // URLの妥当性チェック
      if (url.isEmpty) {
        print('❌ Empty URL provided');
        return;
      }

      // 既に同じURLが再生中の場合は何もしない
      if (_currentUrl == url && _player.playing) {
        print('⏭️ Already playing this URL');
        return;
      }

      // 別のURLが再生中の場合は停止
      if (_currentUrl != url && _player.playing) {
        print('⏹️ Stopping current playback');
        await stop();
      }

      // 新しいURLをセット
      print('📥 Loading audio from URL...');
      _currentUrl = url;
      await _player.setUrl(url);

      // ループモードはoff（手動で15秒ループを制御）
      await _player.setLoopMode(LoopMode.off);

      // 15秒ループ監視を開始
      _startLoopMonitor();

      // 再生開始
      print('▶️ Starting playback...');
      await _player.play();

      print('✅ Successfully playing preview');
    } catch (e, stackTrace) {
      print('❌ Error playing preview: $e');
      print('Stack trace: $stackTrace');
      print('Failed URL: $url');

      // ユーザーにもエラーを通知
      rethrow;
    }
  }

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
      await _player.stop();
      _currentUrl = null;
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

  /// プレビューの長さ（常に15秒）
  Duration get previewDuration => _previewDuration;

  /// プレイヤーの状態ストリーム
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// 再生位置のストリーム（15秒でキャップ）
  Stream<Duration> get positionStream =>
      _player.positionStream.map((pos) => pos > _previewDuration ? _previewDuration : pos);

  /// 楽曲の長さのストリーム（常に15秒を返す）
  Stream<Duration?> get durationStream =>
      _player.durationStream.map((_) => _previewDuration);

  /// 現在の楽曲の長さ（常に15秒）
  Duration? get duration => _previewDuration;

  /// 現在の再生位置
  Duration get position {
    final pos = _player.position;
    return pos > _previewDuration ? _previewDuration : pos;
  }

  /// リソースを解放
  Future<void> dispose() async {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    await _audioPlayer?.dispose();
    _audioPlayer = null;
    _currentUrl = null;
  }
}
