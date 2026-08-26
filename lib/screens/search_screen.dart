import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import '../services/user_service.dart';
import '../services/post_service.dart';
import '../models/user_model.dart';
import '../widgets/profile_widgets.dart';
import '../widgets/common/common.dart';
import 'other_user_profile_screen.dart';
import '../widgets/common/app_toast.dart';
import 'campus_vibe_history_screen.dart';
import 'vibe_playlist/vibe_playlist_screen.dart';
import '../models/vibe_topic_model.dart';

/// 検索画面
class SearchScreen extends StatefulWidget {
  /// 独立した画面として push された場合 true。ヘッダー左に戻るボタンを表示する。
  final bool showBackButton;

  const SearchScreen({super.key, this.showBackButton = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 検索状態管理
  List<UserModel> _userResults = [];
  List<({String topicTitle, String topicId, DateTime date, int count})> _topicResults = [];
  bool _isSearching = false;
  bool _isFocused = false;
  String _currentQuery = '';
  Timer? _debounceTimer;

  // 最近の検索履歴
  List<Map<String, String>> _recentSearches = [];

  // 招待コード
  String? _inviteCode;
  String? _currentUserProfileImageUrl;

  // Vibe セクション（Figma 3986:7761 仕様）
  List<({
    String topicTitle,
    String topicId,
    DateTime date,
    int count,
    List<String> thumbnails,
  })> _vibeTopics = [];

  // デバウンス時間（ミリ秒）
  static const int _debounceDuration = 500;
  static const String _recentSearchesKey = 'recent_searches';

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onFocusChanged);
    _loadRecentSearches();
    _loadInviteCode();
    _loadVibeTopics(randomize: true);
  }

  bool _vibeTopicsLoading = false;
  String? _loadingVibeTopicId;

  Future<void> _loadVibeTopics({bool randomize = false}) async {
    if (_vibeTopicsLoading) return;
    setState(() => _vibeTopicsLoading = true);
    try {
      final topics = await _postService.getVibeTopicsWithThumbnails(
        limit: randomize ? 6 : 20,
        minCount: randomize ? 2 : 1,
        randomize: randomize,
      );
      if (mounted) {
        setState(() => _vibeTopics = topics);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _vibeTopicsLoading = false);
    }
  }

  Future<void> _navigateToVibePlaylist({
    required String topicId,
    required String topicTitle,
    required DateTime date,
  }) async {
    if (_loadingVibeTopicId != null) return;
    setState(() => _loadingVibeTopicId = topicId);
    try {
      final now = DateTime.now();
      final topic = VibeTopicModel(
        topicId: topicId,
        title: topicTitle,
        date: date,
        createdAt: now,
        updatedAt: now,
      );
      final ranking = await _postService.calculateVibeRanking(topicId, date, limit: 1000);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VibePlaylistScreen(
            topic: topic,
            ranking: ranking,
            currentUserId: _auth.currentUser?.uid ?? '',
            hasPostedToday: false,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingVibeTopicId = null);
    }
  }

