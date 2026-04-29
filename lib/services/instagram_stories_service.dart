import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class InstagramStoriesService {
  static const _channel = MethodChannel('com.fifteen.instagram');

  static Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isInstagramAvailable');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> share(
    Uint8List pngBytes, {
    String? postId,
    String? audioUrl,
    int audioStartMs = 0,
    int durationSec = 15,
  }) async {
    try {
      // Instagramリンクスタンプ用HTTPS URL
      // このページが fifteenapp:// を呼び出してアプリを起動する
      const contentUrl = 'https://fifteens-39cfe.web.app/';
      final args = <String, dynamic>{
        'imageData': pngBytes,
        'contentURL': contentUrl,
        if (audioUrl != null && audioUrl.isNotEmpty) 'audioURL': audioUrl,
        'audioStartMs': audioStartMs,
        'durationSec': durationSec,
      };
      await _channel.invokeMethod('shareToStories', args);
      const bundleId = 'com.fifteen.app';
      final uri = Uri.parse('instagram-stories://share?source_application=$bundleId');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
