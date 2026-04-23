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

  static Future<bool> share(Uint8List pngBytes) async {
    try {
      await _channel.invokeMethod('shareToStories', {'imageData': pngBytes});
      // source_application にはFacebook App ID（登録済みの場合）またはバンドルIDを指定
      const bundleId = 'com.fifteen.app'; // TODO: Facebook App IDに変更する
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
