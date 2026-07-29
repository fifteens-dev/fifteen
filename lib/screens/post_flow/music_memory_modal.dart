import 'dart:math' as math;
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/profile_fonts.dart';
import '../../models/post_model.dart';
import '../../models/track_model.dart';
import '../../models/user_model.dart';
import '../../services/apple_music_service.dart';
import '../../services/audio_player_service.dart';
import '../../services/itunes_search_service.dart';
import '../../services/music_service_manager.dart';
import '../../services/now_playing_service.dart';
import '../../services/playback_history_service.dart';
import '../../services/user_service.dart';
import '../../utils/color_extractor.dart';
import '../../widgets/post_card.dart';
import '../post_photo_selection_screen.dart';

/// アルバムアートから抽出したグラデーション色の**プロセス寿命**キャッシュ。
///
/// 投稿ボタンを押したときに 1 度だけ抽出 → 以降どのモーダル open からも即座に
/// 同じ色を使い回す。モーダルの再オープンや deck の再構築で消えない。
///
/// - [get] : 同期取得。無ければ null
/// - [ensureAll] : 与えられた全 track の色抽出を並列で開始し、全部完了するまで await
class _DeckColorCache {
  static final Map<String, (Color, Color)> _cache = {};
  static final Map<String, Future<void>> _inflight = {};

  static (Color, Color)? get(String trackId) => _cache[trackId];

  static Future<void> _ensureOne(TrackModel track) {
    final id = track.trackId;
    if (_cache.containsKey(id)) return Future.value();
    final inflight = _inflight[id];
    if (inflight != null) return inflight;
    if (track.albumImageUrl.isEmpty) return Future.value();

    final f = () async {
      try {
        final c = await ColorExtractor.extractGradientColors(
          track.albumImageUrl,
        );
        _cache[id] = c;
      } catch (_) {
        // 抽出失敗はキャッシュに残さず、PostCard 側 fallback に委ねる
      } finally {
        _inflight.remove(id);
      }
    }();
    _inflight[id] = f;
    return f;
  }

  /// 与えられた全 track の色抽出を並列で開始し、全部完了するまで await。
  /// すでに全部キャッシュ済みなら 1 マイクロタスクで解決。
  static Future<void> ensureAll(Iterable<TrackModel> tracks) {
    return Future.wait(tracks.map(_ensureOne));
  }
}

/// 「今日のMusic Memory」投稿フローモーダル（Apple Music ユーザー向け）。
///
/// - タイトル「今日のMusic Memory」＋サブタイトル（Now Playing / ○時間前）。
/// - カードは中央スナップの横スクロール・カルーセル（[_CardCarousel]）。中央に
///   来るたびハプティック。中央のカードが選択対象。
/// - 初回投稿（その日まだ未投稿）: 中央カードが緩く横揺れ＋「←左スワイプで曲を変更」
///   ＋直下に「この曲で続ける」。次回以降: 揺れ無し・文言無しでボタンのみ中央。
/// - 「この曲で続ける」で PostPhotoSelectionScreen（写真フロー）へ。
///
/// ※ Spotify ユーザーはこのモーダルではなく VibeStoryPostSheet（お題非表示）から
///   楽曲選択し、同じ写真フローへ合流する（home_screen 側で分岐）。
class MusicMemoryModal extends StatefulWidget {
  /// 表示するトラック。null の場合は内部で MusicServiceManager から
  /// 最近再生履歴を取得する。
  final List<TrackModel>? tracks;

  const MusicMemoryModal({super.key, this.tracks});

