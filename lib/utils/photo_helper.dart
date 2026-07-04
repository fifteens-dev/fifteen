import 'dart:convert';
import 'dart:math';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset, Size;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../constants/photo_constants.dart';
import '../services/storage_service.dart';

/// 写真処理のヘルパークラス
class PhotoHelper {
  // 投稿カード裏面の固定寸法（PostCardBackView.cardWidth / cardHeight と同値）
  static const double _cardWidth = 363.0;
  static const double _cardHeight = 645.0;

  /// プラットフォーム別に写真を処理
  static Future<String?> processPhoto({
    required XFile image,
    required String userId,
    required StorageService storageService,
  }) async {
    try {
      final bytes = await image.readAsBytes();
      final (processedBytes, _, __) = await _cropAndCompress(bytes);

      if (kIsWeb) {
        return _convertToBase64(processedBytes, image.path);
      } else {
        return await _uploadToFirebase(processedBytes, userId, storageService);
      }
    } catch (e) {
      if (kDebugMode) print('❌ 写真処理エラー: $e');
      rethrow;
    }
  }

  /// クロップなしでリサイズ + JPEG 圧縮だけ行う軽量版。
  ///
  /// Vibe ストーリー投稿のように「写真をそのまま全画面表示」する用途で使う。
  /// 投稿フローのカード裏面表示用クロップは行わないため、構図はユーザーの
  /// 選択そのまま保たれる。
  ///
  /// 戻り値: (リサイズ・圧縮済みバイト列, 幅px, 高さpx)
  static Future<(Uint8List, int, int)> compressForUpload(
      Uint8List bytes) async {
    return _compressImage(bytes);
  }

