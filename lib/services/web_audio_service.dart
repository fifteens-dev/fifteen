import 'dart:js' as js;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Web専用のオーディオサービス
/// モバイルブラウザでの再生問題を解決するため、ネイティブHTML5 Audioを使用
class WebAudioService {
  static final WebAudioService _instance = WebAudioService._internal();
  factory WebAudioService() => _instance;
  WebAudioService._internal();

  String? _currentUrl;
  bool _isPlaying = false;

  /// 音楽を再生
  Future<void> playAudio(String url) async {
    if (!kIsWeb) {
      print('❌ WebAudioService is only for web platform');
      return;
    }

    try {
      print('🎵 WebAudioService: Playing $url');
      
      // JavaScriptのaudioHelper.playAudio()を呼び出し
      js.context.callMethod('eval', ['window.audioHelper.playAudio("$url")']);
      
      _currentUrl = url;
      _isPlaying = true;
      
      print('✅ WebAudioService: Play command sent');
    } catch (e) {
      print('❌ WebAudioService: Error playing audio: $e');
      rethrow;
    }
  }

  /// 一時停止
  Future<void> pause() async {
    if (!kIsWeb) return;

    try {
      print('⏸ WebAudioService: Pausing');
      js.context.callMethod('eval', ['window.audioHelper.pauseAudio()']);
      _isPlaying = false;
    } catch (e) {
      print('❌ WebAudioService: Error pausing: $e');
    }
  }

  /// 停止
  Future<void> stop() async {
    if (!kIsWeb) return;

    try {
      print('⏹ WebAudioService: Stopping');
      js.context.callMethod('eval', ['window.audioHelper.stopAudio()']);
      _currentUrl = null;
      _isPlaying = false;
    } catch (e) {
      print('❌ WebAudioService: Error stopping: $e');
    }
  }

  /// 再開
  Future<void> resume() async {
    if (!kIsWeb) return;

    try {
      print('▶️ WebAudioService: Resuming');
      js.context.callMethod('eval', ['window.audioHelper.resumeAudio()']);
      _isPlaying = true;
    } catch (e) {
      print('❌ WebAudioService: Error resuming: $e');
    }
  }

  /// 現在再生中かどうか
  bool get isPlaying => _isPlaying;

  /// 現在のURLが指定されたURLかどうか
  bool isPlayingUrl(String url) => _currentUrl == url && _isPlaying;

  /// 現在のURL
  String? get currentUrl => _currentUrl;
}
