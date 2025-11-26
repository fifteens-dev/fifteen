import 'package:flutter/material.dart';
import '../models/track_model.dart';

/// 投稿用楽曲選択画面
class MusicSelectionScreen extends StatefulWidget {
  const MusicSelectionScreen({super.key});

  @override
  State<MusicSelectionScreen> createState() => _MusicSelectionScreenState();
}

class _MusicSelectionScreenState extends State<MusicSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();

  // 選択された楽曲
  TrackModel? _selectedTrack;

  // タブ選択状態: 0 = My Playlist, 1 = 保存済み
  int _selectedTab = 0;

  // テスト用楽曲リスト
  final List<TrackModel> _tracks = [
    TrackModel(
      trackId: '1',
      trackName: '白い恋人達',
      artistName: '桑田圭介',
      albumImageUrl: 'https://via.placeholder.com/47',
    ),
    TrackModel(
      trackId: '2',
      trackName: 'かわいいだけじゃダメですか？',
      artistName: 'CUTIE STREET',
      albumImageUrl: 'https://via.placeholder.com/47',
    ),
    TrackModel(
      trackId: '3',
      trackName: 'ケセラセラ',
      artistName: 'Mrs. Green Apple',
      albumImageUrl: 'https://via.placeholder.com/47',
    ),
    TrackModel(
      trackId: '4',
      trackName: 'いとしのエリー',
      artistName: 'サザンオールスターズ',
      albumImageUrl: 'https://via.placeholder.com/47',
    ),
    TrackModel(
      trackId: '5',
      trackName: 'さよならエレジー',
      artistName: '菅田将暉',
      albumImageUrl: 'https://via.placeholder.com/47',
    ),
    TrackModel(
      trackId: '6',
      trackName: 'ドライフラワー',
      artistName: '優里',
      albumImageUrl: 'https://via.placeholder.com/47',
    ),
    TrackModel(
      trackId: '7',
      trackName: '怪獣の花唄',
      artistName: 'Vaundy',
      albumImageUrl: 'https://via.placeholder.com/47',
    ),
    TrackModel(
      trackId: '8',
      trackName: '残酷な天使のテーゼ',
      artistName: '高橋洋子',
      albumImageUrl: 'https://via.placeholder.com/47',
    ),
    TrackModel(
      trackId: '9',
      trackName: 'LAST PARTY',
      artistName: 'BAD HOP',
      albumImageUrl: 'https://via.placeholder.com/47',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 楽曲を選択
  void _toggleTrackSelection(TrackModel track) {
    setState(() {
      if (_selectedTrack?.trackId == track.trackId) {
        _selectedTrack = null;
      } else {
        _selectedTrack = track;
      }
    });
  }

  /// 次へ進む
  void _onNext() {
    if (_selectedTrack == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('楽曲を選択してください'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
      return;
    }

    // TODO: 次の画面へ遷移（感情選択画面など）
    Navigator.pop(context, _selectedTrack);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Stack(
          children: [
            // メインコンテンツ
            Column(
              children: [
                // ヘッダー
                _buildHeader(),

                // Vibe/感情選択ボタン
                _buildCategoryButtons(),

                // 検索バー
                _buildSearchBar(),

                // タブバー
                _buildTabBar(),

                // 区切り線
                Container(
                  height: 1,
                  color: const Color(0xFF2D2D2D),
                ),

                // 楽曲リスト
                Expanded(
                  child: _buildTrackList(),
                ),
              ],
            ),

            // 半透明オーバーレイ（必要に応じて）
            // TODO: Vibe/感情選択時に表示
          ],
        ),
      ),
    );
  }

  /// ヘッダー
  Widget _buildHeader() {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 19),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 戻るボタン
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.close,
              color: Colors.white,
              size: 20,
            ),
          ),

          // タイトル
          const Text(
            '新規投稿',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),

          // 次へボタン
          GestureDetector(
            onTap: _selectedTrack != null ? _onNext : null,
            child: Text(
              '次へ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _selectedTrack != null
                    ? const Color(0xFF5D8FFF)
                    : const Color(0xFF5B5B5B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Vibe/感情選択ボタン
  Widget _buildCategoryButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 23, vertical: 16),
      child: Row(
        children: [
          // Vibeボタン
          Expanded(
            child: _buildCategoryButtonWithImage(
              imagePath: 'assets/icons/Vibe.png',
              label: 'Vibe',
              subtitle: '【ドライブで聴きたい曲】',
              onTap: () {
                // TODO: Vibe選択画面を表示
              },
            ),
          ),
          const SizedBox(width: 7),
          // 感情選択ボタン
          Expanded(
            child: _buildCategoryButtonWithImage(
              imagePath: 'assets/icons/emotion.png',
              label: '感情で音楽を選ぶ',
              subtitle: null,
              onTap: () {
                // TODO: 感情選択画面を表示
              },
            ),
          ),
        ],
      ),
    );
  }

  /// カテゴリーボタン（画像版）
  Widget _buildCategoryButtonWithImage({
    required String imagePath,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: const Color(0xFF202020),
          border: Border.all(
            color: const Color(0xFF4C4C4C),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              imagePath,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.music_note,
                  color: Colors.white,
                  size: 24,
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 8,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// カテゴリーボタン
  Widget _buildCategoryButton({
    required IconData icon,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: const Color(0xFF202020),
          border: Border.all(
            color: const Color(0xFF4C4C4C),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 8,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 検索バー
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            const SizedBox(width: 13),
            const Icon(
              Icons.search,
              color: Color(0xFF9F9F9F),
              size: 20,
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
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (value) {
                  // TODO: 検索機能を実装
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// タブバー
  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.only(left: 21, top: 11, bottom: 11, right: 21),
      child: Row(
        children: [
          // My Playlistタブ
          GestureDetector(
            onTap: () => setState(() => _selectedTab = 0),
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: _selectedTab == 0
                    ? Colors.white
                    : const Color(0xFF3A3A3A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  'My Playlist',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                    color: _selectedTab == 0
                        ? const Color(0xFF101010)
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 保存済みタブ
          GestureDetector(
            onTap: () => setState(() => _selectedTab = 1),
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 21),
              decoration: BoxDecoration(
                color: _selectedTab == 1
                    ? Colors.white
                    : const Color(0xFF3A3A3A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  '保存済み',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                    color: _selectedTab == 1
                        ? const Color(0xFF101010)
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          // グリッドアイコン
          const Icon(
            Icons.grid_view,
            color: Colors.white,
            size: 20,
          ),
        ],
      ),
    );
  }

  /// 楽曲リスト
  Widget _buildTrackList() {
    return ListView.builder(
      itemCount: _tracks.length,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        final isSelected = _selectedTrack?.trackId == track.trackId;

        return _buildTrackItem(track, isSelected);
      },
    );
  }

  /// 楽曲アイテム
  Widget _buildTrackItem(TrackModel track, bool isSelected) {
    return Container(
      height: 59,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // アルバムアート
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: track.albumImageUrl != null
                ? Image.network(
                    track.albumImageUrl!,
                    width: 47,
                    height: 47,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildPlaceholderImage();
                    },
                  )
                : _buildPlaceholderImage(),
          ),
          const SizedBox(width: 11),

          // 楽曲情報
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  track.trackName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  track.artistName,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // 選択ボタン
          GestureDetector(
            onTap: () => _toggleTrackSelection(track),
            child: Container(
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF4CAF50)
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFF9F9F9F),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 12,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  /// プレースホルダー画像
  Widget _buildPlaceholderImage() {
    return Container(
      width: 47,
      height: 47,
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Icon(
        Icons.music_note,
        color: Color(0xFF9F9F9F),
        size: 24,
      ),
    );
  }
}