  static Future<void> open(
    BuildContext context, {
    List<TrackModel>? tracks,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => MusicMemoryModal(tracks: tracks),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<MusicMemoryModal> createState() => _MusicMemoryModalState();
}

class _MusicMemoryModalState extends State<MusicMemoryModal> {
  final MusicServiceManager _music = MusicServiceManager();
  final UserService _userService = UserService();
  final AudioPlayerService _audioService = AudioPlayerService();
  List<TrackModel> _tracks = const [];
  bool _loading = true;
  // 色抽出まで含めてカード描画可能かどうか。
  bool _colorsReady = false;

  // 現在中央にあるカードの index（サブタイトル・確定対象）。
  int _centerIndex = 0;

  // デッキの表示モード（下部 UI 切替用）。
  _DeckMode _deckMode = _DeckMode.single;

  // カード内 PostCard 描画用のユーザー情報 (プロフィール表示・楽観 UI 用)
  UserModel? _me;

  @override
  void initState() {
    super.initState();
    _load(widget.tracks);
    _loadMe();
  }

  /// 元リストを決めて反映する。
  /// 表示の主データは **Web API（最近再生）**。日本語タイトル・https アート・
  /// プレビューURL・ストリーミング曲まで正しく揃うため、これを一覧の中心にする。
  /// 端末ライブラリ履歴は表示には使わず、[_applyTracks] 内でタイムスタンプ付与にだけ使う
  /// （MusicKit のライブラリ曲はタイトルがローマ字・アートが musicKit:// スキームで
  /// Flutter 表示に使えないため）。
  Future<void> _load(List<TrackModel>? provided) async {
    try {
      final base = (provided != null && provided.isNotEmpty)
          ? provided
          : await _music.getRecentlyPlayedTracks(limit: 15);
      if (!mounted) return;
      await _applyTracks(base);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _colorsReady = true;
        });
      }
    }
  }

  /// 表示リストを構築して反映する。並びは:
  ///  1. 今 Apple Music で「再生中」の曲（先頭固定・完璧一致）。
  ///  2. アプリ起動時からの**手動再生履歴**（新しい順・埋め込みアート付き）。
  ///     購入曲以外・ローカル曲も拾え、正しいジャケットで表示できる。
  ///  3. Web API の最近再生のうち、1・2 と被らないもの（新しい順）。
  Future<void> _applyTracks(List<TrackModel> tracks) async {
    final npTrack = await _resolveNowPlayingFront(tracks);

    // 2) 手動履歴（新しい順）。再生中の曲は先頭に出すのでここでは除外。
    final history = PlaybackHistoryService().recentTracks();
    final historyFiltered = <TrackModel>[
      for (final h in history)
        if (npTrack == null ||
            !(_exactTitle(h.trackName, npTrack.trackName) &&
                _exactTitle(h.artistName, npTrack.artistName)))
          h,
    ];

    // 3) Web API のうち、再生中とも手動履歴とも被らない曲だけを後ろに。
    bool inFront(TrackModel t) {
      if (npTrack != null &&
          _exactTitle(t.trackName, npTrack.trackName) &&
          _exactTitle(t.artistName, npTrack.artistName)) {
        return true;
      }
      return historyFiltered
          .any((h) => _sameSong(t.trackName, t.artistName, h.trackName, h.artistName));
    }

    final webRest = tracks.where((t) => !inFront(t)).toList();
    // Web 分は端末ライブラリ履歴の時刻を照合して「○分前」ラベルを付ける。
    final recents =
        await NowPlayingService().getDeviceRecentlyPlayed(limit: 50);
    final webAnnotated = webRest.map((t) {
      for (final r in recents) {
        if (_sameSong(t.trackName, t.artistName, r.title, r.artist)) {
          return t.copyWith(playedAt: r.playedAt);
        }
      }
      return t;
    }).toList();

    // 先頭カード: 再生中があればそれ。無ければ手動履歴の先頭を「繰り上げ」て先頭にする。
    // 繰り上げた先頭は、再生中カードと同様にアートを確実化する（保存アートが空/劣化でも
    // storeId からカタログ解決してジャケットを復元する）。
    final rest = <TrackModel>[...historyFiltered, ...webAnnotated];
    TrackModel? front = npTrack != null ? npTrack.copyWith(isNowPlaying: true) : null;
    if (front == null && rest.isNotEmpty) {
      front = await _ensureArt(rest.removeAt(0));
    }

    final ordered = <TrackModel>[
      if (front != null) front,
      ...rest,
    ];

    if (!mounted) return;
    setState(() {
      _tracks = ordered;
      _loading = false;
    });
    await _prepareColors(ordered);
  }

  /// アートが空/未取得の曲を、storeId（数字の trackId）からカタログ解決して補う。
  /// data URI/URL のアートが既にあればそのまま返す。
  Future<TrackModel> _ensureArt(TrackModel t) async {
    if (t.albumImageUrl.isNotEmpty) return t;
    if (RegExp(r'^\d+$').hasMatch(t.trackId)) {
      try {
        final c = await AppleMusicService().getCatalogSongById(t.trackId);
        if (c != null && c.albumImageUrl.isNotEmpty) {
          return t.copyWith(
            albumImageUrl: c.albumImageUrl,
            previewUrl: (t.previewUrl?.isNotEmpty ?? false)
                ? t.previewUrl
                : c.previewUrl,
          );
        }
      } catch (_) {}
    }
    return t;
  }

  /// 今 Apple Music で「再生中」の曲を、先頭表示用の完全な TrackModel として返す。
  /// 再生中でなければ null（古い曲が先頭に出る誤動作を避けるため presence だけでは採用しない）。
  Future<TrackModel?> _resolveNowPlayingFront(List<TrackModel> tracks) async {
    final np = await NowPlayingService().getNowPlaying();
    if (np == null || !np.isPlaying || np.title.isEmpty) return null;

    // 0) カタログID（playbackStoreID）があれば、それで**完全一致**を取得する。
    //    曲名検索と違い、同一バージョン・同一アートワークが確実に得られる（最優先）。
    if (np.storeId != null) {
      final exact = await AppleMusicService().getCatalogSongById(np.storeId!);
      if (exact != null) return exact;
    }

    // 以降のフォールバックは、バージョン表記まで含めた**完全一致のみ**。
    // 「(Original Version)」と「(English Version)」を取り違えないため、
    // 括弧内を除去するあいまい一致（_sameSong）は now playing 解決には使わない。

    // 1) 既存リストに、曲名・アーティストが完全一致する曲があればそれ（アート付き）。
    for (final t in tracks) {
      if (_exactTitle(t.trackName, np.title) &&
          _exactTitle(t.artistName, np.artist)) {
        return t;
      }
    }

    // 2) 曲名でカタログ検索。完全一致 → 版を考慮したベストマッチ、の順で選ぶ。
    try {
      final query = np.artist.isNotEmpty ? '${np.title} ${np.artist}' : np.title;
      final found = await _music.searchTracks(query, limit: 15);
      // 2a) 曲名＋アーティスト完全一致。
      for (final t in found) {
        if (_exactTitle(t.trackName, np.title) &&
            _exactTitle(t.artistName, np.artist)) {
          return t;
        }
      }
      // 2b) 版（original/english/instrumental 等）を考慮したベストマッチ。
      //     ローカル/取り込み曲は表記が違う（英日・略記）ので、逆の版を避けつつ
      //     同じ版・無印版を優先して**正しい版のカタログ曲**を掴む。
      final best = _pickBestCatalogMatch(found, np);
      if (best != null) return best;
    } catch (e) {
      print('[MM nowPlaying] catalog search failed: $e');
    }

    // 3) 適切なカタログ曲が見つからない（ローカル/取り込み曲など）ときは、
    //    別バージョンを掴まず、**端末の埋め込みアート**で完璧一致させる。
    //    プレビューURLは持たせない（誤った版を鳴らさないため _playCentered で再生しない）。
    return TrackModel(
      trackId: 'np_${np.title}_${np.artist}'.hashCode.toString(),
      trackName: np.title,
      artistName: np.artist,
      albumImageUrl: np.artworkDataUri ?? '',
    );
  }

  /// カタログ検索結果から、now playing と**同じ版**の曲を選ぶ。
  /// - アーティストが一致する候補に絞る（検索の関連度順は維持）。
  /// - np が版指定を持つ場合：同じ版 → 無印版 の順で採用。**逆の版は採用しない**。
  /// - np が版指定を持たない場合：無印版を優先、無ければ関連度先頭。
  TrackModel? _pickBestCatalogMatch(
      List<TrackModel> found, NowPlayingInfo np) {
    final cands =
        found.where((t) => _looseArtist(t.artistName, np.artist)).toList();
    if (cands.isEmpty) return null;
    final npVer = _versionKeyword(np.title);
    if (npVer != null) {
      for (final t in cands) {
        if (_versionKeyword(t.trackName) == npVer) return t; // 同じ版
      }
      for (final t in cands) {
        if (_versionKeyword(t.trackName) == null) return t; // 無印版
      }
      return null; // 逆の版しか無い → 掴まない
    }
    for (final t in cands) {
      if (_versionKeyword(t.trackName) == null) return t; // 無印優先
    }
    return cands.first;
  }

  /// 曲名から版キーワードを抽出（無ければ null）。english と original 等の取り違え防止用。
  String? _versionKeyword(String title) {
    final t = title.toLowerCase();
    const kws = [
      'english',
      'original',
      'instrumental',
      'inst.',
      'acoustic',
      'live',
      'remix',
      'karaoke',
      'off vocal',
      'movie',
      'tv size',
      'tv ver',
    ];
    for (final k in kws) {
      if (t.contains(k)) return k == 'inst.' ? 'instrumental' : k;
    }
    return null;
  }

  /// アーティストの緩い一致（大文字小文字・空白・部分一致を吸収）。
  bool _looseArtist(String a, String b) {
    String n(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final na = n(a), nb = n(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb || na.contains(nb) || nb.contains(na);
  }

  /// バージョン表記まで含めた曲名の完全一致（大文字小文字・連続空白のみ吸収）。
  bool _exactTitle(String a, String b) {
    String n(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final na = n(a), nb = n(b);
    return na.isNotEmpty && na == nb;
  }

  /// 曲の同一判定。括弧内注記や "feat."、"- Single/Remaster" 等の差異を吸収する。
  bool _sameSong(String t1, String a1, String t2, String a2) {
    String norm(String s) {
      var x = s.toLowerCase();
      x = x.replaceAll(RegExp(r'[\(\[（【].*?[\)\]）】]'), ' '); // 括弧内
      x = x.replaceAll(RegExp(r'\bfeat\.?\b.*$'), ' '); // feat. 以降
      x = x.replaceAll(RegExp(r'\s[-–—]\s.*$'), ' '); // " - Single" 等
      return x.replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    final tt1 = norm(t1), tt2 = norm(t2);
    if (tt1.isEmpty || tt2.isEmpty) return false;
    final titleMatch =
        tt1 == tt2 || tt1.contains(tt2) || tt2.contains(tt1);
    final aa1 = norm(a1), aa2 = norm(a2);
    final artistMatch = aa1.isEmpty ||
        aa2.isEmpty ||
        aa1 == aa2 ||
        aa1.contains(aa2) ||
        aa2.contains(aa1);
    return titleMatch && artistMatch;
  }

  /// 表示前に全 track の色をプロセス寿命キャッシュへ乗せる。
  /// キャッシュに既にあるものは瞬時に返るので、2 回目以降のモーダルオープンは
  /// 実質ゼロレイテンシで deck が出る。
  Future<void> _prepareColors(List<TrackModel> tracks) async {
    await _DeckColorCache.ensureAll(tracks);
    if (!mounted) return;
    setState(() => _colorsReady = true);
  }

  Future<void> _loadMe() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final me = await _userService.getUser(uid);
      if (mounted) setState(() => _me = me);
    } catch (_) {}
  }

  /// 白ボタン「この曲で続ける」→ 以前の投稿フローと同じカメラ画面へ。
  /// PostPhotoSelectionScreen が上下 2 ページの Vertical PageView (カメラ / 写真グリッド) を持ち、
  /// 撮影・写真選択の後 PostCardEditScreen → PostFinalPreviewScreen へ進む。
  ///
  /// カメラ画面左上のくの字ボタンで曲選択に戻れるよう、モーダル自体は
  /// pop せずスタックに残しておく (カメラは fullscreenDialog で上に被さる)。
  void _confirmAndProceed(TrackModel track) {
    // 写真フローへ進む前にプレビュー再生を停止（モーダルはスタックに残るため）。
    _audioService.stop();
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PostPhotoSelectionScreen(
          track: track,
          isMoodPost: true,
        ),
      ),
    );
  }

  /// 中央カードのサブタイトル。再生中は "Now Playing"、24時間以内は "○分前/○時間前"。
  /// 1日以上前は非表示（曲自体はリストに残す。表示だけしない）。
  String _centerSubtitle() {
    if (_tracks.isEmpty) return '';
    final t = _tracks[_centerIndex.clamp(0, _tracks.length - 1)];
    if (t.isNowPlaying) return 'Now Playing';
    final at = t.playedAt;
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inHours >= 24) return ''; // 1日以上前は表示しない
    if (diff.inMinutes < 1) return 'たった今';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    return '${diff.inHours}時間前';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Center(
            child: SizedBox(
              width: 360,
              height: 640,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1B1B).withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // 左上: 閉じる X (Figma: (22, 31), 32×32)
                        Positioned(
                          left: 22,
                          top: 31,
                          width: 32,
                          height: 32,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.of(context).maybePop(),
                            child: Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF2B2B2B),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                CupertinoIcons.xmark,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                        // タイトル (Figma: (99, 37) 175×21)
                        const Positioned(
                          left: 0,
                          right: 0,
                          top: 37,
                          child: Center(
                            child: Text(
                              '今日のMusic Memory',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                fontFamily: kSfProRounded,
                              ),
                            ),
                          ),
                        ),
                        // サブタイトル: Now Playing / ○時間前（データが無ければ非表示）。
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 63,
                          child: Center(
                            child: Text(
                              _centerSubtitle(),
                              style: const TextStyle(
                                color: Color(0xFF9A9A9A),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                fontFamily: kSfProRounded,
                              ),
                            ),
                          ),
                        ),
                        // カード（中央スナップの横スクロール・カルーセル）。
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 92,
                          height: 452,
                          child: (_loading || !_colorsReady)
                              ? const Center(
                                  child: CupertinoActivityIndicator(
                                    color: Colors.white,
                                    radius: 12,
                                  ),
                                )
                              : _tracks.isEmpty
                                  ? const Center(
                                      child: Text(
                                        '最近再生した曲がありません',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                    )
                                  : _CardCarousel(
                                      tracks: _tracks,
                                      audioService: _audioService,
                                      currentUserId: _me?.uid ?? '',
                                      currentUsername: _me?.username ?? '',
                                      currentUserIconUrl:
                                          _me?.profileImageUrl,
                                      onCenterChanged: (i) {
                                        if (_centerIndex != i && mounted) {
                                          setState(() => _centerIndex = i);
                                        }
                                      },
                                      onModeChanged: (m) {
                                        if (_deckMode != m && mounted) {
                                          setState(() => _deckMode = m);
                                        }
                                      },
                                    ),
                        ),
                        // 下部: 扇（fan）中は「←スワイプして曲を変更→」、
                        // 単体/ピックアップ中は「この曲で続ける」ボタン（Figma Component 125/126）。
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 34,
                          child: Center(
                            child: Builder(builder: (_) {
                              final continueBtn = _ContinueButton(
                                onTap: () {
                                  if (_tracks.isEmpty) return;
                                  final i = _centerIndex
                                      .clamp(0, _tracks.length - 1);
                                  _confirmAndProceed(_tracks[i]);
                                },
                              );
                              // fan: スワイプ案内のみ。
                              if (_deckMode == _DeckMode.fan) {
                                return const Text(
                                  '←　スワイプして曲を変更　→',
                                  style: TextStyle(
                                    color: Color(0xFF8D8D8D),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: kSfProRounded,
                                  ),
                                );
                              }
                              // pickup: ボタンのみ（案内は出さない）。
                              if (_deckMode == _DeckMode.pickup) {
                                return continueBtn;
                              }
                              // single: カードとボタンの間に案内を表示。
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    '←　左にスワイプで曲変更',
                                    style: TextStyle(
                                      color: Color(0xFF8D8D8D),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: kSfProRounded,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  continueBtn,
                                ],
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// カード カルーセル（中央スナップ + スナップ毎ハプティック + 初回のみ横揺れ）
// ─────────────────────────────────────────────────────────────

/// デッキの表示モード。
/// single: 1枚目（再生中）を単体表示 / fan: 2枚目以降が右へ扇状 / pickup: 選択カードをリフト。
enum _DeckMode { single, fan, pickup }

/// 1枚のカードの配置（front カード中心からのオフセット・拡大率・回転・不透明度）。
/// 値は Figma Component 123（扇状デッキ）から採取。dx/dy はカード幅 215px 基準の px。
class _Slot {
  final double dx, dy, scale, rotDeg, opacity;
  const _Slot(this.dx, this.dy, this.scale, this.rotDeg, this.opacity);
}

/// Figma 準拠の扇状デッキ + タップでピックアップする選曲カルーセル。
/// - 1枚目（再生中）は単体表示。左スワイプで扇（2枚目以降）へ。
/// - 扇では左右スワイプで先頭曲を変更。先頭カードをタップでピックアップ。
class _CardCarousel extends StatefulWidget {
  final List<TrackModel> tracks;
  final AudioPlayerService audioService;
  final String currentUserId;
  final String currentUsername;
  final String? currentUserIconUrl;

  /// 先頭に来ている曲の index が変わったとき通知（サブタイトル用）。
  final ValueChanged<int> onCenterChanged;

  /// 表示モードが変わったとき通知（下部 UI 切替用）。
  final ValueChanged<_DeckMode> onModeChanged;

  const _CardCarousel({
    required this.tracks,
    required this.audioService,
    required this.currentUserId,
    required this.currentUsername,
    required this.currentUserIconUrl,
    required this.onCenterChanged,
    required this.onModeChanged,
  });

  @override
  State<_CardCarousel> createState() => _CardCarouselState();
}

class _CardCarouselState extends State<_CardCarousel>
    with TickerProviderStateMixin {
  // Figma Component 123 の扇（front=slot0 / 後方へ右に展開）。front 中心基準の px。
  static const List<_Slot> _fan = [
    _Slot(0.0, 0.0, 1.000, -0.07, 1.00),
    _Slot(11.1, 3.3, 0.980, -4.20, 0.95),
    _Slot(35.3, 9.2, 0.949, -5.51, 0.88),
    _Slot(64.8, 14.0, 0.914, -5.49, 0.78),
    _Slot(85.7, 18.8, 0.877, -3.55, 0.65),
    _Slot(101.7, 25.1, 0.876, -1.81, 0.52),
    _Slot(118.8, 24.9, 0.823, -1.48, 0.50),
  ];
  static const int _maxBehind = 6; // 扇に見せる後方カード枚数

  // ピックアップ時（Figma Component 124）
  static const double _pickFrontScale = 1.094; // 前面カード拡大
  static const double _pickFrontDx = 4.2; // 前面カード 右へ(px)
  static const double _pickFrontDy = -7.1; // 前面カード 上へ(px)
  static const double _pickBehindScale = 0.823;
  static const double _pickBehindBaseDx = 84.8; // 後方スタックの基準X(px)
  static const double _pickBehindStep = 5.0; // 後方スタックの重なり間隔(px)
  static const double _pickBehindDy = 25.15;
  static const double _pickBehindOpacity = 0.84;

  late final AnimationController _open; // single(0) ⇄ fan(1)
  late final AnimationController _pick; // fan(0) ⇄ pickup(1)
  late final AnimationController _settle; // ドラッグ離し後の収束アニメ
  late final AnimationController _wobble; // 1枚目の横揺れ（1秒周期）

  _DeckMode _mode = _DeckMode.single;
  int _front = 0; // 先頭に来ている曲の global index（single では 0）

  // 扇モードの指追従ドラッグ量（px）。フレーム毎に反映して連続的にカードを流す。
  double _dragPx = 0;
  double _cardStep = 1; // 1曲送るのに必要な横移動量（=カード幅）。build で更新。

  // 収束アニメ(_settle)の状態。永続リスナーで駆動し、割り込みに強くする。
  double _settleFrom = 0;
  double _settleTo = 0;
  bool _settleCubic = false; // true: easeOutCubic(フリング) / false: easeOut(戻し)
  int? _pendingFront; // 収束完了時に確定する先頭 index（戻しは null）

  final ITunesSearchService _itunes = ITunesSearchService();
  final Map<String, String> _previewCache = {};
  int _playGen = 0;
  static final DateTime _stableTs = DateTime(2026);

  @override
  void initState() {
    super.initState();
    _open = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _pick = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _settle = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 240));
    _open.addListener(() => setState(() {}));
    _pick.addListener(() => setState(() {}));
    // 収束アニメは永続リスナーで駆動（一時リスナーを毎回付け外ししない＝割り込みに強い）。
    _settle.addListener(_onSettleTick);
    _settle.addStatusListener(_onSettleStatus);
    // 1枚目の横揺れ。single のときだけ再描画（他モードでは無駄な rebuild を避ける）。
    _wobble = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(() {
        if (_mode == _DeckMode.single) setState(() {});
      });
    _wobble.repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playFront());
  }

  @override
  void dispose() {
    _open.dispose();
    _pick.dispose();
    _settle.dispose();
    _wobble.dispose();
    widget.audioService.stopIfOwner(this);
    super.dispose();
  }

  int get _n => widget.tracks.length;

  /// 先頭曲のプレビューを再生（single: tracks[0] / fan・pickup: tracks[_front]）。
  Future<void> _playFront() async {
    final gen = ++_playGen;
    if (_n == 0) return;
    final track = widget.tracks[_front.clamp(0, _n - 1)];
    String? url = track.previewUrl;
    if (url == null || url.isEmpty) url = _previewCache[track.trackId];
    if (url == null || url.isEmpty) {
      if (track.isNowPlaying) return; // ローカル再生中曲は別版を鳴らさない
      final r = await _itunes.getPreviewUrlWithArt(
        trackName: track.trackName,
        artistName: track.artistName,
      );
      url = r?['previewUrl'];
      if (url != null && url.isNotEmpty) _previewCache[track.trackId] = url;
    }
    if (!mounted || gen != _playGen || url == null || url.isEmpty) return;
    await widget.audioService.playPreview(url, durationSeconds: 15, owner: this);
  }

  void _setFront(int i) {
    if (_front == i) return;
    _front = i;
    widget.onCenterChanged(i);
    HapticFeedback.selectionClick();
    _playFront();
  }

  void _setMode(_DeckMode m) {
    if (_mode == m) return;
    _mode = m;
    widget.onModeChanged(m);
    // 横揺れは single のときだけ動かす。
    if (m == _DeckMode.single) {
      if (!_wobble.isAnimating) _wobble.repeat();
    } else {
      _wobble.stop();
    }
  }

  // ── 収束アニメ(_settle)の永続ハンドラ ────────────────────
  void _onSettleTick() {
    final t = (_settleCubic ? Curves.easeOutCubic : Curves.easeOut)
        .transform(_settle.value);
    setState(() => _dragPx = _settleFrom + (_settleTo - _settleFrom) * t);
  }

  void _onSettleStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    _dragPx = 0;
    final t = _pendingFront;
    _pendingFront = null;
    if (t != null && t != _front) {
      _front = t;
      widget.onCenterChanged(t);
      HapticFeedback.selectionClick();
      _playFront();
    }
    if (mounted) setState(() {});
  }

  // ── ジェスチャ ──────────────────────────────────────────
  void _onDragStart(DragStartDetails d) {
    if (_mode != _DeckMode.fan || _pick.value != 0) return;
    // フリング収束中に再スワイプ: 見た目位置(frontPos)へ _front を追従させてから
    // 続きのドラッグに入る。これで高速2連スワイプでも継ぎ目が生じない。
    if (_settle.isAnimating) {
      _settle.stop();
      _pendingFront = null;
      final frontPos = _front - _dragPx / _cardStep;
      final nf = frontPos.round().clamp(1, _n - 1);
      _dragPx = (nf - frontPos) * _cardStep; // frontPos を保ったまま _front を更新
      if (nf != _front) {
        _front = nf;
        widget.onCenterChanged(nf);
        _playFront();
      }
    }
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // 扇モードのみ指追従。指の移動量をそのまま _dragPx に反映（カードが一緒に流れる）。
    if (_mode != _DeckMode.fan || _pick.value != 0) return;
    setState(() {
      _dragPx += d.delta.dx;
      // 端でのオーバースクロール抑制。frontPos を [1, N-1] に概ね収める。
      // _dragPx>0 は右ドラッグ（前へ/single へ）、<0 は左ドラッグ（次へ）。
      final leftLimit = (_front - (_n - 1)) * _cardStep; // 最左（これ以上左に送れない）
      final rightLimit = _front > 1 ? (_front - 1) * _cardStep : _cardStep * 0.55;
      _dragPx = _dragPx.clamp(leftLimit, rightLimit);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    const threshold = 300.0;

    if (_mode == _DeckMode.pickup) {
      _pick.reverse();
      _setMode(_DeckMode.fan);
      return;
    }

    if (_mode == _DeckMode.single) {
      // 1枚目から左スワイプ → 扇を開く。
      if (v <= -threshold && _n > 1) {
        _setMode(_DeckMode.fan);
        _setFront(1);
        _open.forward();
      }
      return;
    }

    // 扇モード: ドラッグ量/速度でコミット判定。
    // 速い（＝高|velocity|）ほど何枚も送る。ゆっくりは 1 枚。
    final prog = -_dragPx / _cardStep; // + = 左に送った量（次へ）
    int cardsFor(double vel) =>
        vel.abs() < 900 ? 1 : (vel.abs() / 900).round().clamp(1, 8);

    if (v <= -threshold || prog > 0.32) {
      // 左スワイプ = 次へ（速いほど複数枚）。
      final n = v <= -threshold ? cardsFor(v) : 1;
      final target = (_front + n).clamp(1, _n - 1);
      if (target != _front) {
        _flingTo(target);
      } else {
        _settleDrag(0); // 端でスプリングバック
      }
    } else if (v >= threshold || prog < -0.32) {
      // 右スワイプ = 前へ / 先頭なら single へ。
      if (_front > 1) {
        final n = v >= threshold ? cardsFor(v) : 1;
        final target = (_front - n).clamp(1, _n - 1);
        _flingTo(target);
      } else {
        _dragPx = 0;
        _open.reverse();
        _setMode(_DeckMode.single);
        _setFront(0);
      }
    } else {
      _settleDrag(0); // スプリングバック
    }
  }

  /// _dragPx を [target] まで収束（先頭は変えない＝スプリングバック用）。
  void _settleDrag(double target) {
    _settleFrom = _dragPx;
    _settleTo = target;
    _settleCubic = false;
    _pendingFront = null;
    _settle
      ..stop()
      ..duration = const Duration(milliseconds: 240)
      ..forward(from: 0);
  }

  /// 先頭を [target] まで一気に送る（複数枚フリング対応）。
  /// frontPos が target に着くよう _dragPx をアニメし、完了後に _front を確定。
  void _flingTo(int target) {
    final n = (target - _front).abs();
    _settleFrom = _dragPx;
    _settleTo = (_front - target) * _cardStep; // frontPos → target
    _settleCubic = true;
    _pendingFront = target;
    _settle
      ..stop()
      ..duration = Duration(milliseconds: (240 + (n - 1) * 80).clamp(240, 640))
      ..forward(from: 0);
  }

  void _onFrontTap() {
    if (_mode == _DeckMode.fan) {
      _setMode(_DeckMode.pickup);
      _pick.forward();
    } else if (_mode == _DeckMode.pickup) {
      _pick.reverse();
      _setMode(_DeckMode.fan);
    }
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// 連続スロット so（0=前面, 1..=後方, 負=左へ退場中）に対する配置を返す。
  /// dx/dy は Figma(215px)基準の px。整数 so では扇テーブル [_fan] に一致する。
  (double, double, double, double, double) _slotT(double so) {
    if (so <= -1 || so > _maxBehind + 0.001) return (0, 0, 1, 0, 0);
    double lp(double a, double b, double t) => a + (b - a) * t;
    if (so < 0) {
      // 前面(so=0) ⇄ 左へ退場(so=-1)。退場は左へ1カード分・少し上・縮小・回転・透明。
      final t = so + 1; // 0(退場)→1(前面)
      return (
        lp(-215, 0, t),
        lp(-24, 0, t),
        lp(0.9, _fan[0].scale, t),
        lp(7, _fan[0].rotDeg, t),
        lp(0, 1, t),
      );
    }
    final i0 = so.floor().clamp(0, _maxBehind);
    final i1 = (i0 + 1).clamp(0, _maxBehind);
    final t = so - i0;
    final a = _fan[i0], b = _fan[i1];
    return (
      lp(a.dx, b.dx, t),
      lp(a.dy, b.dy, t),
      lp(a.scale, b.scale, t),
      lp(a.rotDeg, b.rotDeg, t),
      lp(a.opacity, b.opacity, t),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final area = Size(c.maxWidth, c.maxHeight);
        // 前面カードの基準サイズ（363:645 を保持し、扇が収まる幅に制限）。
        // 全体的に大きく見せるため、高さいっぱい＋幅上限を広めに取る。
        double baseH = area.height - 12;
        double baseW = baseH * 363 / 645;
        if (baseW > area.width * 0.74) {
          baseW = area.width * 0.74;
          baseH = baseW * 645 / 363;
        }
        final k = baseW / 215.0; // Figma(215px) → 実寸 変換係数
        _cardStep = baseW; // 1曲送るのに必要な横移動量（指追従 1:1）。
        final open = _open.value;
        final pick = _pick.value;

        // 前面カード中心。single=中央、fan=やや左（扇を右に展開）。
        final frontCx = _lerp(area.width / 2, area.width * 0.34, open) +
            pick * _pickFrontDx * k;
        final frontCy = area.height * 0.49 + pick * _pickFrontDy * k;

        // 指追従ドラッグ量を連続的な先頭位置に反映（扇モードのみ）。
        final drag = (_mode == _DeckMode.fan && pick == 0) ? _dragPx : 0.0;
        final frontPos = _front - drag / _cardStep;

        final children = <Widget>[];

        // 扇カード群を back→front 順（so 大きい＝奥から）に積む。
        // 高速フリングで複数枚が流れて見えるよう、描画は _front ではなく
        // 連続位置 frontPos を基準にする（可視ウィンドウが frontPos に追従）。
        final anchor = frontPos.round();
        for (int g = anchor + _maxBehind; g >= anchor - 1; g--) {
          if (g < 1 || g >= _n) continue; // 扇は 2枚目以降（index 1..N-1）
          final so = g - frontPos;
          var (dxF, dyF, sc, rot, op) = _slotT(so);
          if (op <= 0.004) continue;
          double dx = dxF * k, dy = dyF * k;

          // single→fan: 展開(open)で slot0 から広がる。open=1 で素通し。
          if (open < 1) {
            dx *= open;
            dy *= open;
            sc = _lerp(1.0, sc, open);
            rot *= open;
            if (g != _front) op *= open;
          }

          // fan→pickup: 前面は拡大・僅かに上、後方は右の密集スタックへ。
          final slot = so.round();
          double blur = 0;
          if (pick > 0) {
            if (slot == 0) {
              dx = _lerp(dx, _pickFrontDx * k, pick);
              dy = _lerp(dy, _pickFrontDy * k, pick);
              sc = _lerp(sc, _pickFrontScale, pick);
              rot = _lerp(rot, _fan[0].rotDeg, pick);
            } else {
              final pdx =
                  (_pickBehindBaseDx + (slot - 1) * _pickBehindStep) * k;
              dx = _lerp(dx, pdx, pick);
              dy = _lerp(dy, _pickBehindDy * k, pick);
              sc = _lerp(sc, _pickBehindScale, pick);
              rot = _lerp(rot, 0, pick);
              op = _lerp(op, _pickBehindOpacity, pick);
              blur = pick; // 0→1px
            }
          }

          final isFront = slot == 0;
          children.add(_positionedCard(
            track: widget.tracks[g],
            baseW: baseW,
            baseH: baseH,
            centerX: frontCx + dx,
            centerY: frontCy + dy,
            scale: sc,
            rotDeg: rot,
            opacity: op,
            blurSigma: blur,
            onTap: (isFront && _mode != _DeckMode.single) ? _onFrontTap : null,
          ));
        }

        // 1枚目（再生中 tracks[0]）: single で中央、左スワイプで左へ退場。
        if (open < 1 && _n > 0) {
          final npX =
              _lerp(area.width / 2, area.width / 2 - area.width * 0.85, open);
          // 横揺れ（右・左・右）を1秒周期で。single のときだけ適用。
          // 包絡線 sin(πx) × 揺れ sin(3πx)。両端で位置も速度も0になり滑らかに
          // 立ち上がり／収まる（急な開始・停止がない）。振れ幅は控えめ。
          double wobbleDx = 0;
          if (_mode == _DeckMode.single) {
            const portion = 0.7; // 前半0.7秒で揺れ、残り0.3秒は静止
            final wt = _wobble.value;
            if (wt < portion) {
              final x = wt / portion; // 0..1
              wobbleDx =
                  6.5 * math.sin(math.pi * x) * math.sin(3 * math.pi * x);
            }
          }
          children.add(_positionedCard(
            track: widget.tracks[0],
            baseW: baseW,
            baseH: baseH,
            centerX: npX + wobbleDx,
            centerY: area.height * 0.49,
            scale: 1.0,
            rotDeg: 0,
            opacity: 1 - open,
            blurSigma: 0,
          ));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: Stack(clipBehavior: Clip.none, children: children),
        );
      },
    );
  }

  Widget _positionedCard({
    required TrackModel track,
    required double baseW,
    required double baseH,
    required double centerX,
    required double centerY,
    required double scale,
    required double rotDeg,
    required double opacity,
    required double blurSigma,
    VoidCallback? onTap,
  }) {
    Widget card = _CardBody(
      track: track,
      audioService: widget.audioService,
      currentUserId: widget.currentUserId,
      currentUsername: widget.currentUsername,
      currentUserIconUrl: widget.currentUserIconUrl,
      stableTs: _stableTs,
      maxWidth: baseW,
      maxHeight: baseH,
    );
    if (blurSigma > 0.01) {
      card = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: card,
      );
    }
    if (onTap != null) {
      card = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      );
    }
    return Positioned(
      left: centerX - baseW / 2,
      top: centerY - baseH / 2,
      width: baseW,
      height: baseH,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..scale(scale)
            ..rotateZ(rotDeg * math.pi / 180),
          child: Center(child: card),
        ),
      ),
    );
  }
}