  Future<void> _loadInviteCode() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      // 招待コード取得とユーザー情報取得を並列実行
      final (code, user) = await (
        _userService.ensureInviteCode(uid),
        _userService.getUser(uid),
      ).wait;
      if (mounted) {
        setState(() {
          _inviteCode = code;
          _currentUserProfileImageUrl = user?.profileImageUrl;
        });
      }
    } catch (_) {}
  }

  void _copyInviteCode() {
    if (_inviteCode == null) return;
    Clipboard.setData(ClipboardData(text: _inviteCode!));
    showCopyBanner(context);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.removeListener(_onFocusChanged);
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _isFocused = _searchFocusNode.hasFocus;
    });
  }

  /// 最近の検索履歴を読み込み
  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_recentSearchesKey);
    if (data != null && mounted) {
      setState(() {
        _recentSearches = data
            .map((e) => Map<String, String>.from(jsonDecode(e)))
            .toList();
      });
    }
  }

  /// 最近の検索履歴に追加
  Future<void> _addToRecentSearches(UserModel user) async {
    final entry = {
      'uid': user.uid,
      'username': user.username ?? 'unknown',
      'name': user.name ?? '',
      'profileImageUrl': user.profileImageUrl ?? '',
    };

    // 既に存在する場合は削除して先頭に追加
    _recentSearches.removeWhere((e) => e['uid'] == user.uid);
    _recentSearches.insert(0, entry);

    // 最大10件まで保持
    if (_recentSearches.length > 10) {
      _recentSearches = _recentSearches.sublist(0, 10);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _recentSearchesKey,
      _recentSearches.map((e) => jsonEncode(e)).toList(),
    );

    if (mounted) setState(() {});
  }

  /// 最近の検索履歴から削除
  Future<void> _removeFromRecentSearches(String uid) async {
    _recentSearches.removeWhere((e) => e['uid'] == uid);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _recentSearchesKey,
      _recentSearches.map((e) => jsonEncode(e)).toList(),
    );

    if (mounted) setState(() {});
  }

  /// 検索を実行（デバウンス処理付き）
  void _onSearchChanged(String query) {
    // 既存のタイマーをキャンセル
    _debounceTimer?.cancel();

    // 新しいタイマーをセット
    _debounceTimer = Timer(
      const Duration(milliseconds: _debounceDuration),
      () => _performSearch(query),
    );
  }

  /// 実際の検索処理
  Future<void> _performSearch(String query) async {
    final trimmedQuery = query.trim();

    // 空のクエリの場合は結果をクリア
    if (trimmedQuery.isEmpty) {
      setState(() {
        _userResults = [];
        _topicResults = [];
        _isSearching = false;
        _currentQuery = '';
      });
      return;
    }

    // 同じクエリの場合はスキップ
    if (_currentQuery == trimmedQuery) {
      return;
    }

    setState(() {
      _isSearching = true;
      _currentQuery = trimmedQuery;
    });

    try {
      final results = await Future.wait([
        _userService.searchUsers(query: trimmedQuery, limit: 20),
        _postService.searchVibeTopics(trimmedQuery),
      ]);

      if (mounted) {
        setState(() {
          _userResults = results[0] as List<UserModel>;
          _topicResults = results[1] as List<({String topicTitle, String topicId, DateTime date, int count})>;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userResults = [];
          _topicResults = [];
          _isSearching = false;
        });
        AppToast.show(context, '検索中にエラーが発生しました');
      }
    }
  }

  /// キャンセルボタンのタップ処理
  void _onCancel() {
    _searchController.clear();
    _onSearchChanged('');
    _searchFocusNode.unfocus();
    setState(() {
      _currentQuery = '';
      _userResults = [];
      _topicResults = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            _buildHeader(),

            // 検索バー
            _buildSearchBar(),

            // メインコンテンツエリア
            Expanded(
              child: !_isFocused && _currentQuery.isEmpty
                  ? CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        CupertinoSliverRefreshControl(
                          onRefresh: () async {
                            final refreshStart = DateTime.now();
                            await _loadVibeTopics(randomize: true);
                            final elapsed = DateTime.now().difference(refreshStart);
                            if (elapsed < const Duration(seconds: 1)) {
                              await Future.delayed(const Duration(seconds: 1) - elapsed);
                            }
                          },
                        ),
                        SliverToBoxAdapter(child: _buildInviteCodeCard()),
                        // Vibe 機能は一時的に全面非表示（将来再利用のため温存）。
                        if (false && _vibeTopics.isNotEmpty)
                          SliverToBoxAdapter(child: _buildVibeSection()),
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: SizedBox.shrink(),
                        ),
                      ],
                    )
                  : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  /// ヘッダー
  Widget _buildHeader() {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: const Offset(0, -1),
              child: const Text(
                '15s',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            // 画面右端の閉じるボタン（push 表示時のみ）→ タップでホームへ戻る。
            if (widget.showBackButton)
              Positioned(
                right: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.close, color: Colors.white, size: 26),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 検索バー
  Widget _buildSearchBar() {
    return AppSearchBar(
      controller: _searchController,
      focusNode: _searchFocusNode,
      isFocused: _isFocused,
      onCancel: _onCancel,
      onChanged: (value) {
        _onSearchChanged(value);
        setState(() {});
      },
      showClearButton: true,
    );
  }

  /// 招待コードカード（BeReal風コンパクトレイアウト）
  Widget _buildInviteCodeCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF282828),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _inviteCode == null ? null : _copyInviteCode,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: _inviteCode == null
                  ? const Center(
                      child: CupertinoActivityIndicator(
                        color: Colors.white,
                        radius: 10,
                      ),
                    )
                  : Row(
                      children: [
                        // 左: ユーザーアバター
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[700],
                          ),
                          child: ClipOval(
                            child: ProfileImage(
                              imageUrl: _currentUserProfileImageUrl,
                              size: 40,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 中央: テキスト
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                '友達を招待する',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '招待コード: ${_inviteCode!}',
                                style: const TextStyle(
                                  color: Color(0xFF9F9F9F),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 右: コピーアイコン
                        Icon(
                          Icons.copy,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Vibeセクション（Figma 3986:7761）
  /// - 見出し「Vibe」 + Vibeアイコン
  /// - 横スクロールで個別 Vibe topic カードを表示
  Widget _buildVibeSection() {
    return SizedBox(
      height: 218,
      child: Stack(
        children: [
          // 見出し
          Positioned(
            left: 9,
            top: 2,
            right: 0,
            height: 40,
            child: Row(
              children: [
                Image.asset(
                  'assets/icons/Vibe.png',
                  width: 39.7,
                  height: 40,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.music_note, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 9),
                const Text(
                  'Vibe',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEFEFEF),
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
          // 横スクロールエリア（top=46, h=172）
          Positioned(
            left: 0,
            right: 0,
            top: 46,
            height: 172,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _vibeTopics.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                return _buildVibeCard(_vibeTopics[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Vibeカード（211×172: 写真コラージュ140 + ユーザーエリア24 + 余白）
  Widget _buildVibeCard(({
    String topicTitle,
    String topicId,
    DateTime date,
    int count,
    List<String> thumbnails,
  }) topic) {
    return GestureDetector(
      onTap: () => _navigateToVibePlaylist(
        topicId: topic.topicId,
        topicTitle: topic.topicTitle,
        date: topic.date,
      ),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 211,
        height: 172,
        child: Stack(
          children: [
            // 写真コラージュ（211×140 rounded=15）→ タップでVibeプレイリストへ
            Positioned(
              left: 0,
              top: 0,
              width: 211,
              height: 140,
              child: GestureDetector(
                onTap: () => _navigateToVibePlaylist(
                  topicId: topic.topicId,
                  topicTitle: topic.topicTitle,
                  date: topic.date,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildVibeCollage(topic.thumbnails),
                      if (_loadingVibeTopicId == topic.topicId)
                        Container(
                          color: Colors.black45,
                          child: const Center(
                            child: CupertinoActivityIndicator(
                              color: Colors.white,
                              radius: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // ユーザーエリア（top=142, h=24, left=3, w=171）
            Positioned(
              left: 3 + 9, // Figma: 内側で left=9 のため合算
              top: 142,
              right: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '#${topic.topicTitle}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: -0.11,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${topic.count}件の投稿',
                    style: const TextStyle(
                      fontSize: 7,
                      color: Color(0xFFA8A8A8),
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 4枚画像コラージュ（Figma仕様）
  /// - 左 70×140 / 中央 70×140 → 写真のみ（縦幅にフィット、横はクリップ）
  /// - 右上 70×70 / 右下 70×69 → アルバムアート（cover）
  /// 各スロットの URL が空文字 or 未指定の場合は灰色プレースホルダ
  Widget _buildVibeCollage(List<String> urls) {
    bool hasUrl(int i) => i < urls.length && urls[i].isNotEmpty;

    Widget photoCell(int i) {
      if (!hasUrl(i)) return Container(color: Colors.grey[850]);
      // 縦に等比拡大して縦幅いっぱいに表示、横はクリップ
      return ClipRect(
        child: SizedBox.expand(
          child: CachedNetworkImage(
            imageUrl: urls[i],
            fit: BoxFit.fitHeight,
            alignment: Alignment.center,
            width: double.infinity,
            height: double.infinity,
            errorWidget: (_, __, ___) => Container(color: Colors.grey[850]),
          ),
        ),
      );
    }

    Widget jacketCell(int i) {
      if (!hasUrl(i)) return Container(color: Colors.grey[850]);
      return SizedBox.expand(
        child: CachedNetworkImage(
          imageUrl: urls[i],
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorWidget: (_, __, ___) => Container(color: Colors.grey[850]),
        ),
      );
    }

    return Row(
      children: [
        // 左カラム 70（写真）
        Expanded(child: photoCell(0)),
        const SizedBox(width: 1),
        // 中央カラム 70（写真）
        Expanded(child: photoCell(1)),
        const SizedBox(width: 1),
        // 右カラム 70（アルバムアート 上下2分割）
        Expanded(
          child: Column(
            children: [
              Expanded(child: jacketCell(2)),
              const SizedBox(height: 1),
              Expanded(child: jacketCell(3)),
            ],
          ),
        ),
      ],
    );
  }

  /// 過去のCampusVibeを見るカード
  Widget _buildCampusVibeHistoryCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF282828),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CampusVibeHistoryScreen()),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A3A3A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.school_outlined, color: Colors.white70, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '過去のCampusVibeを見る',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '大学別・週末ごとのVibeを振り返る',
                          style: TextStyle(color: Color(0xFF9F9F9F), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// メインコンテンツ
  Widget _buildContent() {
    // 未フォーカス時は空表示
    if (!_isFocused && _currentQuery.isEmpty) {
      return const SizedBox.shrink();
    }

    // ローディング中
    if (_isSearching) {
      return const Center(
        child: CupertinoActivityIndicator(
          color: Colors.white,
          radius: 8,
        ),
      );
    }

    // フォーカス中でクエリが空 → 最近の検索を表示
    if (_currentQuery.isEmpty) {
      return _buildRecentSearches();
    }

    // 検索結果が0件の場合
    if (_userResults.isEmpty && _topicResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Color(0xFF9F9F9F)),
            const SizedBox(height: 16),
            Text(
              '"$_currentQuery" に一致する結果が見つかりませんでした',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Color(0xFF9F9F9F)),
            ),
          ],
        ),
      );
    }

    // 検索結果リスト（ユーザー + お題）
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // ユーザー結果
        if (_userResults.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              'ユーザー',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9F9F9F),
              ),
            ),
          ),
          ..._userResults.map(_buildUserListItem),
        ],
        // Vibeお題結果（Vibe 機能は一時的に全面非表示・将来再利用のため温存）
        if (false && _topicResults.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.only(top: _userResults.isNotEmpty ? 16 : 4, bottom: 8),
            child: const Text(
              'Vibeお題',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9F9F9F),
              ),
            ),
          ),
          ..._topicResults.map(_buildTopicListItem),
        ],
      ],
    );
  }

  /// 最近の検索履歴セクション
  Widget _buildRecentSearches() {
    if (_recentSearches.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 16, top: 12, bottom: 8),
          child: Text(
            '最近',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recentSearches.length,
            itemBuilder: (context, index) {
              final entry = _recentSearches[index];
              return _buildRecentSearchItem(entry);
            },
          ),
        ),
      ],
    );
  }

  /// 最近の検索アイテム
  Widget _buildRecentSearchItem(Map<String, String> entry) {
    return InkWell(
      onTap: () {
        final uid = entry['uid'] ?? '';
        final currentUserId = _auth.currentUser?.uid;
        if (uid == currentUserId) {
          Navigator.pushNamed(context, '/profile');
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OtherUserProfileScreen(userId: uid),
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // プロフィール画像
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[800],
              ),
              child: ClipOval(
                child: ProfileImage(
                  imageUrl: (entry['profileImageUrl']?.isNotEmpty == true)
                      ? entry['profileImageUrl']
                      : null,
                  size: 50,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // ユーザー情報
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry['username'] ?? 'unknown',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry['name']?.isNotEmpty == true)
                    Text(
                      entry['name']!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // 削除ボタン
            GestureDetector(
              onTap: () => _removeFromRecentSearches(entry['uid'] ?? ''),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: Color(0xFF9F9F9F),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Vibeお題検索結果アイテム
  Widget _buildTopicListItem(({String topicTitle, String topicId, DateTime date, int count}) topic) {
    final dateLabel = '${topic.date.month}月${topic.date.day}日';
    return InkWell(
      onTap: () => _navigateToVibePlaylist(
        topicId: topic.topicId,
        topicTitle: topic.topicTitle,
        date: topic.date,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.music_note, color: Colors.white54, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.topicTitle,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$dateLabel　${topic.count}件',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9F9F9F)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }

  /// ユーザーリストアイテム
  Widget _buildUserListItem(UserModel user) {
    final currentUserId = _auth.currentUser?.uid;
    final isCurrentUser = currentUserId == user.uid;

    return InkWell(
      onTap: () {
        // 最近の検索に追加
        _addToRecentSearches(user);

        // 自分自身の場合はプロフィール画面へ
        if (isCurrentUser) {
          Navigator.pushNamed(context, '/profile');
        } else {
          // 他ユーザーの場合はOtherUserProfileScreenへ
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OtherUserProfileScreen(
                userId: user.uid,
              ),
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // プロフィール画像
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[800],
              ),
              child: ClipOval(
                child: ProfileImage(
                  imageUrl: user.profileImageUrl,
                  size: 50,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // ユーザー情報
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // username
                  Text(
                    user.username ?? 'unknown',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // displayName
                  if (user.name != null && user.name!.isNotEmpty)
                    Text(
                      user.name!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // フォロワー数（オプション）
            if (user.followersCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${user.followersCount} フォロワー',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9F9F9F),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
