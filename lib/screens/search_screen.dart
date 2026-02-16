import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
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
  final UserService _userService = UserService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 検索状態管理
  List<UserModel> _searchResults = [];
  bool _isSearching = false;
  String _currentQuery = '';
  Timer? _debounceTimer;

  // デバウンス時間（ミリ秒）
  static const int _debounceDuration = 500;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
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
      print('❌ Search error: $e');
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
              height: 30,
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
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
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
          // キャンセルボタン
          GestureDetector(
            onTap: () {
              _searchController.clear();
              _onSearchChanged('');
              FocusScope.of(context).unfocus();
            },
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

  /// メインコンテンツ
  Widget _buildContent() {
    // ローディング中
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2,
        ),
      );
    }

    // 検索クエリが空の場合
    if (_currentQuery.isEmpty) {
      return const Center(
        child: Text(
          '検索してユーザーを見つけましょう',
          style: TextStyle(
            fontSize: 16,
            color: Color(0xFF9F9F9F),
          ),
        ),
      );
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

  /// ユーザーリストアイテム
  Widget _buildUserListItem(UserModel user) {
    final currentUserId = _auth.currentUser?.uid;
    final isCurrentUser = currentUserId == user.uid;

    return InkWell(
      onTap: () {
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
