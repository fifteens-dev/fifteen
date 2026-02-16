import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 投稿プレビュー用の共通ウィジェット集
/// リアクションボタン、波形表示など

/// 波形表示ウィジェット
class WaveformWidget extends StatelessWidget {
  final String seed; // 波形生成用のシード（例: trackId）
  final double width;
  final double height;
  final Color color;

  const WaveformWidget({
    super.key,
    required this.seed,
    this.width = 327,
    this.height = 32,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final random = Random(seed.hashCode);
    const barWidth = 2.5;
    const barMargin = 1.2 * 2;
    const totalBarWidth = barWidth + barMargin;
    final barCount = (width / totalBarWidth).floor();

    return SizedBox(
      width: width,
      height: height,
      child: Row(
        children: List.generate(barCount, (index) {
          final normalizedIndex = index / (barCount - 1).toDouble();
          final angle = -pi / 4 + normalizedIndex * 1.5 * pi;
          final waveValue = sin(angle).abs();
          final baseHeight = 0.3 + waveValue * 0.7;
          final randomVariation = (random.nextDouble() - 0.5) * 6;
          final barHeight = 15.0 + (baseHeight * 17.0) + randomVariation;

          return Container(
            width: barWidth,
            height: barHeight.clamp(10.0, height),
            margin: const EdgeInsets.symmetric(horizontal: 1.2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

/// リアクションボタン（プレビューモード用・カウント非表示）
class PreviewReactionButtons extends StatelessWidget {
  final Color iconColor;
  final bool showCounts; // カウントを表示するか（プレビューではfalse）

  const PreviewReactionButtons({
    super.key,
    this.iconColor = Colors.white,
    this.showCounts = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // いいね
        Icon(
          Icons.favorite_border,
          size: 25,
          color: iconColor,
        ),
        const SizedBox(width: 12),
        // コメント
        SvgPicture.asset(
          'assets/icons/message_circle.svg',
          width: 25,
          height: 25,
          colorFilter: ColorFilter.mode(
            iconColor,
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: 12),
        // 追加ボタン
        Container(
          width: 23,
          height: 23,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: iconColor, width: 1),
          ),
          child: Icon(
            Icons.add,
            color: iconColor,
            size: 14,
          ),
        ),
      ],
    );
  }
}

/// いいねした人のアバター表示
class LikedAvatarsWidget extends StatelessWidget {
  final int count; // 表示するアバターの数
  final double size;
  final Color borderColor;

  const LikedAvatarsWidget({
    super.key,
    this.count = 3,
    this.size = 25,
    this.borderColor = const Color(0xFF030303),
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (index) {
        return Container(
          width: size,
          height: size,
          margin: EdgeInsets.only(left: index > 0 ? 4 : 0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF9F9F9F),
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
          ),
          child: const Icon(
            Icons.person,
            size: 14,
            color: Colors.white,
          ),
        );
      }),
    );
  }
}

/// コメント入力欄（プレビュー用）
class CommentInputPreview extends StatelessWidget {
  final double width;
  final double height;
  final Color backgroundColor;
  final Color textColor;
  final Color iconColor;

  const CommentInputPreview({
    super.key,
    this.width = 338,
    this.height = 43,
    this.backgroundColor = const Color(0xFF313131),
    this.textColor = Colors.white,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Text(
            'コメントする',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: textColor,
              fontFamily: 'Noto Sans',
              fontFamilyFallback: const ['Noto Sans JP'],
            ),
          ),
          const Spacer(),
          Icon(
            Icons.send,
            size: 20,
            color: iconColor.withOpacity(0.7),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// ユーザー情報表示（プレビュー用）
class UserInfoPreview extends StatelessWidget {
  final String username;
  final String? hashtag;
  final String? userIconUrl;

  const UserInfoPreview({
    super.key,
    required this.username,
    this.hashtag,
    this.userIconUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // アバター
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF9F9F9F),
          ),
          child: userIconUrl != null && userIconUrl!.isNotEmpty
              ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: userIconUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) {
                      return const Icon(
                        Icons.person,
                        size: 20,
                        color: Colors.white,
                      );
                    },
                  ),
                )
              : const Icon(
                  Icons.person,
                  size: 20,
                  color: Colors.white,
                ),
        ),
        const SizedBox(width: 9),
        // ユーザー名とハッシュタグ
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              username,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFamily: 'Noto Sans',
                fontFamilyFallback: ['Noto Sans JP'],
                letterSpacing: -0.12,
              ),
            ),
            if (hashtag != null) ...[
              const SizedBox(height: 2),
              Text(
                hashtag!,
                style: const TextStyle(
                  fontSize: 8,
                  color: Colors.white,
                  fontFamily: 'Noto Sans',
                  fontFamilyFallback: ['Noto Sans JP'],
                  letterSpacing: -0.08,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
