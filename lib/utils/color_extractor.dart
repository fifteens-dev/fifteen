import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import '../models/post_theme.dart';
import 'album_image.dart';

/// アルバムアート画像から色を抽出するユーティリティクラス
class ColorExtractor {
  /// 画像URLから主要な色を抽出
  ///
  /// [imageUrl] アルバムアート画像のURL
  /// 戻り値: 抽出された主要な色、失敗した場合はnull
  static Future<Color?> extractDominantColor(String imageUrl) async {
    try {
      if (imageUrl.isEmpty) {
        return null;
      }

      // NetworkImageからPaletteGeneratorを生成
      final PaletteGenerator paletteGenerator =
          await PaletteGenerator.fromImageProvider(
        albumImageProvider(imageUrl),
        size: const Size(200, 200), // サンプリングサイズ
        maximumColorCount: 20, // 抽出する色の最大数
      );

      // ドミナントカラーを取得
      return paletteGenerator.dominantColor?.color;
    } catch (e) {
      debugPrint('Color extraction failed: $e');
      return null;
    }
  }

  /// 画像URLから複数の主要な色を抽出
  ///
  /// [imageUrl] アルバムアート画像のURL
  /// 戻り値: 抽出された色のリスト
  static Future<List<Color>> extractColors(String imageUrl) async {
    try {
      if (imageUrl.isEmpty) {
        return [];
      }

      final PaletteGenerator paletteGenerator =
          await PaletteGenerator.fromImageProvider(
        albumImageProvider(imageUrl),
        size: const Size(200, 200),
        maximumColorCount: 20,
      );

      final List<Color> colors = [];

      // ドミナントカラー
      if (paletteGenerator.dominantColor != null) {
        colors.add(paletteGenerator.dominantColor!.color);
      }

      // 鮮やかな色
      if (paletteGenerator.vibrantColor != null) {
        colors.add(paletteGenerator.vibrantColor!.color);
      }

      // ミュートされた色
      if (paletteGenerator.mutedColor != null) {
        colors.add(paletteGenerator.mutedColor!.color);
      }

      // 明るい鮮やかな色
      if (paletteGenerator.lightVibrantColor != null) {
        colors.add(paletteGenerator.lightVibrantColor!.color);
      }

      // 暗い鮮やかな色
      if (paletteGenerator.darkVibrantColor != null) {
        colors.add(paletteGenerator.darkVibrantColor!.color);
      }

      return colors;
    } catch (e) {
      debugPrint('Colors extraction failed: $e');
      return [];
    }
  }

  /// 背景に適した色を抽出（ドミナントカラーを少し暗く）
  ///
  /// [imageUrl] アルバムアート画像のURL
  /// 戻り値: 背景に適した色、失敗した場合はデフォルト色
  static Future<Color> extractBackgroundColor(String imageUrl) async {
    try {
      if (imageUrl.isEmpty) {
        return const Color(0xFF1A1A1A); // デフォルトの暗い背景色
      }

      final PaletteGenerator paletteGenerator =
          await PaletteGenerator.fromImageProvider(
        albumImageProvider(imageUrl),
        size: const Size(200, 200),
        maximumColorCount: 20,
      );

      // ドミナントカラーまたはダークミュートカラーを取得
      Color? baseColor = paletteGenerator.darkMutedColor?.color ??
          paletteGenerator.dominantColor?.color;

      if (baseColor == null) {
        return const Color(0xFF1A1A1A);
      }

      // 色を少し暗くして背景に適した色に調整
      final HSLColor hsl = HSLColor.fromColor(baseColor);
      final HSLColor darkened = hsl.withLightness(
        (hsl.lightness * 0.7).clamp(0.0, 1.0),
      );

      return darkened.toColor();
    } catch (e) {
      debugPrint('Background color extraction failed: $e');
      return const Color(0xFF1A1A1A);
    }
  }

  /// グラデーション用の色ペアを抽出
  ///
  /// [imageUrl] アルバムアート画像のURL
  /// 戻り値: グラデーションの開始色と終了色のペア
  static Future<(Color start, Color end)> extractGradientColors(
      String imageUrl) async {
    try {
      if (imageUrl.isEmpty) {
        return (
          const Color(0xFF1A1A1A).withOpacity(0.0),
          const Color(0xFF1A1A1A)
        );
      }

      final PaletteGenerator paletteGenerator =
          await PaletteGenerator.fromImageProvider(
        albumImageProvider(imageUrl),
        size: const Size(200, 200),
        maximumColorCount: 20,
      );

      // 最も多く使われている色（ドミナントカラー）を取得
      Color? dominantColor = paletteGenerator.dominantColor?.color;

      if (dominantColor == null) {
        return (
          const Color(0xFF1A1A1A).withOpacity(0.0),
          const Color(0xFF1A1A1A)
        );
      }

      // ドミナントカラーをそのまま使用（明るさの調整なし）
      return (
        dominantColor.withOpacity(0.0), // 開始色（透明）
        dominantColor, // 終了色（不透明）
      );
    } catch (e) {
      debugPrint('Gradient colors extraction failed: $e');
      return (
        const Color(0xFF1A1A1A).withOpacity(0.0),
        const Color(0xFF1A1A1A)
      );
    }
  }

  /// グラデーション色からPostThemeを生成
  ///
  /// [gradientStart] グラデーションの開始色
  /// [gradientEnd] グラデーションの終了色
  /// 戻り値: 生成されたPostTheme
  static PostTheme createThemeFromColors(Color gradientStart, Color gradientEnd) {
    // 背景色の明度に応じてアイコンとテキストの色を決定
    final HSLColor hsl = HSLColor.fromColor(gradientEnd);
    final bool isDark = hsl.lightness < 0.5;

    // コメントボタンの色は10%明るくする
    final Color commentButtonColor = hsl
        .withLightness(
          (hsl.lightness * 1.1).clamp(0.0, 1.0),
        )
        .toColor();

    return PostTheme(
      gradientStart: gradientStart,
      gradientEnd: gradientEnd,
      commentButtonColor: commentButtonColor,
      textColor: isDark ? Colors.white : Colors.black,
      iconColor: isDark ? Colors.white : Colors.black,
      secondaryTextColor: isDark
          ? Colors.white.withOpacity(0.8)
          : Colors.black.withOpacity(0.8),
    );
  }

  /// アルバムアートURLからPostThemeを抽出
  ///
  /// [albumArtUrl] アルバムアート画像のURL
  /// 戻り値: 抽出されたPostTheme、失敗した場合はnull
  static Future<PostTheme?> extractThemeFromAlbumArt(String albumArtUrl) async {
    if (albumArtUrl.isEmpty) return null;

    try {
      final (gradientStart, gradientEnd) = await extractGradientColors(albumArtUrl);
      return createThemeFromColors(gradientStart, gradientEnd);
    } catch (e) {
      debugPrint('Theme extraction error: $e');
      return null;
    }
  }
}
