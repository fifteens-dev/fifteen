import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/track_model.dart';
import '../providers/saved_items_provider.dart';
import '../services/artist_service.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/spotify_service.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/profile_widgets.dart';
import 'artist_followers_screen.dart';

/// アーティストプロフィール画面
///
/// iTunes の楽曲一覧をグリッド/リスト表示し、Firestore でフォロー管理する。
class ArtistProfileScreen extends StatefulWidget {
  final String artistName;

  /// 既知の iTunes artistId（省略時は artistName で検索）
  final int? itunesArtistId;

  /// SpotifyアーティストID（あれば画像取得を ID ベースで正確に行う）
  final String? spotifyArtistId;

  const ArtistProfileScreen({
    super.key,
    required this.artistName,
    this.itunesArtistId,
    this.spotifyArtistId,
  });

  @override
  State<ArtistProfileScreen> createState() => _ArtistProfileScreenState();
}

class _ArtistProfileScreenState extends State<ArtistProfileScreen>
    with SingleTickerProviderStateMixin {
  final ArtistService _artistService = ArtistService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  final SpotifyService _spotifyService = SpotifyService();
  final AudioPlayerService _audioService = AudioPlayerService();
  late TabController _tabController;

  List<TrackModel> _tracks = [];
  bool _isLoading = true;
  bool _isFollowing = false;
  int _followerCount = 0;
  String _firestoreArtistId = '';
  String? _playingTrackId;
  String? _artistImageUrl;

  @override
  void initState() {
    super.initState();
    _audioService.stop();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadData();
  }

  @override
  void dispose() {
    _audioService.stop();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(TrackModel track) async {
    if (_playingTrackId == track.trackId) {
      _audioService.stop();
      setState(() => _playingTrackId = null);
      return;
    }
    setState(() => _playingTrackId = track.trackId);

    String? url = track.previewUrl;
    if (url == null || url.isEmpty) {
      url = await _itunesService.getPreviewUrl(
        trackName: track.trackName,
        artistName: track.artistName,
      );
    }
    if (!mounted) return;
    if (url != null && url.isNotEmpty) {
      await _audioService.playPreview(url);
    } else {
      setState(() => _playingTrackId = null);
    }
  }

  Future<void> _loadData() async {
    try {
      int? artistId = widget.itunesArtistId;

      // iTunes artistId 未指定なら名前で検索
      if (artistId == null) {
        final info = await _itunesService.searchArtistInfo(widget.artistName);
        artistId = info?.artistId;
      }

      // Firestore document ID: iTunes artistId があればそれを、なければ名前を正規化
      _firestoreArtistId = artistId?.toString() ??
          widget.artistName
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]'), '_');

      // 楽曲一覧・Firestore情報・Spotifyアーティスト画像を並列取得
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final results = await Future.wait([
        artistId != null
            ? _itunesService.getArtistTracks(artistId, limit: 100)
            : Future.value(<TrackModel>[]),
        _artistService.getArtist(_firestoreArtistId),
        (widget.spotifyArtistId != null && widget.spotifyArtistId!.isNotEmpty)
            ? _spotifyService.getArtistImageUrlById(widget.spotifyArtistId!)
            : _spotifyService.getArtistImageUrl(widget.artistName),
      ]);

      final tracks = results[0] as List<TrackModel>;
      final artistModel = results[1] as dynamic;
      final spotifyImageUrl = results[2] as String?;

      final isFollowing =
          uid != null && (artistModel?.isFollowedBy(uid) ?? false);

      // Spotify画像が取れなければiTunesのアルバムアートで代替
      final imageUrl = (spotifyImageUrl?.isNotEmpty == true)
          ? spotifyImageUrl
          : (tracks.isNotEmpty ? tracks.first.albumImageUrl : null);

      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _followerCount = artistModel?.followerCount ?? 0;
        _isFollowing = isFollowing;
        _artistImageUrl = imageUrl;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    await _loadData();
  }

  Future<void> _toggleSaveTrack(TrackModel track) async {
    HapticFeedback.lightImpact();
    await SavedItemsProvider.toggleTrackWithToast(context, track);
  }

  Future<void> _toggleFollow() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    HapticFeedback.mediumImpact();
    final prev = _isFollowing;
    setState(() {
      _isFollowing = !_isFollowing;
      _followerCount += _isFollowing ? 1 : -1;
    });
    try {
      if (_isFollowing) {
        await _artistService.followArtist(
          userId: uid,
          artistId: _firestoreArtistId,
          artistName: widget.artistName,
        );
      } else {
        await _artistService.unfollowArtist(
          userId: uid,
          artistId: _firestoreArtistId,
        );
      }
      _artistService.invalidateFollowerCountCache(widget.artistName);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFollowing = prev;
          _followerCount += prev ? 1 : -1;
        });
        AppToast.show(context, 'エラーが発生しました');
      }
    }
  }

  // ─── BUILD ───────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  CupertinoSliverRefreshControl(onRefresh: _refresh),
                  SliverToBoxAdapter(child: _buildProfileInfo()),
                  SliverToBoxAdapter(child: _buildFollowButton()),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabBarDelegate(child: _buildTabSelector()),
                  ),
                  ..._buildActiveTabSlivers(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          Center(
            child: Text(
              widget.artistName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfo() {
    final imageUrl = _artistImageUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(27, 30, 27, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.artistName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                width: 65,
                height: 65,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[800],
                ),
                child: ClipOval(
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.person,
                            color: Colors.white54,
                            size: 36,
                          ),
                        )
                      : const Icon(
                          Icons.person,
                          color: Colors.white54,
                          size: 36,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ProfileStatItem(
                  count: '${_tracks.length}', label: 'Tracks'),
              const SizedBox(width: 20),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ArtistFollowersScreen(
                      artistId: _firestoreArtistId,
                      artistName: widget.artistName,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: ProfileStatItem(
                      count: '$_followerCount', label: 'Followers'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFollowButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(21, 0, 21, 16),
      child: GestureDetector(
        onTap: _toggleFollow,
        child: Container(
          height: 30,
          decoration: BoxDecoration(
            color: _isFollowing
                ? Colors.transparent
                : const Color(0xFF0098FE),
            border: _isFollowing
                ? Border.all(color: const Color(0xFF929292))
                : null,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Center(
            child: Text(
              _isFollowing ? 'フォロー中' : 'フォロー',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabSelector() {
    const indicatorWidth = 60.0;
    const indicatorHeight = 2.0;

    return AnimatedBuilder(
      animation: _tabController.animation!,
      builder: (context, _) {
        final t = _tabController.animation!.value.clamp(0.0, 1.0);
        final color0 = Color.lerp(Colors.grey, Colors.white, 1.0 - t)!;
        final color1 = Color.lerp(Colors.grey, Colors.white, t)!;

        return LayoutBuilder(
          builder: (context, constraints) {
            final tabWidth = constraints.maxWidth / 2;
            final indicatorLeft =
                (tabWidth - indicatorWidth) / 2 + t * tabWidth;

            return Stack(
              children: [
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      // グリッドタブ
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _tabController.animateTo(0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(Icons.grid_view,
                                  color: color0, size: 24),
                              const SizedBox(
                                  height: 4 + indicatorHeight),
                            ],
                          ),
                        ),
                      ),
                      // リストタブ（ハンバーガーアイコン）
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _tabController.animateTo(1),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(Icons.menu, color: color1, size: 24),
                              const SizedBox(
                                  height: 4 + indicatorHeight),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: indicatorLeft,
                  child: Container(
                    width: indicatorWidth,
                    height: indicatorHeight,
                    color: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<Widget> _buildActiveTabSlivers() {
    if (_tabController.index == 0) {
      return _buildGridSlivers();
    } else {
      return _buildListSlivers();
    }
  }

  // ── グリッドタブ ──────────────────────────────

  List<Widget> _buildGridSlivers() {
    if (_tracks.isEmpty) {
      return [
        const SliverFillRemaining(
          child: Center(
            child: Text(
              '楽曲が見つかりませんでした',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
        ),
      ];
    }
    return [
      SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 131 / 192,
          crossAxisSpacing: 0,
          mainAxisSpacing: 8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final track = _tracks[index];
            final isPlaying = _playingTrackId == track.trackId;
            return GestureDetector(
              onTap: () => _togglePlay(track),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // アルバムアート（正方形）
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      margin: const EdgeInsets.all(0.5),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (track.albumImageUrl.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: CachedNetworkImage(
                                imageUrl: track.albumImageUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 200,
                                memCacheHeight: 200,
                                errorWidget: (_, __, ___) =>
                                    Container(color: Colors.grey[850]),
                              ),
                            ),
                          if (isPlaying)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Center(
                                child: Icon(Icons.pause,
                                    color: Colors.white, size: 28),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // 曲名
                  Padding(
                    padding: const EdgeInsets.only(left: 6, top: 4),
                    child: Text(
                      track.trackName,
                      style: TextStyle(
                        color: isPlaying
                            ? const Color(0xFF1DB954)
                            : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 保存ボタン
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 2),
                    child: GestureDetector(
                      onTap: () => _toggleSaveTrack(track),
                      child: context.watch<SavedItemsProvider>().isTrackSaved(track.trackId)
                          ? Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 18,
                                  height: 18,
                                  decoration: const BoxDecoration(
                                    color: Colors.lightGreen,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Icon(Icons.check,
                                    size: 13, color: Colors.grey[700]),
                              ],
                            )
                          : const Icon(Icons.add_circle_outline,
                              color: Color(0xFF7A7A7A), size: 18),
                    ),
                  ),
                ],
              ),
            );
          },
          childCount: _tracks.length,
        ),
      ),
    ];
  }

  // ── リストタブ ────────────────────────────────

  List<Widget> _buildListSlivers() {
    if (_tracks.isEmpty) {
      return [
        const SliverFillRemaining(
          child: Center(
            child: Text(
              '楽曲が見つかりませんでした',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
        ),
      ];
    }
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildTrackListItem(_tracks[index]),
          childCount: _tracks.length,
        ),
      ),
    ];
  }

  Widget _buildTrackListItem(TrackModel track) {
    final isPlaying = _playingTrackId == track.trackId;
    return GestureDetector(
      onTap: () => _togglePlay(track),
      child: Container(
        height: 59,
        color: isPlaying ? const Color(0xFF2A2A2A) : const Color(0xFF121212),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                width: 47,
                height: 47,
                child: track.albumImageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: track.albumImageUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey[800],
                          child: const Icon(Icons.album,
                              size: 24, color: Colors.white38),
                        ),
                      )
                    : Container(
                        color: Colors.grey[800],
                        child: const Icon(Icons.album,
                            size: 24, color: Colors.white38),
                      ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.trackName,
                    style: TextStyle(
                      color: isPlaying
                          ? const Color(0xFF1DB954)
                          : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artistName,
                    style: const TextStyle(
                      color: Color(0xFF9F9F9F),
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isPlaying)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.volume_up,
                    color: Color(0xFF1DB954), size: 18),
              ),
            GestureDetector(
              onTap: () => _toggleSaveTrack(track),
              child: context.watch<SavedItemsProvider>().isTrackSaved(track.trackId)
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: Colors.lightGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Icon(Icons.check,
                            size: 18, color: Colors.grey[700]),
                      ],
                    )
                  : const Icon(Icons.add_circle_outline,
                      color: Color(0xFF7A7A7A), size: 24),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _TabBarDelegate({required this.child});

  @override
  double get minExtent => 40;
  @override
  double get maxExtent => 40;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: const Color(0xFF121212), child: child);
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => true;
}
