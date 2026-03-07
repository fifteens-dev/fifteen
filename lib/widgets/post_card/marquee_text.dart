import 'package:flutter/material.dart';

/// テキストが長い場合に横スクロールするマーキーウィジェット
/// [text] + [style] か [textSpan] のどちらかを指定する
class MarqueeText extends StatefulWidget {
  final String? text;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final double width;

  const MarqueeText({
    super.key,
    this.text,
    this.textSpan,
    this.style,
    required this.width,
  }) : assert(text != null || textSpan != null,
            'Either text or textSpan must be provided');

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
    final textPainter = TextPainter(
      text: widget.textSpan ?? TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();

    _textWidth = textPainter.width;

    if (_textWidth > widget.width) {
      setState(() {
        _needsScrolling = true;
      });

      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;

      while (mounted) {
        await _scrollController.animateTo(
          _textWidth - widget.width + 20,
          duration: const Duration(seconds: 5),
          curve: Curves.linear,
        );
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;

        await _scrollController.animateTo(
          0,
          duration: const Duration(seconds: 5),
          curve: Curves.linear,
        );
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

  Widget _buildText({required bool ellipsis}) {
    if (widget.textSpan != null) {
      return Text.rich(
        widget.textSpan!,
        maxLines: 1,
        overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.visible,
      );
    }
    return Text(
      widget.text!,
      style: widget.style,
      maxLines: 1,
      overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.visible,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsScrolling) {
      return SizedBox(
        width: widget.width,
        child: _buildText(ellipsis: true),
      );
    }

    return SizedBox(
      width: widget.width,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: _buildText(ellipsis: false),
      ),
    );
  }
}
