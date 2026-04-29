import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../constants/photo_constants.dart';
import '../services/storage_service.dart';

/// 写真処理のヘルパークラス
class PhotoHelper {
  /// プラットフォーム別に写真を処理
  ///
  /// Web版: Base64に変換してローカル保存（Firestoreに直接保存）
  /// モバイル版: Firebase Storageにアップロード
  ///
  /// [image] 処理する画像ファイル
  /// [userId] ユーザーID（Firebase Storage用）
  /// [storageService] StorageService（モバイル版で使用）
  ///
  /// 戻り値: 処理後のURL（Data URLまたはFirebase Storage URL）
  static Future<String?> processPhoto({
    required XFile image,
    required String userId,
    required StorageService storageService,
  }) async {
    try {
      final bytes = await image.readAsBytes();
      final originalSize = bytes.length;

      if (kDebugMode) {
        print('📸 写真処理開始');
        print('  - 元サイズ: ${(originalSize / 1024).toStringAsFixed(1)} KB');
        print('  - プラットフォーム: ${kIsWeb ? "Web" : "モバイル"}');
      }

      // 画像サイズチェックと圧縮
      Uint8List processedBytes = bytes;
      if (originalSize > PhotoConstants.maxImageSizeBytes) {
        if (kDebugMode) {
          print('⚠️  画像が大きすぎます。圧縮します...');
        }
        processedBytes = await _compressImage(bytes);
        if (kDebugMode) {
          print('✅ 圧縮完了: ${(processedBytes.length / 1024).toStringAsFixed(1)} KB');
        }
      }

      if (kIsWeb) {
        // Web版: Base64に変換
        return _convertToBase64(processedBytes, image.path);
      } else {
        // モバイル版: Firebase Storageにアップロード
        return await _uploadToFirebase(processedBytes, userId, storageService);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 写真処理エラー: $e');
      }
      rethrow;
    }
  }

  /// 写真をアップロードし、URL取得前のReferenceを返す（並列化用）
  ///
  /// Web版: Base64 URLを immediateUrl に返す（storageRef は null）
  /// モバイル版: アップロード後の Reference を storageRef に返す（immediateUrl は null）
  /// これにより呼び出し側で getDownloadURL() と createPost を並列実行できる
  static Future<({String? immediateUrl, Reference? storageRef})> processPhotoSplit({
    required XFile image,
    required String userId,
    required StorageService storageService,
  }) async {
    try {
      final bytes = await image.readAsBytes();
      final originalSize = bytes.length;

      Uint8List processedBytes = bytes;
      if (originalSize > PhotoConstants.maxImageSizeBytes) {
        processedBytes = await _compressImage(bytes);
      }

      if (kIsWeb) {
        final url = _convertToBase64(processedBytes, image.path);
        return (immediateUrl: url, storageRef: null);
      } else {
        final ref = await storageService.uploadPostImageGetRef(
          userId: userId,
          imageBytes: processedBytes,
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw Exception('アップロードがタイムアウトしました'),
        );
        return (immediateUrl: null, storageRef: ref);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 写真分割アップロードエラー: $e');
      }
      rethrow;
    }
  }

  /// 画像を圧縮
  static Future<Uint8List> _compressImage(Uint8List bytes) async {
    try {
      // 画像をデコード
      final image = img.decodeImage(bytes);
      if (image == null) {
        if (kDebugMode) {
          print('⚠️  画像のデコードに失敗しました。元のデータを返します。');
        }
        return bytes;
      }

      // リサイズが必要かチェック
      img.Image resizedImage = image;
      if (image.width > PhotoConstants.maxImageWidth ||
          image.height > PhotoConstants.maxImageHeight) {
        // アスペクト比を維持してリサイズ
        resizedImage = img.copyResize(
          image,
          width: image.width > image.height ? PhotoConstants.maxImageWidth : null,
          height: image.height > image.width ? PhotoConstants.maxImageHeight : null,
        );
        if (kDebugMode) {
          print('  - リサイズ: ${image.width}x${image.height} → ${resizedImage.width}x${resizedImage.height}');
        }
      }

      // JPEG形式で圧縮
      final compressedBytes = Uint8List.fromList(
        img.encodeJpg(resizedImage, quality: PhotoConstants.compressionQuality),
      );

      // 圧縮後もサイズが大きい場合は品質を下げて再圧縮
      if (compressedBytes.length > PhotoConstants.maxImageSizeBytes) {
        if (kDebugMode) {
          print('  - 追加圧縮が必要です（品質を下げます）');
        }
        return Uint8List.fromList(
          img.encodeJpg(resizedImage, quality: 70),
        );
      }

      return compressedBytes;
    } catch (e) {
      if (kDebugMode) {
        print('⚠️  圧縮エラー: $e。元のデータを返します。');
      }
      return bytes;
    }
  }

  /// Base64に変換（Web版）
  static String _convertToBase64(Uint8List bytes, String path) {
    final base64String = base64Encode(bytes);
    final mimeType = _getMimeType(path);
    final dataUrl = 'data:$mimeType;base64,$base64String';

    if (kDebugMode) {
      print('🌐 Web版: Base64変換完了');
      print('  - Base64サイズ: ${(base64String.length / 1024).toStringAsFixed(1)} KB');
      print('  - MIMEタイプ: $mimeType');
    }

    return dataUrl;
  }

  /// Firebase Storageにアップロード（モバイル版）
  static Future<String> _uploadToFirebase(
    Uint8List bytes,
    String userId,
    StorageService storageService,
  ) async {
    if (kDebugMode) {
      print('📱 モバイル版: Firebase Storageにアップロード中...');
    }

    final url = await storageService.uploadPostImage(
      userId: userId,
      imageBytes: bytes,
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw Exception('アップロードがタイムアウトしました');
      },
    );

    if (kDebugMode) {
      print('✅ モバイル版: アップロード完了');
      print('  - URL: $url');
    }

    return url;
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
        return PhotoConstants.mimeTypeJpeg; // デフォルト
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

  /// 写真URLをログ表示用に短縮（Base64の場合は最初の50文字のみ表示）
  ///
  /// [photoUrl] 写真のURL（Data URLまたはネットワークURL）
  /// 戻り値: ログ表示用の短縮文字列
  static String formatPhotoUrlForLog(String? photoUrl) {
    if (photoUrl == null || photoUrl.isEmpty) {
      return '(empty)';
    }

    if (isDataUrl(photoUrl)) {
      // Base64の場合は最初の50文字 + 長さ情報
      final displayLength = 50;
      if (photoUrl.length > displayLength) {
        return '${photoUrl.substring(0, displayLength)}... [Base64 data: ${photoUrl.length} chars]';
      }
      return photoUrl;
    }

    // ネットワークURLやアセットパスはそのまま表示
    return photoUrl;
  }
}
