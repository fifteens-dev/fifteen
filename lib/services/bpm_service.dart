import 'package:cloud_functions/cloud_functions.dart';

/// BPM（テンポ）取得・キャッシュサービス
/// Firebase Cloud Function経由でGetSongBPM APIを利用
class BpmService {
  static final BpmService _instance = BpmService._internal();
  factory BpmService() => _instance;
  BpmService._internal();

  final _functions = FirebaseFunctions.instance;

  // trackId → tempo のキャッシュ
  final Map<String, double?> _cache = {};

  // 現在取得中のトラックID（重複リクエスト防止）
  final Set<String> _fetching = {};

  /// BPMを取得（キャッシュ優先）
  Future<double?> getTempo({
    required String trackId,
    String? trackName,
    String? artistName,
  }) async {
    if (_cache.containsKey(trackId)) {
      return _cache[trackId];
    }

    if (_fetching.contains(trackId)) {
      return null;
    }

    if (trackName == null || trackName.isEmpty) {
      return null;
    }

    _fetching.add(trackId);

    try {
      final result = await _functions.httpsCallable('getBpm').call({
        'trackName': trackName,
        'artistName': artistName,
      });

      final tempo = (result.data['tempo'] as num?)?.toDouble();
      _cache[trackId] = tempo;

      if (tempo != null) {
        print('🎵 BPM取得成功: $trackName - ${tempo}BPM');
      } else {
        print('⚠️ BPM取得失敗: $trackName');
      }

      return tempo;
    } catch (e) {
      print('❌ BpmService error: $e');
      _cache[trackId] = null;
      return null;
    } finally {
      _fetching.remove(trackId);
    }
  }

  /// キャッシュをクリア
  void clearCache() {
    _cache.clear();
  }
}
