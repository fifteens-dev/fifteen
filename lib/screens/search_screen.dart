import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/user_service.dart';
import '../models/user_model.dart';
import '../widgets/profile_widgets.dart';
import 'other_user_profile_screen.dart';

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
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 検索状態管理
  List<UserModel> _searchResults = [];
  bool _isSearching = false;
  bool _isFocused = false;
  String _currentQuery = '';
  Timer? _debounceTimer;

  // 最近の検索履歴
  List<Map<String, String>> _recentSearches = [];

  // 招待コード
  String? _inviteCode;
  int _inviteUsedCount = 0;
  static const int _maxInvites = 3;
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
      final code = await _userService.ensureInviteCode(uid);
      final used = await _userService.getInviteCodeUsedCount(code);
      final user = await _userService.getUser(uid);
      if (mounted) {
        setState(() {
          _inviteCode = code;
          _inviteUsedCount = used;
          _currentUserProfileImageUrl = user?.profileImageUrl;
        });
      }
    } catch (_) {}
  }

  void _copyInviteCode() {
    if (_inviteCode == null) return;
    Clipboard.setData(ClipboardData(text: _inviteCode!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('招待コードをコピーしました'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF4CAF50),
      ),
    );
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
        _searchResults = [];
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
      final results = await _userService.searchUsers(
        query: trimmedQuery,
        limit: 20,
      );

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      print('Search error: $e');
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('検索中にエラーが発生しました'),
            backgroundColor: Color(0xFFDC3545),
          ),
        );
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
      _searchResults = [];
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
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Center(
        child: Text(
          '15s',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// 検索バー
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          // 検索フィールド
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 11),
                  const Icon(
                    Icons.search,
                    color: Color(0xFF9F9F9F),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        hintText: '検索',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9F9F9F),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 6),
                      ),
                      onChanged: (value) {
                        _onSearchChanged(value);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // キャンセルボタン（フォーカス時のみ表示）
          if (_isFocused)
            GestureDetector(
              onTap: _onCancel,
              child: const Padding(
                padding: EdgeInsets.only(left: 10, right: 4),
                child: Text(
                  'キャンセル',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF99999B),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 招待コードカード（BeReal風コンパクトレイアウト）
  Widget _buildInviteCodeCard() {
    final isExhausted = _inviteUsedCount >= _maxInvites;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF282828),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _inviteCode == null || isExhausted ? null : _copyInviteCode,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: _inviteCode == null
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
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
                              Text(
                                isExhausted ? '招待枠が上限に達しました' : '友達を招待する',
                                style: TextStyle(
                                  color: isExhausted ? Colors.grey : Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isExhausted
                                    ? '残り0人'
                                    : '招待コード: ${_inviteCode!}　残り${_maxInvites - _inviteUsedCount}人',
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
                          color: isExhausted ? Colors.grey[600] : Colors.white,
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

  /// メインコンテンツ
  Widget _buildContent() {
    // 未フォーカス時は空表示
    if (!_isFocused && _currentQuery.isEmpty) {
      return const SizedBox.shrink();
    }

    // ローディング中
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2,
        ),
      );
    }

    // フォーカス中でクエリが空 → 最近の検索を表示
    if (_currentQuery.isEmpty) {
      return _buildRecentSearches();
    }

    // 検索結果が0件の場合
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.search_off,
              size: 64,
              color: Color(0xFF9F9F9F),
            ),
            const SizedBox(height: 16),
            Text(
              '"$_currentQuery" に一致するユーザーが見つかりませんでした',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF9F9F9F),
              ),
            ),
          ],
        ),
      );
    }

    // 検索結果リスト
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        return _buildUserListItem(_searchResults[index]);
      },
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
              fontSize: 14,
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[800],
              ),
              child: ClipOval(
                child: ProfileImage(
                  imageUrl: (entry['profileImageUrl']?.isNotEmpty == true)
                      ? entry['profileImageUrl']
                      : null,
                  size: 44,
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
                        color: Color(0xFF9F9F9F),
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
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            // プロフィール画像
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[800],
              ),
              child: ClipOval(
                child: ProfileImage(
                  imageUrl: user.profileImageUrl,
                  size: 44,
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
                  const SizedBox(height: 2),

                  // displayName
                  if (user.name != null && user.name!.isNotEmpty)
                    Text(
                      user.name!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9F9F9F),
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
