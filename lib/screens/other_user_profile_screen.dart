import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../constants/adl_teams.dart';
import '../constants/profile_fonts.dart';
import '../models/user_model.dart';
import '../models/post_model.dart';
import '../models/track_model.dart';
import '../models/artist_model.dart';
import '../providers/saved_items_provider.dart';
import '../services/user_service.dart';
import '../services/post_service.dart';
import '../services/audio_player_service.dart';
import '../services/artist_service.dart';
import '../services/spotify_service.dart';
import '../widgets/profile_widgets.dart';
import '../widgets/common/app_toast.dart';
import 'adl_team_playlist_screen.dart';
import 'artist_profile_screen.dart';
import 'follow_list_screen.dart';
import 'music_memory_month_screen.dart';
import 'music_memory_detail_screen.dart';

/// 他人プロフィールのタブ
enum _OtherProfileTab { memories, saved }

/// Saved タブ内のサブタブ
enum _OtherSavedSubTab { songs, artists, playlists }

/// プロフィール画面（他人）
class OtherUserProfileScreen extends StatefulWidget {
  final String userId;

  const OtherUserProfileScreen({
    super.key,
    required this.userId,
  });

  @override
  State<OtherUserProfileScreen> createState() => _OtherUserProfileScreenState();
}

class _OtherUserProfileScreenState extends State<OtherUserProfileScreen>
    with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  final AudioPlayerService _audioService = AudioPlayerService();
  final ArtistService _artistService = ArtistService();

  // タブは「タップ限定」— 横スワイプでは切り替わらないので TabController は
  // 廃止。虹色バーは AnimationController でスライドさせる（新プロフィールと同構造）。
  _OtherProfileTab _tab = _OtherProfileTab.memories;
  late AnimationController _tabAnim; // 0.0=Memories, 1.0=Saved
  _OtherSavedSubTab _savedSubTab = _OtherSavedSubTab.songs;

  // フォロー中アーティスト（Saved > Artists で表示）
  List<ArtistModel> _followedArtists = const [];
  bool _isLoadingFollowedArtists = false;

  // 楽曲プレビュー再生中のトラック ID
  String? _playingTrackId;

  // ダミーユーザーの定数
  static const List<String> _dummyUsernames = [
    'momo.hirai',
    'mina.myoi',
    'm.by__sana',
  ];

  UserModel? _userData;
  List<PostModel> _otherPosts = [];
  List<PostModel> _savedPosts = [];
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isFollowedBy = false; // 相手が自分をフォローしているか


  // ダミーユーザー用フォロワー数オーバーライド
  int? _followerCountOverride;

  int get _followersCount =>
      _followerCountOverride ?? _userData?.followersCount ?? 0;
  int get _followingCount => _userData?.followingCount ?? 0;

  @override
  void initState() {
    super.initState();
    _tabAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    // 班アカウント (users/{teamId}) の場合は専用プロフィール画面に置換遷移
    if (AdlTeamDefinitions.isTeamAccountUid(widget.userId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AdlTeamPlaylistScreen(teamId: widget.userId),
          ),
        );
      });
      return;
    }

    _loadData();
  }

  @override
  void dispose() {
    _tabAnim.dispose();
    _audioService.stopIfOwner(this);
    super.dispose();
  }

  void _switchTab(_OtherProfileTab next) {
    if (_tab == next) return;
    setState(() => _tab = next);
    if (next == _OtherProfileTab.saved) {
      _tabAnim.forward();
      if (_savedPosts.isEmpty) _loadSavedPosts();
      _loadFollowedArtists();
    } else {
      _tabAnim.reverse();
    }
  }

  /// このプロフィールユーザがフォロー中のアーティストを Firestore から取得。
  Future<void> _loadFollowedArtists() async {
    if (widget.userId.isEmpty) return;
    setState(() => _isLoadingFollowedArtists = true);
    try {
      final list = await _artistService.getFollowedArtists(widget.userId);
      if (!mounted) return;
      setState(() {
        _followedArtists = list;
        _isLoadingFollowedArtists = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingFollowedArtists = false);
    }
  }

  /// プロフィール画像を拡大表示（円形に切り抜き）
  void _showProfileImageDialog(String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(40),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: ClipOval(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  color: const Color(0xFF2A2A2A),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.person,
                    color: Colors.white54,
                    size: 80,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// データを全て再読み込み
  Future<void> _refresh() async {
    final refreshStart = DateTime.now();
    await Future.wait([
      _loadData(),
      _loadSavedPosts(),
    ]);
    // 最低1秒はリフレッシュインジケーターを表示
    final elapsed = DateTime.now().difference(refreshStart);
    if (elapsed < const Duration(seconds: 1)) {
      await Future.delayed(Duration(seconds: 1) - elapsed);
    }
  }

  /// データを読み込み
  Future<void> _loadData() async {
    try {
      final userData = await _userService.getUser(widget.userId);

      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      UserModel? currentUser;
      if (currentUserId != null) {
        currentUser = await _userService.getUser(currentUserId);
      }

      final otherPosts =
          await _postService.getPostsExcludingToday(widget.userId, limit: 50);

      if (mounted) {
        final isDummyUser =
            _dummyUsernames.contains(userData?.username ?? '');

        // 公開範囲フィルタ: 鍵投稿は「自分自身」or「フォローしている」場合のみ表示。
        // ADL班プロフィールは別画面（[AdlTeamPlaylistScreen]）で扱うのでここでは考慮不要。
        final isViewerAuthor = currentUserId == widget.userId;
        final viewerFollowsAuthor =
            currentUser?.isFollowing(widget.userId) ?? false;
        final canSeeFollowersOnly = isViewerAuthor || viewerFollowsAuthor;

        // 48時間 + 公開範囲フィルタ
        final cutoff48h = DateTime.now().subtract(const Duration(hours: 48));
        final visibleOtherPosts = otherPosts.where((p) {
          if (!p.createdAt.isBefore(cutoff48h)) return false;
          if (p.audience == PostAudience.followers && !canSeeFollowersOnly) {
            return false;
          }
          return true;
        }).toList();

        setState(() {
          _userData = userData;
          _otherPosts = visibleOtherPosts;
          _isFollowing = viewerFollowsAuthor;
          _isFollowedBy = userData?.following.contains(currentUserId) ?? false;
          _isLoading = false;

          if (isDummyUser) {
            _followerCountOverride = userData?.followers.length ?? 0;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 保存済み投稿を読み込み
  Future<void> _loadSavedPosts() async {
    try {
      final savedPosts =
          await _postService.getPostsSavedByUser(widget.userId);
      if (mounted) {
        setState(() {
          _savedPosts = savedPosts;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('保存済み投稿の読み込みエラー: $e');
      }
    }
  }

  /// フォロー/アンフォローを切り替え
  Future<void> _toggleFollow() async {
    final currentUsername = _userData?.username ?? '';

    if (_dummyUsernames.contains(currentUsername)) {
      setState(() {
        _isFollowing = !_isFollowing;
        _followerCountOverride ??= _userData?.followers.length ?? 0;
        _followerCountOverride = _isFollowing
            ? (_followerCountOverride! + 1)
            : (_followerCountOverride! - 1);
      });
      return;
    }

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    HapticFeedback.mediumImpact();

    final previousState = _isFollowing;
    setState(() {
      _isFollowing = !_isFollowing;
    });

    try {
      if (_isFollowing) {
        await _userService.followUser(
          currentUserId: currentUserId,
          targetUserId: widget.userId,
        );
      } else {
        await _userService.unfollowUser(
          currentUserId: currentUserId,
          targetUserId: widget.userId,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFollowing = previousState;
        });
        AppToast.show(context, 'エラーが発生しました: $e');
      }
    }
  }

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

    if (_userData == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'ユーザーが見つかりません',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('戻る'),
              ),
            ],
          ),
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
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: Colors.white,
                backgroundColor: const Color(0xFF1E1E1E),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildProfileInfo(),
                      _buildStatsRow(),
                      const SizedBox(height: 12),
                      _buildActionButtons(),
                      const SizedBox(height: 12),
                      _buildTabSelector(),
                      ..._buildActiveTabContent(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ヘッダー（戻るボタン + ユーザーID）
  Widget _buildHeader() {
    final username = _userData?.username ?? 'ユーザー名';

    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          // ユーザーID（中央）
          Center(
            child: Text(
              username,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // 戻るボタン（左端）
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () {
                _audioService.stop();
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// プロフィール情報セクション（新プロフィールと同じレイアウト）。
  ///
  /// レイアウト:
  ///   - 上段: 左に 85×85 アバター、右に 名前 / @handle / bio
  Widget _buildProfileInfo() {
    final displayName = _userData?.name ?? '';
    final handle = _userData?.username;
    final bio = _userData?.bio;
    final profileImageUrl = _userData?.profileImageUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(27, 24, 27, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: profileImageUrl != null && profileImageUrl.isNotEmpty
                ? () => _showProfileImageDialog(profileImageUrl)
                : null,
            child: Container(
              width: 85,
              height: 85,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[800],
              ),
              child: ClipOval(
                child: ProfileImage(imageUrl: profileImageUrl, size: 85),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (displayName.isNotEmpty)
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (handle != null && handle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      handle.startsWith('@') ? handle : '@$handle',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: kSfProRounded,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (bio != null && bio.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      bio,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontFamily: kSfProRounded,
                        height: 1.35,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 統計行（Followers / Following）— スタック format。
  /// Tracks は非表示にし、Followers / Following を中央に寄せて並べる（自分の
  /// プロフィールと同様）。
  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(27, 20, 27, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _statItem(
            _followersCount,
            'Followers',
            onTap: () => _openFollowList(true),
          ),
          const SizedBox(width: 56),
          _statItem(
            _followingCount,
            'Following',
            onTap: () => _openFollowList(false),
          ),
        ],
      ),
    );
  }

  Widget _statItem(int count, String label, {VoidCallback? onTap}) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontFamily: kSfProRounded,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF919191),
            fontFamily: 'SF Pro',
            fontSize: 11,
            height: 1.256,
          ),
        ),
      ],
    );
    if (onTap == null) return Center(child: content);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(child: content),
    );
  }

  void _openFollowList(bool showFollowers) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FollowListScreen(
          userId: widget.userId,
          showFollowers: showFollowers,
        ),
      ),
    );
  }

  /// アクションボタン（フォロー）
  Widget _buildActionButtons() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == widget.userId) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 21),
      child: GestureDetector(
        onTap: _toggleFollow,
        child: Container(
          height: 32,
          decoration: BoxDecoration(
            color: _isFollowing ? Colors.transparent : const Color(0xFF0098FE),
            border: _isFollowing
                ? Border.all(color: const Color(0xFF929292))
                : null,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Center(
            child: Text(
              _isFollowing
                  ? 'フォロー中'
                  : _isFollowedBy
                      ? 'フォローバック'
                      : 'フォロー',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontFamily: kSfProRounded,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Memories / Saved タブ切替（新プロフィールと同じアセット/構造）
  Widget _buildTabSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: AnimatedBuilder(
        animation: _tabAnim,
        builder: (context, _) {
          final t = _tabAnim.value.clamp(0.0, 1.0);
          return LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              final tabWidth = totalWidth / 2;
              const barWidth = 141.0;
              const barHeight = 3.0;
              final barLeft = (tabWidth - barWidth) / 2 + t * tabWidth;

              return Stack(
                children: [
                  Container(
                    height: 39,
                    decoration: BoxDecoration(
                      color: const Color(0xFF090909),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: const Color(0xFF1F1F20),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        _tabItem(
                          activeAsset: 'assets/profile/tab_calendar_active.png',
                          inactiveAsset:
                              'assets/profile/tab_calendar_inactive.png',
                          label: 'Memories',
                          active: _tab == _OtherProfileTab.memories,
                          onTap: () => _switchTab(_OtherProfileTab.memories),
                        ),
                        _tabItem(
                          activeAsset: 'assets/profile/tab_heart_active.png',
                          inactiveAsset:
                              'assets/profile/tab_heart_inactive.png',
                          label: 'Saved',
                          active: _tab == _OtherProfileTab.saved,
                          onTap: () => _switchTab(_OtherProfileTab.saved),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: totalWidth / 2 - 0.5,
                    top: 9,
                    bottom: 10,
                    width: 1,
                    child: const ColoredBox(color: Color(0xFF2E2E2E)),
                  ),
                  Positioned(
                    bottom: 0,
                    left: barLeft,
                    child: Image.asset(
                      'assets/profile/tab_rainbow_bar.png',
                      width: barWidth,
                      height: barHeight,
                      fit: BoxFit.fill,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _tabItem({
    required String activeAsset,
    required String inactiveAsset,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final labelColor = active ? Colors.white : const Color(0xFF8B8B8B);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              active ? activeAsset : inactiveAsset,
              width: 14,
              height: 14,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: 12,
                fontFamily: kSfProRounded,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// アクティブタブに応じた本文。
  List<Widget> _buildActiveTabContent() {
    if (_tab == _OtherProfileTab.saved) {
      return [_buildSavedContent()];
    }
    return [
      _buildMusicMemorySection(),
      _buildMyPlaylistSection(),
    ];
  }

  // ── Music Memory + Playlist ─────────────────────────────────────

  Widget _buildMusicMemorySection() {
    // Figma 4773:10023 準拠。タイトル→週カード=9, 週カード→記録カード=18,
    // 記録カードは 236 幅で中央(padding-h 67)。
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Music Memory',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: kSfProRounded,
            ),
          ),
          const SizedBox(height: 9),
          _buildWeekCard(),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 67),
            child: _buildRecordCard(),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekCard() {
    // border は foregroundDecoration で「子より前面」に描く。
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131315),
        borderRadius: BorderRadius.circular(19),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFF272627), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openMusicMemoryMonth,
            child: Container(
              height: 44,
              color: const Color(0xFF131315),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    _currentWeekLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFamily: kSfProRounded,
                    ),
                  ),
                  const Spacer(),
                  Image.asset(
                    'assets/profile/memory_arrow.png',
                    width: 7,
                    height: 11,
                    errorBuilder: (_, __, ___) => const Icon(
                      CupertinoIcons.chevron_right,
                      color: Colors.white70,
                      size: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 中身の Stack が Positioned で絶対配置するため alignment は使わない。
          SizedBox(
            height: 70,
            child: ColoredBox(
              color: const Color(0xFF0B0B0B),
              child: _buildWeekMemoryRow(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard() {
    final musicCount = _otherPosts.length;
    final streak = _computePostingStreak();
    return Container(
      height: 47,
      decoration: BoxDecoration(
        color: const Color(0xFF09090A),
        borderRadius: BorderRadius.circular(15),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF272627), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('💜', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    '$musicCount Music',
                    style: const TextStyle(
                      color: Color(0xFF5C5656),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: kSfProRounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 14, color: const Color(0xFF272627)),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(
                    '${streak}d 連続',
                    style: const TextStyle(
                      color: Color(0xFF5C5656),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: kSfProRounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _computePostingStreak() {
    if (_otherPosts.isEmpty) return 0;
    final days = <DateTime>{};
    for (final p in _otherPosts) {
      final d = p.createdAt;
      days.add(DateTime(d.year, d.month, d.day));
    }
    var streak = 0;
    var cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  String _currentWeekLabel() {
    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);
    final week = ((now.day + firstOfMonth.weekday - 1) / 7).ceil();
    return '${now.month}月 Week$week';
  }

  /// Figma 4773:10031 準拠。7 スロット(日曜〜土曜)。他人プロフィールなので
  /// 「新規投稿」枠は出ない(未投稿の日はドットのまま)。
  Widget _buildWeekMemoryRow() {
    const dotSize = 12.0;
    const artSize = 42.0;
    const dotLeftXs = <double>[35, 83, 131, 179, 227, 275, 323];
    const dotY = 31.0;
    const artY = 14.0;

    final now = DateTime.now();
    final weekday = now.weekday % 7;
    final sunday = DateTime(now.year, now.month, now.day - weekday);
    final byDay = <int, PostModel>{};
    for (final p in _otherPosts) {
      if (p.createdAt.isBefore(sunday)) continue;
      if (p.createdAt.isAfter(sunday.add(const Duration(days: 7)))) continue;
      final idx = p.createdAt.difference(sunday).inDays;
      if (idx < 0 || idx > 6) continue;
      byDay.putIfAbsent(idx, () => p);
    }

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        for (int i = 0; i < 7; i++)
          _weekMemorySlot(
            i: i,
            post: byDay[i],
            dotLeftX: dotLeftXs[i],
            dotY: dotY,
            artY: artY,
            dotSize: dotSize,
            artSize: artSize,
          ),
      ],
    );
  }

  Widget _weekMemorySlot({
    required int i,
    required PostModel? post,
    required double dotLeftX,
    required double dotY,
    required double artY,
    required double dotSize,
    required double artSize,
  }) {
    final artLeft = dotLeftX + (dotSize - artSize) / 2;
    if (post != null) {
      return Positioned(
        left: artLeft,
        top: artY,
        width: artSize,
        height: artSize,
        child: GestureDetector(
          onTap: () => _openPostCardBack(post),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _albumArtOrPlaceholder(post.track.albumImageUrl),
          ),
        ),
      );
    }
    return Positioned(
      left: dotLeftX,
      top: dotY,
      width: dotSize,
      height: dotSize,
      child: Image.asset(
        'assets/profile/memory_dot.png',
        width: dotSize,
        height: dotSize,
        errorBuilder: (_, __, ___) => Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF2A2A2A),
          ),
        ),
      ),
    );
  }

  Widget _albumArtOrPlaceholder(String url) {
    if (url.isEmpty) {
      return Container(
        color: const Color(0xFF3A3A3A),
        alignment: Alignment.center,
        child: const Icon(Icons.album, color: Colors.white38, size: 18),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => Container(
        color: const Color(0xFF3A3A3A),
        alignment: Alignment.center,
        child: const Icon(Icons.album, color: Colors.white38, size: 18),
      ),
    );
  }

  Future<void> _openMusicMemoryMonth() async {
    final grouped = <String, List<PostModel>>{};
    for (final p in _otherPosts) {
      final key =
          '${p.createdAt.year}-${p.createdAt.month.toString().padLeft(2, '0')}';
      (grouped[key] ??= []).add(p);
    }
    await MusicMemoryMonthScreen.push(context, postsByMonth: grouped);
  }

  /// アルバムアートタップ → Music Memory 詳細（日カルーセル）。
  /// カレンダー(月)から辿り着く画面と同じ。各日の代表（最新1件）を新→古で並べ、
  /// タップした投稿の日を初期表示にする。
  Future<void> _openPostCardBack(PostModel post) async {
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final repByDay = <String, PostModel>{};
    for (final p in _otherPosts) {
      final key = '${p.createdAt.year}-${p.createdAt.month}-${p.createdAt.day}';
      final ex = repByDay[key];
      if (ex == null || p.createdAt.isAfter(ex.createdAt)) repByDay[key] = p;
    }
    final days = repByDay.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (days.isEmpty) days.add(post);
    final idx = days.indexWhere((p) => sameDay(p.createdAt, post.createdAt));

    await MusicMemoryDetailScreen.push(
      context,
      posts: days,
      initialIndex: idx < 0 ? 0 : idx,
    );
  }

  Widget _buildMyPlaylistSection() {
    const existingCount = 0; // 実データ配線までは占位のみ
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 26, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 2),
            child: Text(
              'My Playlist',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: kSfProRounded,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 116,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              children: [
                for (int i = 0; i < existingCount; i++) ...[
                  if (i > 0) const SizedBox(width: 30),
                  _playlistExistingSlot(name: 'Night', trackCount: 23),
                ],
                if (existingCount == 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 40),
                    child: Text(
                      'プレイリストがありません',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playlistExistingSlot({required String name, required int trackCount}) {
    return SizedBox(
      width: 57,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/profile/playlist_existing.png',
            width: 57,
            height: 81,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              width: 57,
              height: 81,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: const Color(0xFF424242),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontFamily: 'SF Pro',
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '$trackCount曲',
            style: const TextStyle(
              color: Color(0xFF9E9FA1),
              fontSize: 9,
              fontFamily: 'SF Pro',
              height: 1.44,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Saved (3 サブタブ) ─────────────────────────────────────────

  /// Saved タブ本文。Figma 4682:8196: サブタブ(38)直下からリスト(60×N)が始まる。
  Widget _buildSavedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRecentlySavedSection(),
        _buildSavedSubTabs(),
        _buildSavedSubTabContent(),
      ],
    );
  }

  /// Recently Saved セクション（Figma 4679:9793）。
  /// アルバム 90×90 radius 10 + border `#323232`、タイトル 14px、アーティスト #9B9B9B。
  Widget _buildRecentlySavedSection() {
    if (_savedPosts.isEmpty) return const SizedBox.shrink();
    final sorted = List<PostModel>.from(_savedPosts)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recent = sorted.take(8).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recently Saved',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: kSfProRounded,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: recent.length,
              separatorBuilder: (_, __) => const SizedBox(width: 15),
              itemBuilder: (context, i) =>
                  _recentlySavedItem(recent[i].track),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentlySavedItem(TrackModel track) {
    return SizedBox(
      width: 90,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF323232), width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: track.albumImageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: track.albumImageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFF2A2A2A),
                      alignment: Alignment.center,
                      child: const Icon(Icons.album,
                          color: Colors.white38, size: 28),
                    ),
                  )
                : Container(
                    color: const Color(0xFF2A2A2A),
                    alignment: Alignment.center,
                    child: const Icon(Icons.album,
                        color: Colors.white38, size: 28),
                  ),
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Text(
              track.trackName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: kSfProRounded,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Text(
              track.artistName,
              style: const TextStyle(
                color: Color(0xFF9B9B9B),
                fontSize: 10,
                height: 1.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Figma 4679:9838: サブタブバー。
  /// - Container 38 高 / bg #131315 / border #272627 1px / 上端 radius 19
  /// - テキスト 12px SF Pro Rounded Bold / active white / 非active #8B8B8B
  /// - 下線 77×2 が active タブ下端(bottom:1)
  Widget _buildSavedSubTabs() {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFF131315),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(19),
          topRight: Radius.circular(19),
        ),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(19),
          topRight: Radius.circular(19),
        ),
        border: Border.all(color: const Color(0xFF272627), width: 1),
      ),
      child: Row(
        children: [
          _savedSubTabItem('Songs', _OtherSavedSubTab.songs),
          _savedSubTabItem('Artists', _OtherSavedSubTab.artists),
          _savedSubTabItem('Playlists', _OtherSavedSubTab.playlists),
        ],
      ),
    );
  }

  Widget _savedSubTabItem(String label, _OtherSavedSubTab tab) {
    final active = _savedSubTab == tab;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _savedSubTab = tab);
          if (tab == _OtherSavedSubTab.artists) _loadFollowedArtists();
        },
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: 12,
              child: Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xFF8B8B8B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: kSfProRounded,
                ),
              ),
            ),
            Positioned(
              bottom: 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 2,
                width: active ? 77 : 0,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedSubTabContent() {
    switch (_savedSubTab) {
      case _OtherSavedSubTab.songs:
        return _buildSavedSongsList();
      case _OtherSavedSubTab.artists:
        return _buildSavedArtistsList();
      case _OtherSavedSubTab.playlists:
        return _buildSavedPlaylistsList();
    }
  }

  Widget _buildSavedSongsList() {
    if (_savedPosts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: Center(
          child: Text(
            '保存済みの楽曲がありません',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      );
    }
    return Column(
      children: _savedPosts
          .map((p) => _OtherSavedTrackItem(
                track: p.track,
                postId: p.postId,
                isPlaying: _playingTrackId == p.track.trackId,
                onPlayTap: () => _handlePlay(p.track),
                onSaveTap: () => SavedItemsProvider.togglePostWithToast(
                    context, p),
              ))
          .toList(growable: false),
    );
  }

  Future<void> _handlePlay(TrackModel track) async {
    final playing = _playingTrackId == track.trackId;
    if (playing) {
      _audioService.stop();
      setState(() => _playingTrackId = null);
      return;
    }
    setState(() => _playingTrackId = track.trackId);
    final url = track.previewUrl;
    if (url != null && url.isNotEmpty) {
      await _audioService.playPreview(url);
    }
  }

  Widget _buildSavedArtistsList() {
    if (_isLoadingFollowedArtists && _followedArtists.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CupertinoActivityIndicator(color: Colors.white70, radius: 10),
        ),
      );
    }
    if (_followedArtists.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: Center(
          child: Text(
            'フォロー中のアーティストがいません',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      );
    }
    return Column(
      children:
          _followedArtists.map((a) => _followedArtistRow(a)).toList(growable: false),
    );
  }

  Widget _followedArtistRow(ArtistModel artist) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ArtistProfileScreen(artistName: artist.artistName),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _OtherFollowedArtistAvatar(artist: artist),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'アーティスト',
                    style: TextStyle(
                      color: Color(0xFF9A9A9A),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedPlaylistsList() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Center(
        child: Text(
          '保存済みのプレイリストがありません',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ),
    );
  }
}

/// 他人のフォロー中アーティストのアバター(56×56)。
///
/// - artist.imageUrl があれば直接表示
/// - 無ければ Spotify 名前検索で都度取得(セッション内キャッシュあり、
///   関連アーティストにヒットするケースがあるため Firestore には保存しない)
class _OtherFollowedArtistAvatar extends StatefulWidget {
  final ArtistModel artist;
  const _OtherFollowedArtistAvatar({required this.artist});

  @override
  State<_OtherFollowedArtistAvatar> createState() =>
      _OtherFollowedArtistAvatarState();
}

class _OtherFollowedArtistAvatarState
    extends State<_OtherFollowedArtistAvatar> {
  final SpotifyService _spotify = SpotifyService();
  String? _resolvedUrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.artist.imageUrl;
    if (saved != null && saved.isNotEmpty) {
      _resolvedUrl = saved;
    } else {
      _fetchOnDemand();
    }
  }

  Future<void> _fetchOnDemand() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final url = await _spotify.getArtistImageUrl(widget.artist.artistName);
      if (!mounted) return;
      setState(() {
        _resolvedUrl = url;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: 56,
        height: 56,
        child: (_resolvedUrl != null && _resolvedUrl!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: _resolvedUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const _OtherArtistAvatarPlaceholder(),
              )
            : const _OtherArtistAvatarPlaceholder(),
      ),
    );
  }
}

class _OtherArtistAvatarPlaceholder extends StatelessWidget {
  const _OtherArtistAvatarPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF2A2A2A),
      alignment: Alignment.center,
      child: const Icon(Icons.person, color: Colors.white38, size: 26),
    );
  }
}

/// 他人プロフィールの Saved > Songs 行。プレイ・保存トグルは新プロフィールと同構造。
class _OtherSavedTrackItem extends StatelessWidget {
  final TrackModel track;
  final String? postId;
  final bool isPlaying;
  final Future<void> Function() onPlayTap;
  final Future<void> Function() onSaveTap;

  const _OtherSavedTrackItem({
    required this.track,
    this.postId,
    required this.isPlaying,
    required this.onPlayTap,
    required this.onSaveTap,
  });

  @override
  Widget build(BuildContext context) {
    final savedItems = context.watch<SavedItemsProvider>();
    final isSaved = savedItems.isTrackSaved(track.trackId) ||
        (postId != null && savedItems.isPostSaved(postId!));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPlayTap,
      child: Container(
        height: 60,
        color: isPlaying ? const Color(0xFF2A2A2A) : const Color(0xFF121212),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                width: 50,
                height: 50,
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
            const SizedBox(width: 22),
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
                      fontWeight: FontWeight.w500,
                      height: 1.198,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artistName,
                    style: const TextStyle(
                      color: Color(0xFF9B9B9B),
                      fontSize: 10,
                      height: 1.5,
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
              behavior: HitTestBehavior.opaque,
              onTap: () => onSaveTap(),
              child: isSaved
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
                        Icon(Icons.check, size: 18, color: Colors.grey[700]),
                      ],
                    )
                  : const Icon(Icons.add_circle_outline,
                      color: Colors.white54, size: 24),
            ),
          ],
        ),
      ),
    );
  }
}
