import 'package:flutter/foundation.dart';

import '../models/music_service_type.dart';
import '../models/post_model.dart';
import '../models/profile_snapshot.dart';
import 'listening_history_service.dart';
import 'music_service_manager.dart';
import 'post_service.dart';
import 'spotify_service.dart';

/// top artists / recent choice の集計。
///
/// プロフィール画面と投稿カードの裏面で同じものを出すので、集計はここに一本化
/// している。別々に書くと、片方だけ仕様変更したときに食い違う。
///
/// ## 集計元
///  - Apple Music: 再生履歴の直近 [_appleMusicHistorySize] 件
///  - Spotify / 未連携: 直近 [postWindow] に自分が投稿した曲
///
/// Spotify で再生履歴を使わないのは、一般ユーザーが履歴 API を叩けないため。
/// Development Mode では許可リストの 5 人しか Web API を使えず、Extended Quota
/// Mode は法人かつ 250k MAU が条件で当面申請できない。
class ProfileSnapshotService {
  ProfileSnapshotService._();
  static final ProfileSnapshotService instance = ProfileSnapshotService._();

  /// Apple Music の再生履歴から何件ぶん遡るか。
  static const int appleMusicHistorySize = 100;

  /// 投稿から集計するときに遡る期間。
  static const Duration postWindow = Duration(days: 7);

  /// 何人・何曲まで出すか。
  static const int limit = 3;

  final PostService _postService = PostService();
  final SpotifyService _spotify = SpotifyService();

  /// アーティスト名を多い順に最大 [limit] 件返す。
  ///
  /// [posts] は投稿ベースに落ちたときの材料。呼び出し側が既に持っていれば
  /// 渡す（渡さなければここで取りに行く）。
  Future<List<String>> topArtistNames({
    required String uid,
    List<PostModel>? posts,
  }) async {
    List<String> names = const [];
    try {
      final service = await MusicServiceManager().getSelectedService();
      if (service == MusicServiceType.appleMusic) {
        names = await ListeningHistoryService.instance
            .recentArtistNames(limit: appleMusicHistorySize);
      }
    } catch (e) {
      if (kDebugMode) print('ProfileSnapshot: history failed: $e');
    }

    if (names.isEmpty) {
      final source = posts ?? await _recentPosts(uid);
      names = artistNamesFromPosts(source);
    }
    return rankByCount(names);
  }

  /// 直近 [postWindow] に投稿した曲のアーティスト名（重複はそのまま）。
  static List<String> artistNamesFromPosts(List<PostModel> posts) {
    final since = DateTime.now().subtract(postWindow);
    return [
      for (final p in posts)
        if (p.createdAt.isAfter(since) && p.track.artistName.trim().isNotEmpty)
          p.track.artistName.trim(),
    ];
  }

  /// 出現回数の多い順に上位 [limit] 件。
  /// 同数のときは先に出てきた（＝新しい）方を優先する。
  static List<String> rankByCount(List<String> names) {
    final counts = <String, int>{};
    final firstSeen = <String, int>{};
    for (var i = 0; i < names.length; i++) {
      final name = names[i];
      counts[name] = (counts[name] ?? 0) + 1;
      firstSeen.putIfAbsent(name, () => i);
    }
    final ranked = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        if (byCount != 0) return byCount;
        return firstSeen[a]!.compareTo(firstSeen[b]!);
      });
    return ranked.take(limit).toList();
  }

  /// 投稿カードに焼き込むスナップショットを作る。
  ///
  /// アーティスト画像もここで解決しておく。カードを見るたびに Spotify を
  /// 叩くとタイムラインが重くなるため。取れなければ null のままにして、
  /// 表示側でプレースホルダに落とす。
  Future<ProfileSnapshot> build({
    required String uid,
    List<PostModel>? posts,
  }) async {
    try {
      final source = posts ?? await _recentPosts(uid);
      final names = await topArtistNames(uid: uid, posts: source);

      final artists = <SnapshotArtist>[];
      for (final name in names) {
        artists.add(SnapshotArtist(
          name: name,
          imageUrl: await _artistImage(name, source),
        ));
      }

      return ProfileSnapshot(
        topArtists: artists,
        recentTracks: [
          for (final p in source.take(limit))
            SnapshotTrack(
              trackName: p.track.trackName,
              artistName: p.track.artistName,
              albumImageUrl: p.track.albumImageUrl,
            ),
        ],
      );
    } catch (e) {
      if (kDebugMode) print('ProfileSnapshot.build error: $e');
      return ProfileSnapshot.empty;
    }
  }

  /// アーティスト画像。投稿に Spotify の ID が入っていればそちらを優先する
  /// （同名アーティスト対策）。
  Future<String?> _artistImage(String name, List<PostModel> posts) async {
    try {
      for (final p in posts) {
        if (p.track.artistName.trim() != name) continue;
        final id = p.track.spotifyArtistId;
        if (id != null && id.isNotEmpty) {
          return await _spotify.getArtistImageUrlById(id);
        }
      }
      return await _spotify.getArtistImageUrl(name);
    } catch (_) {
      return null;
    }
  }

  Future<List<PostModel>> _recentPosts(String uid) async {
    try {
      final result = await _postService.getPostsByUserIdPaged(uid, limit: 60);
      return result.posts;
    } catch (e) {
      if (kDebugMode) print('ProfileSnapshot: posts failed: $e');
      return const [];
    }
  }
}
