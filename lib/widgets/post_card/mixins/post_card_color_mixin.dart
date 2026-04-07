part of '../../post_card.dart';

extension PostCardColorMethods on PostCardState {
  /// 色テーマの初期化
  void _initializeColors() {
    // 色の優先順位:
    // 1. 事前抽出パラメータ
    // 2. Firestoreに保存されたテーマ（デフォルトテーマでない場合）
    // 3. リアルタイム抽出
    if (widget.preExtractedGradientStart != null && widget.preExtractedGradientEnd != null) {
      debugPrint('✅ PostCard: 事前抽出された色を使用します');
      _extractedGradientStart = widget.preExtractedGradientStart;
      _extractedGradientEnd = widget.preExtractedGradientEnd;
    } else if (widget.post.theme != PostTheme.defaultTheme) {
      debugPrint('✅ PostCard: Firestoreのテーマを使用します');
      _extractedGradientStart = widget.post.theme.gradientStart;
      _extractedGradientEnd = widget.post.theme.gradientEnd;
    } else {
      debugPrint('⚠️ PostCard: 色が未抽出のため、抽出を開始します');
      _extractColorsFromAlbumArt();
    }
  }

  /// アルバムアートから色を抽出
  Future<void> _extractColorsFromAlbumArt() async {
    if (_isColorExtracting) return;

    setState(() {
      _isColorExtracting = true;
    });

    try {
      final imageUrl = _displayAlbumArtUrl;
      debugPrint('🎨 Extracting colors from: $imageUrl');

      if (imageUrl.isNotEmpty) {
        // グラデーション用の色ペアを抽出
        final (gradientStart, gradientEnd) =
            await ColorExtractor.extractGradientColors(imageUrl);

        debugPrint('✅ Color extraction successful!');
        debugPrint('  Gradient Start: $gradientStart');
        debugPrint('  Gradient End: $gradientEnd');

        if (mounted) {
          setState(() {
            _extractedGradientStart = gradientStart;
            _extractedGradientEnd = gradientEnd;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Color extraction error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isColorExtracting = false;
        });
      }
    }
  }

  /// 動的にテーマを生成（抽出された色を優先、なければデフォルトテーマ）
  PostTheme _getDynamicTheme() {
    // 抽出された色がある場合は動的にテーマを生成
    if (_extractedGradientStart != null && _extractedGradientEnd != null) {
      return ColorExtractor.createThemeFromColors(
        _extractedGradientStart!,
        _extractedGradientEnd!,
      );
    }
    // デフォルトのテーマを使用
    return widget.post.theme;
  }
}
