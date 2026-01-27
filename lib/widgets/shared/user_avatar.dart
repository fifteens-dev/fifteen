import 'package:flutter/material.dart';
import '../../constants/post_card_constants.dart';

/// ユーザーアバターのサイズ
enum UserAvatarSize {
  /// 小サイズ (25px) - 保存ユーザー表示など
  small,

  /// 中サイズ (32px) - カード内ユーザー情報
  medium,

  /// 大サイズ (40px) - プロフィール画面など
  large,
}

/// 共有ユーザーアバターウィジェット
/// プロフィール画像を丸く表示する
class UserAvatar extends StatelessWidget {
  /// プロフィール画像のURL
  final String? imageUrl;

  /// アバターのサイズ
  final UserAvatarSize size;

  /// カスタムサイズ（指定した場合はsizeを無視）
  final double? customSize;

  /// 背景色（画像がない場合）
  final Color backgroundColor;

  /// タップ時のコールバック
  final VoidCallback? onTap;

  /// ボーダーの色（nullの場合はボーダーなし）
  final Color? borderColor;

  /// ボーダーの太さ
  final double borderWidth;

  const UserAvatar({
    super.key,
    this.imageUrl,
    this.size = UserAvatarSize.medium,
    this.customSize,
    this.backgroundColor = const Color(0xFF9F9F9F),
    this.onTap,
    this.borderColor,
    this.borderWidth = 1.0,
  });

  double get _size {
    if (customSize != null) return customSize!;
    switch (size) {
      case UserAvatarSize.small:
        return AvatarSizes.small;
      case UserAvatarSize.medium:
        return AvatarSizes.medium;
      case UserAvatarSize.large:
        return AvatarSizes.large;
    }
  }

  double get _iconSize {
    switch (size) {
      case UserAvatarSize.small:
        return 14;
      case UserAvatarSize.medium:
        return 18;
      case UserAvatarSize.large:
        return 24;
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarSize = _size;

    Widget avatar = Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        border: borderColor != null
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? Image.network(
                imageUrl!,
                width: avatarSize,
                height: avatarSize,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
              )
            : _buildPlaceholder(),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: avatar,
      );
    }

    return avatar;
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Icon(
        Icons.person,
        size: _iconSize,
        color: Colors.white,
      ),
    );
  }
}

/// 複数のユーザーアバターを重ねて表示するウィジェット
class StackedUserAvatars extends StatelessWidget {
  /// ユーザー画像URLのリスト
  final List<String?> imageUrls;

  /// アバターのサイズ
  final UserAvatarSize size;

  /// 最大表示数
  final int maxDisplay;

  /// 重なりのオフセット
  final double overlap;

  /// タップ時のコールバック（ユーザーIDのインデックスを返す）
  final void Function(int index)? onTap;

  const StackedUserAvatars({
    super.key,
    required this.imageUrls,
    this.size = UserAvatarSize.small,
    this.maxDisplay = 3,
    this.overlap = 4.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayCount = imageUrls.length > maxDisplay ? maxDisplay : imageUrls.length;

    if (displayCount == 0) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(displayCount, (index) {
        return Padding(
          padding: EdgeInsets.only(left: index > 0 ? overlap : 0),
          child: UserAvatar(
            imageUrl: imageUrls[index],
            size: size,
            onTap: onTap != null ? () => onTap!(index) : null,
          ),
        );
      }),
    );
  }
}
