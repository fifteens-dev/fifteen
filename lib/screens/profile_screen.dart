import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/saved_items_provider.dart';
import '../services/user_service.dart';
import '../services/post_service.dart';
import '../services/audio_player_service.dart';
import '../services/artist_service.dart';
import '../services/spotify_service.dart';
import '../models/user_model.dart';
import '../models/post_model.dart';
import '../models/track_model.dart';
import '../models/artist_model.dart';
import 'artist_profile_screen.dart';
import '../widgets/profile_widgets.dart';
import 'settings_screen.dart';
import 'follow_list_screen.dart';
import 'music_memory_month_screen.dart';
import '../widgets/common/app_toast.dart';
import '../constants/profile_fonts.dart';

/// プロフィール画面（自分）
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

/// プロフィール上部タブ
enum _ProfileTab { memories, saved }

/// Saved タブ内のサブタブ
enum _SavedSubTab { songs, artists, playlists }

class ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  final AudioPlayerService _audioService = AudioPlayerService();
  final ArtistService _artistService = ArtistService();
  final ScrollController _scrollController = ScrollController();

  // タブは「タップ限定」— 横スワイプでは切り替わらないので TabController も
  // PageController も使わない。虹色バーは AnimationController でスライドさせる。
  _ProfileTab _tab = _ProfileTab.memories;
  late AnimationController _tabAnim; // 0.0=Memories, 1.0=Saved
  _SavedSubTab _savedSubTab = _SavedSubTab.songs;

  // フォロー中アーティスト（Saved > Artists で表示）
  List<ArtistModel> _followedArtists = const [];
  bool _isLoadingFollowedArtists = false;

  // ユーザーデータ
  UserModel? _userData;
  bool _isLoading = true;

  // 保存済み投稿
  List<PostModel> _savedPosts = [];
  String? _playingTrackId;


  // 自分の投稿（Music Memory Week / Month 用）
  List<PostModel> _otherPosts = [];
  int _totalPostCount = 0;

  int get _tracksCount => _totalPostCount;
  int get _followersCount => _userData?.followersCount ?? 0;
  int get _followingCount => _userData?.followingCount ?? 0;


  @override
  void initState() {
    super.initState();
    _tabAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _loadPostCount();
    _loadUserData();
    _loadUserPosts();
  }

  @override
  void dispose() {
    _tabAnim.dispose();
    _scrollController.dispose();
    _audioService.stopIfOwner(this);
    super.dispose();
  }

  void _switchTab(_ProfileTab next) {
    if (_tab == next) return;
    setState(() => _tab = next);
    if (next == _ProfileTab.saved) {
      _tabAnim.forward();
      _loadSavedTabData();
      _loadFollowedArtists();
    } else {
      _tabAnim.reverse();
    }
  }

  /// フォロー中アーティスト（＝Saved > Artists）を Firestore から取得。
  Future<void> _loadFollowedArtists() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isLoadingFollowedArtists = true);
    try {
      final list = await _artistService.getFollowedArtists(uid);
      if (!mounted) return;
      setState(() {
        _followedArtists = list;
        _isLoadingFollowedArtists = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingFollowedArtists = false);
    }
  }

  /// 投稿総数を取得（グリッド表示数とは独立して取得）
  Future<void> _loadPostCount() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    try {
      final count = await _postService.getPostCountByUserId(currentUser.uid);
      if (mounted) setState(() => _totalPostCount = count);
    } catch (_) {}
  }

  /// ユーザーデータを読み込み
  Future<void> _loadUserData() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    // Web開発用：Firebase認証がない場合はダミーデータを使用
    if (currentUser == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      print('[ProfileScreen] _loadUserData: fetching uid=${currentUser.uid}');
      final userData = await _userService.getUser(currentUser.uid);
      print('[ProfileScreen] _loadUserData: success name=${userData?.name} username=${userData?.username}');
      if (mounted) {
        setState(() {
          _userData = userData;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[ProfileScreen] _loadUserData: error=$e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// ユーザーの投稿を読み込み（初回）
  /// [limit] 起動時は9件、リフレッシュ時は20件
  Future<void> _loadUserPosts({int limit = 9}) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      print('[ProfileScreen] _loadUserPosts: fetching uid=${currentUser.uid}');
      final result = await _postService.getPostsByUserIdPaged(
        currentUser.uid,
        limit: limit,
      );
      print('[ProfileScreen] _loadUserPosts: success count=${result.posts.length} hasMore=${result.hasMore}');

      if (mounted) {
        setState(() {
          _otherPosts = result.posts;
        });
      }
    } catch (e) {
      print('[ProfileScreen] _loadUserPosts: error=$e');
    }
  }

  /// 保存済み投稿を読み込み
  Future<void> _loadSavedPosts() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) return;

    try {
      // savedByUserIds フィールドを使った単一クエリで取得
      final posts = await _postService.getPostsSavedByUser(currentUser.uid);

      if (mounted) {
        setState(() {
          _savedPosts = posts;
        });
      }
    } catch (e) {
      print('保存済み投稿の読み込みエラー: $e');
    }
  }

  /// 保存タブに遷移したときに呼ぶ。投稿・ユーザー情報を再読み込みし、
  /// SavedItemsProvider も最新化する。
  Future<void> _loadSavedTabData() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    await Future.wait([
      _loadSavedPosts(),
      _loadUserData(),
    ]);
    if (mounted && _userData != null) {
      context.read<SavedItemsProvider>().initialize(
        userId: currentUser.uid,
        user: _userData!,
      );
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
    final currentUser = FirebaseAuth.instance.currentUser;
    await Future.wait([
      _loadUserData(),
      _loadUserPosts(limit: 20),
      _loadPostCount(),
      _loadSavedPosts(),
    ]);
    // SavedItemsProvider も最新化（保存タブ・他画面の保存状態に反映）
    if (mounted && _userData != null && currentUser != null) {
      context.read<SavedItemsProvider>().initialize(
        userId: currentUser.uid,
        user: _userData!,
      );
    }
    // 最低1秒はリフレッシュインジケーターを表示
    final elapsed = DateTime.now().difference(refreshStart);
    if (elapsed < const Duration(seconds: 1)) {
      await Future.delayed(Duration(seconds: 1) - elapsed);
    }
  }

  /// 投稿を削除
  Future<void> _deletePost(PostModel post) async {
    try {
      await _postService.deletePost(post.postId);
      if (mounted) {
        setState(() {
          _otherPosts.removeWhere((p) => p.postId == post.postId);
        });
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '削除に失敗しました');
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
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildProfileInfo(),
                      _buildStatsRow(),
                      const SizedBox(height: 20),
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

  /// ヘッダー（ユーザーID + 設定アイコン）
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
          // 設定アイコン（右端）
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
                // 設定画面から戻ったらデータを再読み込み
                _loadUserData();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// プロフィール情報セクション（Figma 4687:8337 / 4687:8330）。
  ///
  /// レイアウト:
  ///   - 上段: 左に 85×85 アバター、右に 名前 / @handle / bio (自己紹介)
  ///   - 下段: Tracks / Followers / Following の 3カラム
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
          // 左: 85×85 アバター
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
          // 右: 名前 / @handle / bio
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
                      // 自己紹介欄は英数字でも SF Pro Rounded
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

  /// 統計行（Tracks / Followers / Following）— 数字は SF Pro Rounded。
  /// Figma 4687:8330 に沿い、行幅 286 内で 3等分。
  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(27, 20, 27, 4),
      child: Row(
        children: [
          Expanded(child: _statItem(_tracksCount, 'Tracks')),
          Expanded(
            child: _statItem(
              _followersCount,
              'Followers',
              onTap: () => _openFollowList(true),
            ),
          ),
          Expanded(
            child: _statItem(
              _followingCount,
              'Following',
              onTap: () => _openFollowList(false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(int count, String label, {VoidCallback? onTap}) {
    // Figma 4687:8330: スタック配置。
    // - 数字 20px SF Pro Rounded Bold 白
    // - ラベル 11px SF Pro Regular #919191
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
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FollowListScreen(
          userId: userId,
          showFollowers: showFollowers,
        ),
      ),
    );
  }

  /// Memories / Saved タブ切替（素材モックアップに準拠）
  ///
  /// 仕様:
  ///   - タップのみで切替（横スワイプ不可）
  ///   - 下部の虹色バー（アセット画像）が選択タブ側にスライド
  ///   - アイコンは選択でカラー・非選択でグレー
  ///   - ラベルは SF Pro Rounded
  Widget _buildTabSelector() {
    // Figma 4687:8389: Frame 683 は Frame 699 (x=14) 直下で幅 373 →
    // 画面左から 14px 左オフセットで配置。Music Memory 枠 (x=14, w=370) と
    // 同じ左端に揃える。
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
                // Figma 4687:8390: 39px 高 / bg #090909 / border #1F1F20 / radius 13
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
                        active: _tab == _ProfileTab.memories,
                        onTap: () => _switchTab(_ProfileTab.memories),
                      ),
                      _tabItem(
                        activeAsset: 'assets/profile/tab_heart_active.png',
                        inactiveAsset: 'assets/profile/tab_heart_inactive.png',
                        label: 'Saved',
                        active: _tab == _ProfileTab.saved,
                        onTap: () => _switchTab(_ProfileTab.saved),
                      ),
                    ],
                  ),
                ),
                // 中央縦線（Figma Line 150）— 20px 高
                Positioned(
                  left: totalWidth / 2 - 0.5,
                  top: 9,
                  bottom: 10,
                  width: 1,
                  child: const ColoredBox(color: Color(0xFF2E2E2E)),
                ),
                // 虹色スライドバー（アセット画像）
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
    // Figma 4687:8389:
    //   - アイコン 14×14 相当
    //   - ラベル 12px SF Pro Rounded Semibold
    //   - 非選択色 #8B8B8B
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

  /// アクティブタブに応じた本文（通常 Widget リスト）。
  /// 横スワイプはさせないので PageView 不使用。
  List<Widget> _buildActiveTabContent() {
    if (_tab == _ProfileTab.saved) {
      return [_buildSavedContent()];
    }
    return [
      _buildMusicMemorySection(),
      _buildMyPlaylistSection(),
    ];
  }

  // ── Memories タブ: Music Memory + My Playlist ────────────────────

  /// Music Memory セクション。Figma 4773:10023 準拠:
  ///   - 「Music Memory」タイトル(y=0)、週カード(y=28)、記録カード(y=160)
  ///   - タイトル→週カード = 9px
  ///   - 週カード→記録カード = 18px
  ///   - 記録カードは 236 幅で中央に配置 (Music Memory枠 370 の中央、67px マージン)
  Widget _buildMusicMemorySection() {
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

  /// 週カード。上部ヘッダ全体タップで Month 画面へ横スライド遷移。
  /// Figma 4687:8344:
  ///   - コンテナ: border #272627 1px / radius 19 / 全体 114 高
  ///   - ヘッダ: 44 高 / bg #131315
  ///   - ドット行: 70 高 / bg #0B0B0B
  Widget _buildWeekCard() {
    // border は foregroundDecoration で「子より前面」に描く。
    // decoration の border は子の背景色(#0B0B0B)に上書きされて丸角部分で
    // 消えてしまうため、前景に置くことで丸角にも線が乗る。
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
          // ヘッダ 44 高（タップで Month へ）
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
          // 週の 6 スロット行 — 70 高 / bg #0B0B0B
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

  /// 記録カード。💜 曲数 と 🔥 連続日数 を並置。
  /// Figma 4687:8367: 236×47 / bg #09090A / border #272627 / radius 15
  ///   - テキスト 14px SF Pro Rounded Semibold color #5C5656
  ///   - 中央 divider Line 145 (14px 高)
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

  /// 連続投稿日数を集計（今日 → 過去へ、1日でも空くと打ち切り）
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

  /// 週内 7 スロットの帯（Figma 4773:10031 Frame 663 準拠、日曜〜土曜の 7 日分）
  /// - dot 位置: Frame 671 内 x=[0,48,96,144,192,240,288]、Frame 671 は
  ///   Frame 663 内で x=35 → 絶対 dot 左端: 35, 83, 131, 179, 227, 275, 323
  /// - dot Y = 31（Frame 663 高 70 内）
  /// - アルバム Y = 14（同上）42×42、dot と中心を揃える
  /// - 投稿のあった日: アルバムアート、今日で未投稿: 新規投稿枠、それ以外: dot
  Widget _buildWeekMemoryRow() {
    const dotSize = 12.0;
    const artSize = 42.0;
    // Figma 実座標(370 幅の Frame 663 内の絶対 x)。7 スロット = 日曜〜土曜。
    const dotLeftXs = <double>[35, 83, 131, 179, 227, 275, 323];
    const dotY = 31.0;
    const artY = 14.0;

    final now = DateTime.now();
    final weekday = now.weekday % 7; // Sunday=0
    final sunday = DateTime(now.year, now.month, now.day - weekday);
    final byDay = <int, PostModel>{};
    for (final p in _otherPosts) {
      if (p.createdAt.isBefore(sunday)) continue;
      if (p.createdAt.isAfter(sunday.add(const Duration(days: 7)))) continue;
      final idx = p.createdAt.difference(sunday).inDays;
      if (idx < 0 || idx > 6) continue;
      byDay.putIfAbsent(idx, () => p);
    }
    final todayIdx = weekday.clamp(0, 6);

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        for (int i = 0; i < 7; i++)
          _weekMemorySlot(
            i: i,
            post: byDay[i],
            isTodayEmpty:
                i == todayIdx && byDay[i] == null && _isCurrentUser,
            dotLeftX: dotLeftXs[i],
            dotY: dotY,
            artY: artY,
            dotSize: dotSize,
            artSize: artSize,
          ),
      ],
    );
  }

  /// 6 スロット中の 1 個。post がある → アルバム、今日で未投稿 → 新規投稿枠、
  /// それ以外 → dot。全て Positioned で Figma 座標に合わせて配置。
  Widget _weekMemorySlot({
    required int i,
    required PostModel? post,
    required bool isTodayEmpty,
    required double dotLeftX,
    required double dotY,
    required double artY,
    required double dotSize,
    required double artSize,
  }) {
    // アルバム/新規投稿枠は dot 中心と揃える(dotLeftX - 15)
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
    if (isTodayEmpty) {
      return Positioned(
        left: artLeft,
        top: artY,
        width: artSize,
        height: artSize,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openPostFlow,
          child: Image.asset(
            'assets/profile/memory_new_post.png',
            width: artSize,
            height: artSize,
            errorBuilder: (_, __, ___) => Container(
              width: artSize,
              height: artSize,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.add, color: Colors.white70, size: 20),
            ),
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

  bool get _isCurrentUser => FirebaseAuth.instance.currentUser != null;

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
    // 投稿を月キー(YYYY-MM)でグルーピング
    final grouped = <String, List<PostModel>>{};
    for (final p in _otherPosts) {
      final key =
          '${p.createdAt.year}-${p.createdAt.month.toString().padLeft(2, '0')}';
      (grouped[key] ??= []).add(p);
    }
    await MusicMemoryMonthScreen.push(context, postsByMonth: grouped);
  }

  void _openPostCardBack(PostModel post) {
    // 投稿カード裏面表示: 既存の詳細画面へルーティング（allPosts の中でこの投稿の
    // index を先頭にして渡すことで対象を開く）。
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: ProfilePostGridItem(
              post: post,
              allPosts: _otherPosts,
              initialIndex: _otherPosts.indexOf(post).clamp(0, _otherPosts.length - 1),
              onDelete: () => _deletePost(post),
              disableInteractions: false,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPostFlow() async {
    // Home 画面のセンター FAB 相当の投稿フローに接続する導線。
    // ここではトースト表示のみ（本フローの呼び出しは Home / navigation で共通化）。
    AppToast.show(context, '投稿フローを開きます');
  }

  /// My Playlist セクション（Figma 4687:8402 準拠）
  /// - サムネイル 57×81、間隔 30 (87 - 57 = 30)
  /// - 新規投稿枠のみカラー
  /// - 名前 10px SF Pro Medium 白 / "23曲" 9px SF Pro Regular #9E9FA1
  /// - 「新しいプレイリスト」9px SF Pro Medium #8C8986
  Widget _buildMyPlaylistSection() {
    // 表示するプレイリスト。実データが揃うまでは占位で 4 個表示。
    // TODO: PlaylistModel から実データを流し込む
    const existingCount = 4;
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
                _playlistNewSlot(),
                for (int i = 0; i < existingCount; i++) ...[
                  const SizedBox(width: 30),
                  _playlistExistingSlot(name: 'Night', trackCount: 23),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playlistNewSlot() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => AppToast.show(context, 'プレイリストを作成'),
      child: SizedBox(
        width: 57,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/profile/playlist_new.png',
              width: 57,
              height: 81,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                width: 57,
                height: 81,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF36C5F4), Color(0xFFF857C1), Color(0xFF6D5BFF)],
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.add, color: Colors.white, size: 24),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '新しいプレイリスト',
              style: TextStyle(
                color: Color(0xFF8C8986),
                fontSize: 9,
                fontFamily: 'SF Pro',
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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

  /// Saved タブの本文（Recently Saved + Songs / Artists / Playlists サブタブ）。
  /// Figma 4682:8196: サブタブ(38) 直下からリスト(60×N)が始まる(0 gap)。
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
  /// 直近保存の楽曲を横スクロールで最大 N 件表示。
  ///   - タイトル "Recently Saved" 16px SF Pro Rounded Bold
  ///   - アルバム 90×90 radius **10** + border `#323232` 1px
  ///   - タイトル 14px SF Pro Rounded Bold / アーティスト 10px `#9B9B9B`
  ///   - 間隔 15px、アルバム→テキスト 3px、Section 下 13px でサブタブに繋ぐ
  Widget _buildRecentlySavedSection() {
    final entries = _sortedSavedEntries();
    if (entries.isEmpty) return const SizedBox.shrink();
    final recent = entries.take(8).toList();
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
            height: 130, // 90(album) + 3(gap) + 33(text 2 lines) + 少しの余白
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: recent.length,
              separatorBuilder: (_, __) => const SizedBox(width: 15),
              itemBuilder: (context, i) {
                final e = recent[i];
                final track = e.track ?? e.post!.track;
                return _recentlySavedItem(track);
              },
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
          // 90×90 アルバム、radius 10、border #323232 1px
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
  /// - Container 38 高、bg #131315、border #272627 1px、**上端のみ radius 19**
  /// - 3タブ均等分割、テキスト 12px SF Pro Rounded Bold
  ///   active=white / 非active=#8B8B8B
  /// - 下線 77×2 が active タブ下端(bottom:1)に位置
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
          _savedSubTabItem('Songs', _SavedSubTab.songs),
          _savedSubTabItem('Artists', _SavedSubTab.artists),
          _savedSubTabItem('Playlists', _SavedSubTab.playlists),
        ],
      ),
    );
  }

  Widget _savedSubTabItem(String label, _SavedSubTab tab) {
    final active = _savedSubTab == tab;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _savedSubTab = tab);
          if (tab == _SavedSubTab.artists) _loadFollowedArtists();
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
      case _SavedSubTab.songs:
        return _buildSavedPostsGrid();
      case _SavedSubTab.artists:
        return _buildSavedArtistsList();
      case _SavedSubTab.playlists:
        return _buildSavedPlaylistsList();
    }
  }

  /// Artists サブタブ = **フォロー中アーティスト一覧**。
  /// モックアップ準拠: 円形アバター + アーティスト名 + "アーティスト" サブテキスト。
  /// タップで ArtistProfileScreen へ遷移。
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
      children: _followedArtists
          .map((a) => _followedArtistRow(a))
          .toList(growable: false),
    );
  }

  Widget _followedArtistRow(ArtistModel artist) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ArtistProfileScreen(
              artistName: artist.artistName,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _FollowedArtistAvatar(artist: artist),
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

  /// Playlists サブタブ。現状はプレイリスト保存機構が未実装なので占位。
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

  /// 楽曲(savedTracksData) と 投稿(savedPosts) を保存時刻で統合しソート。
  /// trackId 重複は track ベースを優先。最新が先頭。
  List<_SavedEntry> _sortedSavedEntries() {
    final savedTracksData = _userData?.savedTracksData ?? {};
    final savedPostsAt = _userData?.savedPostsAt ?? {};
    final entries = <_SavedEntry>[];
    final seenTrackIds = <String>{};

    for (final v in savedTracksData.values) {
      if (v is! Map) continue;
      final m = Map<String, dynamic>.from(v);
      final trackId = m['trackId']?.toString() ?? '';
      if (trackId.isEmpty || seenTrackIds.contains(trackId)) continue;
      seenTrackIds.add(trackId);
      final ts = m['savedAt'];
      entries.add(_SavedEntry(
        savedAt: ts is Timestamp ? ts.toDate() : DateTime(0),
        track: TrackModel(
          trackId: trackId,
          trackName: m['trackName']?.toString() ?? '',
          artistName: m['artistName']?.toString() ?? '',
          albumImageUrl: m['albumImageUrl']?.toString() ?? '',
          previewUrl: m['previewUrl']?.toString(),
        ),
      ));
    }

    for (final post in _savedPosts) {
      if (seenTrackIds.contains(post.track.trackId)) continue;
      seenTrackIds.add(post.track.trackId);
      final ts = savedPostsAt[post.postId];
      entries.add(_SavedEntry(
        savedAt: ts is Timestamp ? ts.toDate() : DateTime(0),
        post: post,
      ));
    }

    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return entries;
  }

  /// 保存済み楽曲リスト（Figma 566:8620準拠）
  Widget _buildSavedPostsGrid() {
    final entries = _sortedSavedEntries();

    if (entries.isEmpty) {
      return const Center(
        child: Text(
          '保存済みの楽曲がありません',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final e = entries[index];
        if (e.post != null) return _buildSavedTrackItem(e.post!);
        return _buildSavedTrackModelItem(e.track!);
      },
    );
  }

  Future<void> _handlePlay(TrackModel track) async {
    final isPlaying = _playingTrackId == track.trackId;
    if (isPlaying) {
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

  /// アーティストプロフィールから保存した楽曲の行（trackId ベース）
  Widget _buildSavedTrackModelItem(TrackModel track) {
    return _SavedTrackItem(
      track: track,
      isPlaying: _playingTrackId == track.trackId,
      onPlayTap: () => _handlePlay(track),
      onSaveTap: () => SavedItemsProvider.toggleTrackWithToast(context, track),
    );
  }

  /// 投稿保存から追加された楽曲の行（postId ベース）
  Widget _buildSavedTrackItem(PostModel post) {
    final track = post.track;
    return _SavedTrackItem(
      track: track,
      postId: post.postId,
      isPlaying: _playingTrackId == track.trackId,
      onPlayTap: () => _handlePlay(track),
      onSaveTap: () => SavedItemsProvider.togglePostWithToast(context, post),
    );
  }
}

/// 保存済み楽曲の行 Widget。
/// 保存状態は SavedItemsProvider から直接読み取り、タップで toggle を呼ぶ。
class _SavedTrackItem extends StatelessWidget {
  final TrackModel track;
  final String? postId; // 投稿として保存されている場合
  final bool isPlaying;
  final Future<void> Function() onPlayTap;
  final Future<void> Function() onSaveTap;

  const _SavedTrackItem({
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
                          child: const Icon(Icons.album, size: 24, color: Colors.white38),
                        ),
                      )
                    : Container(
                        color: Colors.grey[800],
                        child: const Icon(Icons.album, size: 24, color: Colors.white38),
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
                      color: isPlaying ? const Color(0xFF1DB954) : Colors.white,
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
                child: Icon(Icons.volume_up, color: Color(0xFF1DB954), size: 18),
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
                  : const Icon(Icons.add_circle_outline, color: Colors.white54, size: 24),
            ),
          ],
        ),
      ),
    );
  }
}