/// カード 1 枚（既存 [PostCard] を表面のみでレンダリングし、利用可能領域に
/// アスペクト比 363:645 を保って収める）。色は [_DeckColorCache] から同期取得。
class _CardBody extends StatelessWidget {
  final TrackModel track;
  final AudioPlayerService audioService;
  final String currentUserId;
  final String currentUsername;
  final String? currentUserIconUrl;
  final DateTime stableTs;
  final double maxWidth;
  final double maxHeight;

  const _CardBody({
    required this.track,
    required this.audioService,
    required this.currentUserId,
    required this.currentUsername,
    required this.currentUserIconUrl,
    required this.stableTs,
    required this.maxWidth,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    const nativeW = 363.0;
    const nativeH = 645.0;
    // 影ぶんの余白を残して高さ基準でフィット、幅超過時は幅基準。
    // 束（覗き）表示ではカードがスロット幅をほぼ使い切る必要があるため、
    // 左右マージンは小さめ（8px）にして隣が確実に覗くようにする。
    final availH = (maxHeight - 20).clamp(0.0, double.infinity);
    final availW = (maxWidth - 8).clamp(0.0, double.infinity);
    double cardH = availH;
    double cardW = cardH * nativeW / nativeH;
    if (cardW > availW) {
      cardW = availW;
      cardH = cardW * nativeH / nativeW;
    }

    final colors = _DeckColorCache.get(track.trackId);
    final post = PostModel(
      postId: '__deck_preview_${track.trackId}__',
      userId: currentUserId.isNotEmpty ? currentUserId : '__preview__',
      username: currentUsername.isNotEmpty ? currentUsername : 'ユーザー',
      userIconUrl: currentUserIconUrl,
      track: track,
      createdAt: stableTs,
      updatedAt: stableTs,
    );

    return SizedBox(
      width: cardW,
      height: cardH,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 30,
              offset: const Offset(0, 20),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 80,
              offset: const Offset(0, 50),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: nativeW,
              height: nativeH,
              child: IgnorePointer(
                child: PostCard(
                  key: ValueKey('deck-preview-${track.trackId}'),
                  post: post,
                  audioService: audioService,
                  showFrontOnly: true,
                  hideReactionCounts: true,
                  hideAudienceBadge: true,
                  disableInteractions: true,
                  backSideEnabled: false,
                  currentUserId: currentUserId,
                  currentUserIconUrl: currentUserIconUrl,
                  preExtractedGradientStart: colors?.$1,
                  preExtractedGradientEnd: colors?.$2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 白ピル「この曲で続ける」ボタン（既存 UI を踏襲: 258×42・角丸36・グレー文字）。
class _ContinueButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ContinueButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 258,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(36),
        ),
        alignment: Alignment.center,
        child: const Text(
          'この曲で続ける',
          style: TextStyle(
            color: Color(0xFF8D8D8D),
            fontSize: 15,
            fontWeight: FontWeight.w500,
            fontFamily: kSfProRounded,
          ),
        ),
      ),
    );
  }
}
