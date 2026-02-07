import 'package:flutter/material.dart';

/// テキストが長い場合に横スクロールするマーキーウィジェット
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double width;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    required this.width,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late ScrollController _scrollController;
  bool _needsScrolling = false;
  double _textWidth = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndStartScrolling();
    });
  }

  void _checkAndStartScrolling() async {
    // テキストの幅を計算
    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();

    _textWidth = textPainter.width;

    if (_textWidth > widget.width) {
      setState(() {
        _needsScrolling = true;
      });

      // スクロールアニメーションを開始
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;

      while (mounted) {
        // 右から左へスクロール
        await _scrollController.animateTo(
          _textWidth - widget.width + 20,
          duration: const Duration(seconds: 5),
          curve: Curves.linear,
        );

        // 少し待つ
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;

        // 左端に戻る
        await _scrollController.animateTo(
          0,
          duration: const Duration(seconds: 5),
          curve: Curves.linear,
        );

        // 少し待つ
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsScrolling) {
      return SizedBox(
        width: widget.width,
        child: Text(
          widget.text,
          style: widget.style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(
          widget.text,
          style: widget.style,
          maxLines: 1,
        ),
      ),
    );
  }
}
