import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track_model.dart';
import '../models/music_service_type.dart';
import 'spotify_service.dart';
import 'spotify_auth_service.dart';
import 'apple_music_service.dart';

/// 音楽サービスの統一管理クラス
class MusicServiceManager {
  static final MusicServiceManager _instance = MusicServiceManager._internal();
  factory MusicServiceManager() => _instance;
  MusicServiceManager._internal();

  final SpotifyService _spotifyService = SpotifyService();
  final SpotifyAuthService _spotifyAuthService = SpotifyAuthService();
  final AppleMusicService _appleMusicService = AppleMusicService();

  static const String _selectedServiceKey = 'selected_music_service';

  MusicServiceType? _selectedService;

  /// 選択されている音楽サービスを取得
  Future<MusicServiceType> getSelectedService() async {
    if (_selectedService != null) {
      return _selectedService!;
    }

    final prefs = await SharedPreferences.getInstance();
    final serviceString = prefs.getString(_selectedServiceKey);

    if (serviceString == null) {
      _selectedService = MusicServiceType.none;
    } else {
      _selectedService = MusicServiceType.values.firstWhere(
        (e) => e.toString() == serviceString,
        orElse: () => MusicServiceType.none,
      );
    }

    return _selectedService!;
  }

  /// 音楽サービスを選択
  Future<void> setSelectedService(MusicServiceType service) async {
    _selectedService = service;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedServiceKey, service.toString());
    await syncSelectedServiceToProfile(service);
  }

  /// 「このユーザーは既にスタンプ済み」を端末に覚えておくキー。
  /// 値は uid。アカウントを切り替えたら一致しなくなるので再スタンプされる。
  static const String _stampedUidKey = 'music_service_stamped_uid';

  /// 選択中サービスを `users/{uid}` に「連携スタンプ」として刻む。
  ///
  /// 端末ローカル(SharedPreferences)にしか無い選択を Firestore にも残し、
  /// 管理者パネルが**確実に**利用サービスを追えるようにする。
  ///
  /// 記録する項目:
  /// - `musicService`            現在の連携先（appleMusic / spotify / none）
  /// - `musicServiceUpdatedAt`   最後にスタンプした時刻
  /// - `musicServiceFirst(At)`   最初に記録した連携先とその時刻
  /// - `musicServicePrevious`    直前の連携先（乗り換えたときだけ）
  /// - `musicServiceChangedAt`   直近の乗り換え時刻
  /// - `musicServiceSwitchCount` 乗り換え回数
  /// - `musicServiceHistory`     `{service, at}` の履歴
  ///
  /// # 呼ばれ方と負荷
  /// - **連携操作時**（[setSelectedService] 経由で [service] 付き）: 必ず刻む。
  /// - **アプリ起動時**（引数なし）: そのユーザーを**まだ一度も刻んでいないときだけ**
  ///   実行する。一度刻めば端末に記録が残り、以降の起動では Firestore に
  ///   一切アクセスしない。既存ユーザーの取りこぼしを埋め終わったあとは
  ///   実質「連携操作時のみ」に収束する（切り替え作業も再リリースも不要）。
  ///
  /// 失敗は無視する（集計用のメタデータであり、機能には影響しないため）。
  Future<void> syncSelectedServiceToProfile([MusicServiceType? service]) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // 引数ありは連携操作、無しは起動時のバックフィル。
    final isExplicit = service != null;
    final prefs = await SharedPreferences.getInstance();
    if (!isExplicit && prefs.getString(_stampedUidKey) == uid) return;

    final s = service ?? await getSelectedService();
    final key = s.storageKey;

    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await ref.get();
      final previous = snap.data()?['musicService'] as String?;

      if (previous == key) {
        // 変化なし。最終確認時刻だけ更新する。
        await ref.set({
          'musicServiceUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        final updates = <String, dynamic>{
          'musicService': key,
          'musicServiceUpdatedAt': FieldValue.serverTimestamp(),
          // arrayUnion の中では serverTimestamp が使えないのでクライアント時刻。
          'musicServiceHistory': FieldValue.arrayUnion([
            {'service': key, 'at': Timestamp.now()}
          ]),
        };
        if (previous == null) {
          // 初回スタンプ。乗り換えではないので previous / changedAt は付けない。
          updates['musicServiceFirst'] = key;
          updates['musicServiceFirstAt'] = FieldValue.serverTimestamp();
        } else {
          updates['musicServicePrevious'] = previous;
          updates['musicServiceChangedAt'] = FieldValue.serverTimestamp();
          updates['musicServiceSwitchCount'] = FieldValue.increment(1);
        }
        await ref.set(updates, SetOptions(merge: true));
      }

      // 成功したときだけ記録する。失敗したら次の起動で再試行される。
      await prefs.setString(_stampedUidKey, uid);
    } catch (_) {}
  }

  /// 選択されているサービスでログイン
  Future<bool> login() async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        return await _spotifyAuthService.login();
      case MusicServiceType.appleMusic:
        return await _appleMusicService.login();
      case MusicServiceType.none:
        return false;
    }
  }

  /// ログアウト
  Future<void> logout() async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        await _spotifyAuthService.logout();
        break;
      case MusicServiceType.appleMusic:
        await _appleMusicService.logout();
        break;
      case MusicServiceType.none:
        break;
    }
  }

  /// 認証状態を確認
  Future<bool> isAuthenticated() async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        return await _spotifyAuthService.isAuthenticated();
      case MusicServiceType.appleMusic:
        return await _appleMusicService.isAuthenticated();
      case MusicServiceType.none:
        return false;
    }
  }

  /// 楽曲を検索
  Future<List<TrackModel>> searchTracks(String query, {int limit = 20}) async {
    final service = await getSelectedService();
    print('🎵 MusicServiceManager.searchTracks: service=$service, query="$query"');

    switch (service) {
      case MusicServiceType.spotify:
        try {
          return await _spotifyService.searchTracks(query, limit: limit);
        } catch (e) {
          print('⚠️ Spotify検索失敗: $e');
          return [];
        }
      case MusicServiceType.appleMusic:
        final results = await _appleMusicService.searchTracks(query, limit: limit);
        if (results.isNotEmpty) return results;
        // Apple Musicで結果が空の場合、Spotifyにフォールバック
        print('⚠️ Apple Music検索失敗 - Spotifyにフォールバック');
        try {
          return await _spotifyService.searchTracks(query, limit: limit);
        } catch (e) {
          print('⚠️ Spotifyフォールバックも失敗: $e');
          return [];
        }
      case MusicServiceType.none:
        try {
          return await _spotifyService.searchTracks(query, limit: limit);
        } catch (e) {
          print('⚠️ Spotify検索失敗: $e');
          return [];
        }
    }
  }

  /// おすすめの楽曲を取得
  /// 全サービス共通で Apple Music Charts API（日本トップチャート）を使用
  // おすすめ取得ソース定義
  // genreId: 29=J-Pop, 17=サウンドトラック(アニメ楽曲に近い), 14=Pop
  static const List<_ChartSource> _chartSources = [
    _ChartSource.japanTop,
    _ChartSource.trendingJapan,
  ];

  Future<List<TrackModel>> getRecommendedTracks({int limit = 50}) async {
    print('🎵 MusicServiceManager.getRecommendedTracks: ランダム選択');

    // ソースをシャッフルして順番に試す
    final sources = List<_ChartSource>.from(_chartSources)..shuffle(Random());

    for (final source in sources) {
      try {
        final tracks = await _fetchChartSource(source, limit: limit);
        if (tracks.isNotEmpty) {
          print('📊 ${source.label}から${tracks.length}曲取得');
          return tracks;
        }
      } catch (e) {
        print('⚠️ ${source.label}取得失敗: $e');
      }
    }

    // 全ソース失敗時の最終フォールバック
    try {
      return await _spotifyService.searchTracks('J-POP 人気', limit: limit);
    } catch (e) {
      print('⚠️ 最終フォールバックも失敗: $e');
      return [];
    }
  }

  Future<List<TrackModel>> _fetchChartSource(_ChartSource source,
      {int limit = 50}) async {
    switch (source) {
      case _ChartSource.japanTop:
        return await _appleMusicService.getTopCharts(limit: limit);
      case _ChartSource.trendingJapan:
        return await _appleMusicService.getHotHitsJapan(limit: limit);
    }
  }

  /// プレイリストから楽曲を取得
  Future<List<TrackModel>> getPlaylistTracks(String playlistId,
      {int limit = 50}) async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        return await _spotifyService.getPlaylistTracks(playlistId,
            limit: limit);
      case MusicServiceType.appleMusic:
        return await _appleMusicService.getPlaylistTracks(playlistId,
            limit: limit);
      case MusicServiceType.none:
        return [];
    }
  }

  /// プレイリスト名で検索してトラックを取得
  Future<List<TrackModel>> searchPlaylistTracks(String playlistName,
      {int limit = 20}) async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        return await _spotifyService.searchPlaylistTracks(playlistName,
            limit: limit);
      case MusicServiceType.appleMusic:
        return await _appleMusicService.searchPlaylistTracks(playlistName,
            limit: limit);
      case MusicServiceType.none:
        return [];
    }
  }

  /// ユーザーの最近再生した楽曲を取得
  Future<List<TrackModel>> getRecentlyPlayedTracks({int limit = 30}) async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        if (await _spotifyAuthService.isAuthenticated()) {
          try {
            return await _spotifyService.getRecentlyPlayedTracks(limit: limit);
          } catch (e) {
            print('⚠️ Spotify最近再生した曲の取得失敗: $e');
            return [];
          }
        }
        return [];
      case MusicServiceType.appleMusic:
        try {
          return await _appleMusicService.getRecentlyPlayedTracks(limit: limit);
        } catch (e) {
          print('⚠️ Apple Music最近再生した曲の取得失敗: $e');
          return [];
        }
      case MusicServiceType.none:
        return [];
    }
  }

  /// ユーザーのお気に入り楽曲を取得
  Future<List<TrackModel>> getSavedTracks({int limit = 50}) async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        // OAuth認証済みの場合のみお気に入り楽曲を取得（フォールバックなし）
        if (await _spotifyAuthService.isAuthenticated()) {
          try {
            return await _spotifyService.getSavedTracks(limit: limit);
          } catch (e) {
            print('⚠️ Spotifyライブラリ取得失敗: $e');
            return [];
          }
        }
        return [];
      case MusicServiceType.appleMusic:
        // ユーザーのライブラリから取得のみ（フォールバックなし）
        try {
          return await _appleMusicService.getSavedTracks(limit: limit);
        } catch (e) {
          print('⚠️ Apple Musicライブラリ取得失敗: $e');
          return [];
        }
      case MusicServiceType.none:
        return [];
    }
  }

  /// 楽曲の歌詞を取得
  /// trackId: トラックID（サービスによって形式が異なる）
  Future<String?> getLyrics(String trackId) async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        // Spotify APIは公式に歌詞APIを提供していない
        // サードパーティAPIやスクレイピングが必要
        print('Spotify歌詞取得は未実装です');
        return null;
      case MusicServiceType.appleMusic:
        return await _appleMusicService.getLyrics(trackId);
      case MusicServiceType.none:
        // デフォルトでApple Musicを試す
        return await _appleMusicService.getLyrics(trackId);
    }
  }
}

enum _ChartSource {
  japanTop,       // 日本チャート（genre指定なし）
  trendingJapan;  // 急上昇プレイリスト

  String get label {
    switch (this) {
      case _ChartSource.japanTop:       return '日本チャート';
      case _ChartSource.trendingJapan:  return '急上昇チャート';
    }
  }
}
