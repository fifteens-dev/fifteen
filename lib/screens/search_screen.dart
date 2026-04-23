import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/user_service.dart';
import '../services/post_service.dart';
import '../models/user_model.dart';
import '../widgets/profile_widgets.dart';
import '../widgets/common/common.dart';
import 'other_user_profile_screen.dart';
import '../widgets/common/app_toast.dart';
import 'vibe_history_screen.dart';
import 'campus_vibe_history_screen.dart';
import 'vibe_posts_list_screen.dart';

/// 検索画面
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

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

  // デバウンス時間（ミリ秒）
  static const int _debounceDuration = 500;
  static const String _recentSearchesKey = 'recent_searches';

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onFocusChanged);
    _loadRecentSearches();
    _loadInviteCode();
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

            // 招待コードカード（未フォーカス時のみ表示）
            if (!_isFocused && _currentQuery.isEmpty)
              _buildInviteCodeCard(),

            // 過去のVibe・CampusVibeカード（未フォーカス時のみ表示）
            if (!_isFocused && _currentQuery.isEmpty) ...[
              _buildVibeHistoryCard(),
              _buildCampusVibeHistoryCard(),
            ],

            // メインコンテンツエリア
            Expanded(
              child: _buildContent(),
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
      child: Center(
        child: Transform.translate(
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

  /// 過去のVibeを見るカード
  Widget _buildVibeHistoryCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
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
              MaterialPageRoute(builder: (_) => const VibeHistoryScreen()),
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
                    child: const Icon(Icons.history, color: Colors.white70, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '過去のVibeを見る',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '過去のお題と投稿を振り返る',
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
        // Vibeお題結果
        if (_topicResults.isNotEmpty) ...[
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
    final currentUserId = _auth.currentUser?.uid ?? '';
    final dateLabel = '${topic.date.month}月${topic.date.day}日';
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VibePostsListScreen(
              title: '$dateLabel ${topic.topicTitle}',
              currentUserId: currentUserId,
              fetchPosts: () => _postService.getVibePostsByTopicAndDate(
                topic.topicId,
                topic.date,
              ),
            ),
          ),
        );
      },
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
