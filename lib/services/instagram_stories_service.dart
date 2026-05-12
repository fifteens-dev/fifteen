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

  static Future<bool> share(Uint8List pngBytes, {String? postId}) async {
    try {
      final contentUrl = postId != null && postId.isNotEmpty
          ? 'https://fifteens-39cfe.web.app/post/$postId'
          : 'https://fifteens-39cfe.web.app/';
      final args = <String, dynamic>{
        'imageData': pngBytes,
        'contentURL': contentUrl,
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
