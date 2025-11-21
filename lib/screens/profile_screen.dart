import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';
import 'settings_screen.dart';

/// プロフィール画面（自分）
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _selectedTabIndex = 0; // 0: グリッド, 1: 保存

  // ダミーデータ
  final String _displayName = '後藤 太郎';
  final String _username = 'taroooooda';
  final int _tracksCount = 18;
  final int _followersCount = 87;
  final int _followingCount = 89;

  // ダミーの投稿データ
  final List<Map<String, String>> _posts = [
    {
      'trackName': 'Miss Luxury',
      'artistName': 'YZERR, LANA, JP THE WAVY, ¥ellow Bucks',
      'albumArt': '',
    },
    {
      'trackName': 'High Land(feat. Tiji Jojo, Vingo & YZERR)',
      'artistName': 'BAD HOP, Tiji Jojo, Vingo, YZERR',
      'albumArt': '',
    },
    {
      'trackName': 'かわいいだけじゃダメですか',
      'artistName': 'CUTIE STREET',
      'albumArt': '',
    },
    {
      'trackName': 'ヒロイン',
      'artistName': 'back number',
      'albumArt': '',
    },
    {
      'trackName': '愛のかたまり',
      'artistName': 'Kinki Kids',
      'albumArt': '',
    },
    {
      'trackName': 'ラブホテル',
      'artistName': 'クリープハイプ',
      'albumArt': '',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            _buildHeader(),

            // メインコンテンツ
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // プロフィール情報
                    _buildProfileInfo(),

                    // 今日の楽曲カード
                    _buildTodaysTrack(),

                    const SizedBox(height: 16),

                    // タブ切り替え
                    _buildTabSelector(),

                    // 投稿グリッド
                    _buildPostsGrid(),
                  ],
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
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 戻るボタン
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          // ユーザーID
          Text(
            _username,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          // 設定アイコン
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  /// プロフィール情報セクション
  Widget _buildProfileInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 27, vertical: 16),
      child: Column(
        children: [
          // ユーザー情報行
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左側: 名前とユーザーID
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'aoyama',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // 右側: プロフィール画像
              Container(
                width: 65,
                height: 65,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[800],
                ),
                child: ClipOval(
                  child: Icon(
                    Icons.person,
                    size: 40,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 統計情報
          Row(
            children: [
              _buildStatItem('$_tracksCount', 'Tracks'),
              const SizedBox(width: 32),
              _buildStatItem('$_followersCount', 'Followers'),
              const SizedBox(width: 32),
              _buildStatItem('$_followingCount', 'Following'),
            ],
          ),
        ],
      ),
    );
  }

  /// 統計アイテム
  Widget _buildStatItem(String count, String label) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF919191),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// 今日の楽曲カード
  Widget _buildTodaysTrack() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF3C3C3C)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ラベル
            const Padding(
              padding: EdgeInsets.only(left: 8, top: 2, bottom: 8),
              child: Text(
                '今日の楽曲',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                ),
              ),
            ),
            // 楽曲情報
            Row(
              children: [
                // アルバムアート
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Icon(
                    Icons.album,
                    size: 40,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(width: 14),
                // 曲名とアーティスト
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'いとしのエリー',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'サザンオールスターズ',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                // 再生ボタンと時間
                Column(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '0:15',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// タブ切り替え
  Widget _buildTabSelector() {
    return Container(
      height: 40,
      child: Row(
        children: [
          // グリッドタブ
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTabIndex = 0),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _selectedTabIndex == 0 ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Icon(
                  Icons.grid_view,
                  color: _selectedTabIndex == 0 ? Colors.white : Colors.grey,
                  size: 24,
                ),
              ),
            ),
          ),
          // 保存タブ
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTabIndex = 1),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _selectedTabIndex == 1 ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _selectedTabIndex == 1 ? Colors.white : Colors.grey,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.add,
                    color: _selectedTabIndex == 1 ? Colors.white : Colors.grey,
                    size: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 投稿グリッド
  Widget _buildPostsGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 131 / 185,
        crossAxisSpacing: 0,
        mainAxisSpacing: 5,
      ),
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        final post = _posts[index];
        return _buildPostItem(post);
      },
    );
  }

  /// 投稿アイテム
  Widget _buildPostItem(Map<String, String> post) {
    return Container(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // アルバムアート
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              margin: const EdgeInsets.all(0.5),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Icon(
                Icons.album,
                size: 50,
                color: Colors.white54,
              ),
            ),
          ),
          // 曲名
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 4),
            child: Text(
              post['trackName'] ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // アーティスト名
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              post['artistName'] ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 追加ボタン
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 2),
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: const Icon(
                Icons.add,
                color: Colors.white,
                size: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
