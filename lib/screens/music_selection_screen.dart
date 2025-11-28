import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/track_model.dart';
import 'post_preview_screen.dart';

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

  // 表示モード: true = グリッド, false = リスト
  bool _isGridView = false;

  // カテゴリー選択状態: null = 未選択, 'vibe' = Vibe, 'emotion' = 感情
  String? _selectedCategoryType;

  // 選択されたVibeカテゴリー（例: 「ドライブで聴きたい曲」）
  String? _selectedVibeCategory;

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

    // 投稿プレビュー画面へ遷移
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostPreviewScreen(track: _selectedTrack!),
      ),
    );
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

            // Vibe/感情選択ボタン
            _buildCategoryButtons(),

            // タブバー
            _buildTabBar(),

            // 区切り線
            Container(
              height: 1,
              color: const Color(0xFF2D2D2D),
            ),

            // 楽曲リスト or グリッド
            Expanded(
              child: _isGridView ? _buildTrackGrid() : _buildTrackList(),
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
              isSelected: _selectedCategoryType == 'vibe',
              onTap: () {
                setState(() {
                  _selectedCategoryType = 'vibe';
                  _selectedVibeCategory = 'ドライブで聴きたい曲';
                });
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
              isSelected: _selectedCategoryType == 'emotion',
              onTap: () {
                setState(() {
                  _selectedCategoryType = 'emotion';
                  _selectedVibeCategory = null;
                });
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
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            height: 70,
            width:  210,
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
          // チェックマークオーバーレイ
          if (isSelected)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
        ],
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
          // グリッド/リスト切り替えボタン
          GestureDetector(
            onTap: () => setState(() => _isGridView = !_isGridView),
            child: SvgPicture.asset(
              'assets/icons/grid.svg',
              width: 25,
              height: 25,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
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

  /// 楽曲グリッド
  Widget _buildTrackGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: _tracks.length,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        final isSelected = _selectedTrack?.trackId == track.trackId;

        return _buildGridTrackItem(track, isSelected);
      },
    );
  }

  /// 楽曲アイテム（リスト表示用）
  Widget _buildTrackItem(TrackModel track, bool isSelected) {
    return GestureDetector(
      onTap: () => _toggleTrackSelection(track),
      child: Container(
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
            Container(
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
          ],
        ),
      ),
    );
  }

  /// 楽曲アイテム（グリッド表示用）
  Widget _buildGridTrackItem(TrackModel track, bool isSelected) {
    return GestureDetector(
      onTap: () => _toggleTrackSelection(track),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // アルバムアート
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: track.albumImageUrl != null
                      ? Image.network(
                          track.albumImageUrl!,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildGridPlaceholderImage();
                          },
                        )
                      : _buildGridPlaceholderImage(),
                ),
                // 選択インジケーター
                if (isSelected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // 楽曲名
          Text(
            track.trackName,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // アーティスト名
          Text(
            track.artistName,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF9F9F9F),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// プレースホルダー画像（リスト用）
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

  /// プレースホルダー画像（グリッド用）
  Widget _buildGridPlaceholderImage() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Icon(
        Icons.music_note,
        color: Color(0xFF9F9F9F),
        size: 40,
      ),
    );
  }
}
