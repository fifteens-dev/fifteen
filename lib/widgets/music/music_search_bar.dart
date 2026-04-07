import 'package:flutter/material.dart';
import '../common/search_bar.dart';

/// 楽曲選択画面の検索バーウィジェット
///
/// AppSearchBar を楽曲検索用の設定でラップする StatelessWidget。
class MusicSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isFocused;
  final VoidCallback onCancel;
  final ValueChanged<String> onChanged;

  const MusicSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isFocused,
    required this.onCancel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppSearchBar(
      controller: controller,
      focusNode: focusNode,
      isFocused: isFocused,
      onCancel: onCancel,
      onChanged: onChanged,
    );
  }
}
