import 'dart:io';
import 'package:flutter/material.dart';

/// テキストフィールド用コンテキストメニュービルダー
///
/// iOS  : SystemContextMenu（UIEditMenuInteraction）を使用。
///        AppDelegate で AppleLanguages=["ja"] を強制し、
///        FlutterTextInputView の canPerformAction をスウィズルして
///        ペーストを常時表示する。
///        iOS 15 以下は Live Text を除いた Cupertino スタイルにフォールバック。
/// Android: Live Text を除外し、ペーストを常に日本語で表示する。
Widget buildTextContextMenu(
    BuildContext ctx, EditableTextState editableTextState) {
  if (Platform.isIOS) {
    if (SystemContextMenu.isSupported(ctx)) {
      return SystemContextMenu.editableText(
        editableTextState: editableTextState,
      );
    }
    // iOS 15 以下フォールバック: Live Text を除いた Cupertino スタイル
    final items = editableTextState.contextMenuButtonItems
        .where((i) => i.type != ContextMenuButtonType.liveTextInput)
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  // Android: ペーストを常に表示
  var items = editableTextState.contextMenuButtonItems
      .where((i) => i.type != ContextMenuButtonType.liveTextInput)
      .map((item) {
    if (item.type == ContextMenuButtonType.paste) {
      return ContextMenuButtonItem(
        onPressed: item.onPressed,
        type: item.type,
        label: 'ペースト',
      );
    }
    return item;
  }).toList();

  final hasPaste = items.any((i) => i.type == ContextMenuButtonType.paste);
  if (!hasPaste) {
    items = [
      ...items,
      ContextMenuButtonItem(
        onPressed: () {
          editableTextState.pasteText(SelectionChangedCause.toolbar);
        },
        type: ContextMenuButtonType.paste,
        label: 'ペースト',
      ),
    ];
  }

  if (items.isEmpty) return const SizedBox.shrink();
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: items,
  );
}
