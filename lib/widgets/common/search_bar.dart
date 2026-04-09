import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../utils/context_menu_builder.dart';

/// アプリ共通の検索バーウィジェット
///
/// 楽曲選択画面のスタイルを正典とする。
/// - [controller] / [focusNode] は呼び出し元のStateが管理する
/// - [isFocused] が true のときキャンセルボタンを表示し、検索バーを狭くする
/// - [showClearButton] が true のとき、入力がある場合にフィールド内クリアボタンを表示
/// - [padding] で外側の余白を上書き可能（デフォルト: horizontal 16）
class AppSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isFocused;
  final VoidCallback onCancel;
  final ValueChanged<String> onChanged;
  final String hintText;
  final bool showClearButton;
  final EdgeInsetsGeometry padding;

  const AppSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isFocused,
    required this.onCancel,
    required this.onChanged,
    this.hintText = '検索',
    this.showClearButton = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          // フォーカス時は狭く（flex: 75）、非フォーカス時は全幅
          Expanded(
            flex: isFocused ? 75 : 1,
            child: Container(
              height: AppDimensions.searchBarHeight,
              decoration: BoxDecoration(
                color: AppColors.searchBarBackground,
                borderRadius: BorderRadius.circular(AppDimensions.searchBarBorderRadius),
              ),
              child: Row(
                children: [
                  const SizedBox(width: AppDimensions.searchBarLeadingGap),
                  const Icon(
                    Icons.search,
                    color: AppColors.searchBarIcon,
                    size: AppDimensions.searchBarIconSize,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: const TextStyle(
                        fontSize: AppDimensions.searchBarFontSize,
                        color: Colors.white,
                      ),
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: const TextStyle(
                          fontSize: AppDimensions.searchBarFontSize,
                          color: AppColors.searchBarIcon,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: onChanged,
                      contextMenuBuilder: buildTextContextMenu,
                    ),
                  ),
                  if (showClearButton && controller.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        controller.clear();
                        onChanged('');
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.cancel,
                          color: AppColors.searchBarIcon,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isFocused)
            Expanded(
              flex: 25,
              child: GestureDetector(
                onTap: onCancel,
                child: const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: Text(
                    'キャンセル',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: AppColors.searchCancelText,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
