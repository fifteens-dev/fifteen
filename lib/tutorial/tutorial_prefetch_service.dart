import 'tutorial_album_carousel.dart';
import '../services/spotify_service.dart';
import '../services/itunes_search_service.dart';
import '../services/audio_player_service.dart';

/// チュートリアル固定3曲のアルバムアート・プレビューURLをアプリ起動直後に
/// バックグラウンドで取得し、キャッシュするシングルトンサービス。
///
/// MusicConnectionScreen.initState() で prefetchAll() を呼ぶことで
/// Frame628 カルーセル表示時には取得済みになるよう設計されている。
///
/// - アルバムアート: Spotify
/// - プレビューURL: Spotify (preview_url が空の場合は iTunes にフォールバック)
class TutorialPrefetchService {
  TutorialPrefetchService._();
  static final TutorialPrefetchService instance = TutorialPrefetchService._();

  /// key = '${title}__${artist}'
  final Map<String, String?> artCache = {};
  final Map<String, String?> previewCache = {};

  bool _started = false;

  /// 全3曲を並列でプリフェッチする（2回目以降は何もしない）。
  /// プリフェッチ完了後、初期アクティブカードの音声データを AudioPlayerService に preload する
  /// （setUrlを事前実行することで、playPreview時に即スワップ再生される最速パスに乗る）。
  void prefetchAll() {
    if (_started) return;
    _started = true;
    Future.wait(
      TutorialAlbumCarousel.defaultItems.map(_fetchOne),
      eagerError: false,
    ).then((_) {
      // 初期表示されるアクティブカードの音声を preload
      final initialIdx = TutorialAlbumCarousel.initialPage %
          TutorialAlbumCarousel.defaultItems.length;
      preloadAudio(TutorialAlbumCarousel.defaultItems[initialIdx]);
    }).ignore();
  }

  /// 指定アイテムのプレビュー音声を AudioPlayerService.preload() で setUrl 済み状態にする。
  /// URLがキャッシュ済みであれば即実行、未取得ならまず _fetchOne で取得してから preload。
  Future<void> preloadAudio(TutorialAlbumItem item) async {
    final key = '${item.title}__${item.artist}';
    await ensureReady(key, item);
    final url = previewCache[key];
    if (url != null && url.isNotEmpty) {
      await AudioPlayerService().preload(url);
    }
  }

  /// cacheKey の両キャッシュが揃っていることを保証する（home_screen から使用）
  Future<void> ensureReady(String cacheKey, TutorialAlbumItem item) async {
    if (artCache.containsKey(cacheKey) && previewCache.containsKey(cacheKey)) {
      return;
    }
    await _fetchOne(item);
  }

  // ---- private ----

  Future<void> _fetchOne(TutorialAlbumItem item) async {
    final key = '${item.title}__${item.artist}';
    if (artCache.containsKey(key) && previewCache.containsKey(key)) return;

    // ① Spotify からアートとプレビューURLを取得
    String? artUrl;
    String? previewUrl;
    try {
      final tracks = await SpotifyService().searchTracks(
        '${item.title} ${item.artist}',
        limit: 1,
      );
      if (tracks.isNotEmpty) {
        artUrl = tracks.first.albumImageUrl;
        final sp = tracks.first.previewUrl;
        if (sp != null && sp.isNotEmpty) previewUrl = sp;
      }
    } catch (_) {}

    // ② Spotify のプレビューURLが空の場合は iTunes にフォールバック
    if (previewUrl == null || previewUrl.isEmpty) {
      try {
        final result = await ITunesSearchService().getPreviewUrlWithArt(
          trackName: item.title,
          artistName: item.artist,
        );
        previewUrl = result?['previewUrl'];
      } catch (_) {}
    }

    artCache[key] = artUrl;
    previewCache[key] = previewUrl;
  }
}
