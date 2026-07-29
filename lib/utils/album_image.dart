import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// albumImageUrl がネットワークURLではなく、端末ローカル由来（data URI /
/// ファイルパス）かどうか。今再生中のローカル/取り込み曲の埋め込みアートを
/// data URI で持たせるために使う。
bool isLocalAlbumArt(String url) =>
    url.startsWith('data:') ||
    url.startsWith('file://') ||
    url.startsWith('/');

/// albumImageUrl から適切な [ImageProvider] を返す。
/// - `data:image/...;base64,...` → [MemoryImage]
/// - `file://...` / 絶対パス → [FileImage]
/// - それ以外（http/https）→ [CachedNetworkImageProvider]（従来通り）
ImageProvider albumImageProvider(String url) {
  if (url.startsWith('data:')) {
    final i = url.indexOf(',');
    if (i >= 0) {
      try {
        return MemoryImage(base64Decode(url.substring(i + 1)));
      } catch (_) {
        // デコード失敗時は下のネットワーク扱いにフォールバック（実際には失敗表示になる）。
      }
    }
  }
  if (url.startsWith('file://')) return FileImage(File(url.substring(7)));
  if (url.startsWith('/')) return FileImage(File(url));
  return CachedNetworkImageProvider(url);
}