  /// 圧縮済みバイト列をそのまま PUT し、Reference を返す軽量版。
  /// 後段で getDownloadURL + createPost を並列化できるよう URL は取らない。
  static Future<({Reference? storageRef, int width, int height})>
      uploadCompressedSplit({
    required Uint8List imageBytes,
    required String userId,
    required StorageService storageService,
  }) async {
    final (processed, w, h) = await _compressImage(imageBytes);
    if (kIsWeb) {
      // Web は base64 で returnImmediateUrl 想定なのでここでは未対応
      throw UnsupportedError('uploadCompressedSplit is not supported on web');
    }
    final ref = await storageService
        .uploadPostImageGetRef(userId: userId, imageBytes: processed)
        .timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception('アップロードがタイムアウトしました'),
    );
    return (storageRef: ref, width: w, height: h);
  }

  /// リサイズ + JPEG 再エンコード（クロップなしの共通ロジック）。
  /// [PhotoConstants.maxImageWidth] / [maxImageHeight] を超えていれば縮小し、
  /// quality 85 → 大きすぎたら 70 に下げる。
  static Future<(Uint8List, int, int)> _compressImage(Uint8List bytes) async {
    final src = img.decodeImage(bytes);
    if (src == null) return (bytes, 0, 0);

    img.Image resized = src;
    if (src.width > PhotoConstants.maxImageWidth ||
        src.height > PhotoConstants.maxImageHeight) {
      resized = img.copyResize(
        src,
        width: src.width > src.height ? PhotoConstants.maxImageWidth : null,
        height: src.height > src.width ? PhotoConstants.maxImageHeight : null,
      );
    }

    final finalWidth = resized.width;
    final finalHeight = resized.height;

    final encoded = Uint8List.fromList(
        img.encodeJpg(resized, quality: PhotoConstants.compressionQuality));
    if (encoded.length > PhotoConstants.maxImageSizeBytes) {
      return (
        Uint8List.fromList(img.encodeJpg(resized, quality: 70)),
        finalWidth,
        finalHeight,
      );
    }
    return (encoded, finalWidth, finalHeight);
  }

  /// 写真をアップロードし、URL取得前のReferenceを返す（並列化用）
  ///
  /// [imageOffset]・[imageScale]・[imageNaturalSize] を渡すと、
  /// カード裏面に表示される領域のみを切り出してからアップロードする。
  /// 戻り値の [croppedWidth] / [croppedHeight] はクロップ後のピクセル寸法。
  static Future<({String? immediateUrl, Reference? storageRef, int croppedWidth, int croppedHeight})> processPhotoSplit({
    required XFile image,
    required String userId,
    required StorageService storageService,
    Offset imageOffset = Offset.zero,
    double imageScale = 1.0,
    Size? imageNaturalSize,
  }) async {
    try {
      final bytes = await image.readAsBytes();

      final (processedBytes, croppedWidth, croppedHeight) = await _cropAndCompress(
        bytes,
        imageOffset: imageOffset,
        imageScale: imageScale,
        imageNaturalSize: imageNaturalSize,
      );

      if (kIsWeb) {
        final url = _convertToBase64(processedBytes, image.path);
        return (immediateUrl: url, storageRef: null, croppedWidth: croppedWidth, croppedHeight: croppedHeight);
      } else {
        final ref = await storageService.uploadPostImageGetRef(
          userId: userId,
          imageBytes: processedBytes,
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw Exception('アップロードがタイムアウトしました'),
        );
        return (immediateUrl: null, storageRef: ref, croppedWidth: croppedWidth, croppedHeight: croppedHeight);
      }
    } catch (e) {
      if (kDebugMode) print('❌ 写真分割アップロードエラー: $e');
      rethrow;
    }
  }

  /// カード裏面の表示領域に合わせて画像をクロップし、必要なら圧縮する
  /// 戻り値: (エンコード済みバイト列, クロップ後幅px, クロップ後高さpx)
  static Future<(Uint8List, int, int)> _cropAndCompress(
    Uint8List bytes, {
    Offset imageOffset = Offset.zero,
    double imageScale = 1.0,
    Size? imageNaturalSize,
  }) async {
    final src = img.decodeImage(bytes);
    if (src == null) return (bytes, 0, 0);

    // カード裏面に映る部分だけ切り取る
    final cropped = _cropToCardView(src, imageOffset, imageScale, imageNaturalSize) ?? src;

    // 最大サイズを超える場合はリサイズ
    img.Image resized = cropped;
    if (cropped.width > PhotoConstants.maxImageWidth || cropped.height > PhotoConstants.maxImageHeight) {
      resized = img.copyResize(
        cropped,
        width: cropped.width > cropped.height ? PhotoConstants.maxImageWidth : null,
        height: cropped.height > cropped.width ? PhotoConstants.maxImageHeight : null,
      );
    }

    final finalWidth = resized.width;
    final finalHeight = resized.height;

    // JPEG に変換
    final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: PhotoConstants.compressionQuality));
    if (encoded.length > PhotoConstants.maxImageSizeBytes) {
      return (Uint8List.fromList(img.encodeJpg(resized, quality: 70)), finalWidth, finalHeight);
    }
    return (encoded, finalWidth, finalHeight);
  }

  /// カード表示領域（363×645）に対応する画像ピクセル矩形を切り取る
  ///
  /// PostCardBackView の描画ロジックを逆算:
  ///   baseScale = cardH / natH
  ///   表示サイズ: (natW * baseScale) × cardH
  ///   カード上座標 (cx, cy) → 画像ピクセル (px, py):
  ///     px = (cx − imageOffset.dx) / imageScale / displayW * natW
  ///     py = (cy − imageOffset.dy) / imageScale / cardH   * natH
  static img.Image? _cropToCardView(
    img.Image src,
    Offset imageOffset,
    double imageScale,
    Size? imageNaturalSize,
  ) {
    final natW = (imageNaturalSize?.width ?? src.width).toDouble();
    final natH = (imageNaturalSize?.height ?? src.height).toDouble();

    int l, t, r, b;

    if (imageNaturalSize != null) {
      // ユーザーがオフセット/スケールを指定しているケース
      final baseScale = _cardHeight / natH;
      final displayW = natW * baseScale;

      final pxL = ((0 - imageOffset.dx) / imageScale / displayW * natW).floor();
      final pxT = ((0 - imageOffset.dy) / imageScale / _cardHeight * natH).floor();
      final pxR = ((_cardWidth - imageOffset.dx) / imageScale / displayW * natW).ceil();
      final pxB = ((_cardHeight - imageOffset.dy) / imageScale / _cardHeight * natH).ceil();

      l = pxL.clamp(0, src.width);
      t = pxT.clamp(0, src.height);
      r = pxR.clamp(l, src.width);
      b = pxB.clamp(t, src.height);
    } else {
      // imageNaturalSize 未指定 → BoxFit.cover センタークロップ
      final scale = max(_cardWidth / natW, _cardHeight / natH);
      final offsetX = (natW - _cardWidth / scale) / 2;
      final offsetY = (natH - _cardHeight / scale) / 2;

      l = offsetX.floor().clamp(0, src.width);
      t = offsetY.floor().clamp(0, src.height);
      r = (natW - offsetX).ceil().clamp(l, src.width);
      b = (natH - offsetY).ceil().clamp(t, src.height);
    }

    final w = r - l;
    final h = b - t;
    if (w <= 0 || h <= 0) return null;

    return img.copyCrop(src, x: l, y: t, width: w, height: h);
  }

  /// Firebase Storageにアップロード（モバイル版）
  static Future<String> _uploadToFirebase(
    Uint8List bytes,
    String userId,
    StorageService storageService,
  ) async {
    return await storageService.uploadPostImage(
      userId: userId,
      imageBytes: bytes,
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception('アップロードがタイムアウトしました'),
    );
  }

  /// Base64に変換（Web版）
  static String _convertToBase64(Uint8List bytes, String path) {
    final base64String = base64Encode(bytes);
    final mimeType = _getMimeType(path);
    return 'data:$mimeType;base64,$base64String';
  }

  /// ファイルパスからMIMEタイプを取得
  static String _getMimeType(String path) {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'png':
        return PhotoConstants.mimeTypePng;
      case 'jpg':
      case 'jpeg':
        return PhotoConstants.mimeTypeJpeg;
      case 'gif':
        return PhotoConstants.mimeTypeGif;
      case 'webp':
        return PhotoConstants.mimeTypeWebp;
      default:
        return PhotoConstants.mimeTypeJpeg;
    }
  }

  /// URLがData URL（Base64）かどうかをチェック
  static bool isDataUrl(String url) {
    return url.startsWith(PhotoConstants.dataUrlPrefix);
  }

  /// URLがネットワークURL（http/https）かどうかをチェック
  static bool isNetworkUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /// 写真URLをログ表示用に短縮
  static String formatPhotoUrlForLog(String? photoUrl) {
    if (photoUrl == null || photoUrl.isEmpty) return '(empty)';
    if (isDataUrl(photoUrl)) {
      const displayLength = 50;
      if (photoUrl.length > displayLength) {
        return '${photoUrl.substring(0, displayLength)}... [Base64 data: ${photoUrl.length} chars]';
      }
    }
    return photoUrl;
  }
}
