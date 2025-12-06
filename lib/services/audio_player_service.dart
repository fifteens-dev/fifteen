import 'package:just_audio/just_audio.dart';

/// 音楽再生を管理するサービス
class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  AudioPlayer? _audioPlayer;
  String? _currentUrl;

  /// AudioPlayerのインスタンスを取得（必要に応じて作成）
  AudioPlayer get _player {
    _audioPlayer ??= AudioPlayer();
    return _audioPlayer!;
  }

  /// プレビューURLから音楽を再生
  Future<void> playPreview(String url) async {
    try {
      // 既に同じURLが再生中の場合は何もしない
      if (_currentUrl == url && _player.playing) {
        return;
      }

      // 別のURLが再生中の場合は停止
      if (_currentUrl != url && _player.playing) {
        await stop();
      }

      // 新しいURLをセット
      _currentUrl = url;
      await _player.setUrl(url);

      // ループ再生を有効化（プレビューが終わったら最初から再生）
      await _player.setLoopMode(LoopMode.one);

      // 再生開始
      await _player.play();

      print('Playing preview: $url');
    } catch (e) {
      print('Error playing preview: $e');
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
      await _player.stop();
      _currentUrl = null;
      print('Stopped playback');
    } catch (e) {
      print('Error stopping playback: $e');
    }
  }

  /// 現在再生中かどうか
  bool get isPlaying => _player.playing;

  /// 現在一時停止中かどうか
  bool get isPaused => _player.processingState == ProcessingState.ready && !_player.playing;

  /// 現在のURLが指定されたURLかどうか
  bool isPlayingUrl(String url) => _currentUrl == url && _player.playing;

  /// プレイヤーの状態ストリーム
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// リソースを解放
  Future<void> dispose() async {
    await _audioPlayer?.dispose();
    _audioPlayer = null;
    _currentUrl = null;
  }
}