/// 保存タブの行データ。投稿ベース or 楽曲ベースのどちらか一方が入る。
class _SavedEntry {
  final DateTime savedAt;
  final PostModel? post;
  final TrackModel? track;
  _SavedEntry({required this.savedAt, this.post, this.track});
}

/// フォロー中アーティストのアバター(56×56, 円形)。
///
/// - artist.imageUrl があれば直接表示(Firestore に保存済み = 本人と断定できたもの)
/// - 無ければ表示時に Spotify 名前検索で都度取得(セッション内キャッシュあり)
/// - 名前検索の結果は関連アーティストにヒットする可能性があるため Firestore には保存しない
///   (次回起動時にまた取得しなおす)
class _FollowedArtistAvatar extends StatefulWidget {
  final ArtistModel artist;
  const _FollowedArtistAvatar({required this.artist});

  @override
  State<_FollowedArtistAvatar> createState() => _FollowedArtistAvatarState();
}

class _FollowedArtistAvatarState extends State<_FollowedArtistAvatar> {
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
                errorWidget: (_, __, ___) => const _ArtistAvatarPlaceholder(),
              )
            : const _ArtistAvatarPlaceholder(),
      ),
    );
  }
}

class _ArtistAvatarPlaceholder extends StatelessWidget {
  const _ArtistAvatarPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF2A2A2A),
      alignment: Alignment.center,
      child: const Icon(Icons.person, color: Colors.white38, size: 26),
    );
  }
}
