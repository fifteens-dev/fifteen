import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../constants/campus_vibe_constants.dart';
import '../screens/campus_vibe_screen.dart';
import '../services/post_service.dart';
import '../services/wikipedia_image_service.dart';
import '../utils/university_colors.dart';

/// Campus Vibe バナーカード
/// ホームタイムラインの VibeBar 直下に表示（金土日のみ）
class CampusVibeCard extends StatefulWidget {
  final String university;
  final String currentUserId;

  const CampusVibeCard({
    super.key,
    required this.university,
    required this.currentUserId,
  });

  @override
  State<CampusVibeCard> createState() => _CampusVibeCardState();
}

class _CampusVibeCardState extends State<CampusVibeCard> {
  String? _imageUrl;
  late Stream<int> _countStream;

  @override
  void initState() {
    super.initState();
    _countStream = PostService().streamCampusVibePostCount(widget.university);
    _fetchImage();
  }

  @override
  void didUpdateWidget(CampusVibeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.university != widget.university) {
      _countStream = PostService().streamCampusVibePostCount(widget.university);
      _fetchImage();
    }
  }

  Future<void> _fetchImage() async {
    final url =
        await WikipediaImageService.fetchUniversityImageUrl(widget.university);
    if (mounted) setState(() => _imageUrl = url);
  }

  void _navigateToCampusVibe(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CampusVibeScreen(
          university: widget.university,
          currentUserId: widget.currentUserId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = UniversityColors.gradientFor(widget.university);

    return SizedBox(
      height: CampusVibeConstants.cardHeight,
      child: GestureDetector(
        onTap: () => _navigateToCampusVibe(context),
        child: StreamBuilder<int>(
          stream: _countStream,
          initialData: 0,
          builder: (context, snapshot) {
            final postCount = snapshot.data ?? 0;
            return _CardLayout(
              university: widget.university,
              gradientColors: gradientColors,
              imageUrl: _imageUrl,
              postCount: postCount,
            );
          },
        ),
      ),
    );
  }
}

/// カードのレイアウトを担う内部ウィジェット
/// StreamBuilder の再ビルドスコープを最小化するため分離
class _CardLayout extends StatelessWidget {
  final String university;
  final List<Color> gradientColors;
  final String? imageUrl;
  final int postCount;

  const _CardLayout({
    required this.university,
    required this.gradientColors,
    required this.imageUrl,
    required this.postCount,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageWidth = constraints.maxWidth - CampusVibeConstants.imageLeft;

        return Container(
          // 高さを明示して Stack の Positioned(bottom:0) を確実に動作させる
          height: CampusVibeConstants.cardHeight,
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(CampusVibeConstants.cardRadius),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: gradientColors,
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              // 大学画像（半透明）
              Positioned(
                left: CampusVibeConstants.imageLeft,
                top: 0,
                bottom: 0,
                width: imageWidth,
                child: imageUrl != null
                    ? Opacity(
                        opacity: 0.45,
                        child: CachedNetworkImage(
                          imageUrl: imageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const SizedBox(),
                        ),
                      )
                    : const SizedBox(),
              ),

              // 画像左縁フェードマスク
              Positioned(
                left: CampusVibeConstants.imageLeft,
                top: 0,
                bottom: 0,
                width: CampusVibeConstants.imageFadeWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        gradientColors[0],
                        gradientColors[0].withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),

              // テキスト群
              Padding(
                padding: const EdgeInsets.only(
                    left: CampusVibeConstants.leftPad, top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ラベル行
                    const Row(
                      children: [
                        Text('🔥', style: TextStyle(fontSize: 13)),
                        SizedBox(width: 4),
                        Text(
                          'Campus Vibe',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // 大学名
                    Text(
                      university,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),

                    // 投稿人数（リアルタイム）
                    Text(
                      '$postCount人が投稿',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 「今週末を見る」ボタン
                    Container(
                      height: CampusVibeConstants.buttonHeight,
                      width: CampusVibeConstants.buttonWidth,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.66),
                        borderRadius: BorderRadius.circular(
                            CampusVibeConstants.buttonRadius),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      child: const Row(
                        children: [
                          Expanded(
                            child: Text(
                              '今週末のCampus Vibeを見る',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right, color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
