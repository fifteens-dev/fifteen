import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'web_audio_service.dart';

/// 音楽再生を管理するサービス
class AudioPlayerService {
  AudioPlayer? _audioPlayer;
  String? _currentUrl;
  bool _audioContextUnlocked = false;

  // Web専用のオーディオサービス
  final WebAudioService _webAudioService = WebAudioService();

  /// AudioPlayerのインスタンスを取得（必要に応じて作成）
  AudioPlayer get _player {
    _audioPlayer ??= AudioPlayer();
    return _audioPlayer!;
  }

  /// Web版（特にモバイル）でオーディオコンテキストをアンロック
  Future<void> _unlockAudioContext() async {
    if (!kIsWeb || _audioContextUnlocked) return;

    try {
      // モバイルブラウザ用：無音のデータURLを使用してオーディオコンテキストをアンロック
      // これはユーザーのタップ/クリックイベント内で実行される必要がある
      const silentAudioDataUrl =
          'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=';

      await _player.setVolume(0.0);
      await _player.setUrl(silentAudioDataUrl);
      await _player.play();
      await Future.delayed(const Duration(milliseconds: 50));
      await _player.stop();
      await _player.setVolume(1.0);
      _audioContextUnlocked = true;
      print('Audio context unlocked for web/mobile');
    } catch (e) {
      print('Failed to unlock audio context: $e');
      // 失敗してもアンロック済みとマークして、実際の音声再生を試みる
      _audioContextUnlocked = true;
    }
  }

  /// プレビューURLから音楽を再生
  Future<void> playPreview(String url) async {
    // Web版では専用のWebAudioServiceを使用
    if (kIsWeb) {
      try {
        print('🌐 Using WebAudioService for web platform');
        await _webAudioService.playAudio(url);
        _currentUrl = url;
      } catch (e) {
        print('❌ WebAudioService error: $e');
      }
      return;
    }

    // モバイル/デスクトップアプリではjust_audioを使用
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
    if (kIsWeb) {
      await _webAudioService.pause();
      return;
    }

    try {
      await _player.pause();
      print('Paused playback');
    } catch (e) {
      print('Error pausing playback: $e');
    }
  }

  /// 再生を再開
  Future<void> resume() async {
    if (kIsWeb) {
      await _webAudioService.resume();
      return;
    }

    try {
      await _player.play();
      print('Resumed playback');
    } catch (e) {
      print('Error resuming playback: $e');
    }
  }

  /// 再生を停止
  Future<void> stop() async {
    if (kIsWeb) {
      await _webAudioService.stop();
      _currentUrl = null;
      return;
    }

    try {
      await _player.stop();
      _currentUrl = null;
      print('Stopped playback');
    } catch (e) {
      print('Error stopping playback: $e');
    }
  }

  /// 現在再生中かどうか
  bool get isPlaying {
    if (kIsWeb) return _webAudioService.isPlaying;
    return _player.playing;
  }

  /// 現在一時停止中かどうか
  bool get isPaused {
    if (kIsWeb) return !_webAudioService.isPlaying;
    return _player.processingState == ProcessingState.ready && !_player.playing;
  }

  /// 現在のURLが指定されたURLかどうか
  bool isPlayingUrl(String url) {
    if (kIsWeb) return _webAudioService.isPlayingUrl(url);
    return _currentUrl == url && _player.playing;
  }

  /// プレイヤーの状態ストリーム
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// 再生位置のストリーム
  Stream<Duration> get positionStream => _player.positionStream;

  /// 楽曲の長さのストリーム
  Stream<Duration?> get durationStream => _player.durationStream;

  /// 現在の楽曲の長さ
  Duration? get duration => _player.duration;

  /// 現在の再生位置
  Duration get position => _player.position;

  /// リソースを解放
  Future<void> dispose() async {
    await _audioPlayer?.dispose();
    _audioPlayer = null;
    _currentUrl = null;
  }
}
