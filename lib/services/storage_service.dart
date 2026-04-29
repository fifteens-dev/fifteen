import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Firebase Storageサービス
///
/// プロフィール画像などのファイルをFirebase Storageにアップロード
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// 投稿/プロフィール画像のCDNキャッシュヘッダー（30日）
  /// 同一画像の再ダウンロード時に Storage egress を発生させない。
  /// プロフィール画像は変更頻度が低い投稿画像と同じ運用で十分。
  static const String _imageCacheControl = 'public, max-age=2592000';

  /// プロフィール画像をアップロード
  ///
  /// [userId] ユーザーID
  /// [imageBytes] 画像のバイトデータ
  /// 戻り値: アップロードされた画像のダウンロードURL
  Future<String> uploadProfileImage({
    required String userId,
    required Uint8List imageBytes,
  }) async {
    try {
      // ファイル名: profile_images/{userId}/profile.jpg
      final storageRef = _storage.ref().child('profile_images/$userId/profile.jpg');

      // メタデータを設定（CDNキャッシュ有効化で egress 抑制）
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: _imageCacheControl,
        customMetadata: {'uploaded': DateTime.now().toIso8601String()},
      );

      // アップロード
      final uploadTask = await storageRef.putData(imageBytes, metadata);

      // ダウンロードURLを取得
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      if (kDebugMode) {
        print('Profile image uploaded successfully: $downloadUrl');
      }

      return downloadUrl;
    } catch (e) {
      if (kDebugMode) {
        print('Error uploading profile image: $e');
      }
      rethrow;
    }
  }

  /// プロフィール画像を削除
  ///
  /// [userId] ユーザーID
  Future<void> deleteProfileImage(String userId) async {
    try {
      final storageRef = _storage.ref().child('profile_images/$userId/profile.jpg');
      await storageRef.delete();

      if (kDebugMode) {
        print('Profile image deleted successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting profile image: $e');
      }
      // 画像が存在しない場合のエラーは無視
      if (e is FirebaseException && e.code == 'object-not-found') {
        return;
      }
      rethrow;
    }
  }

  /// 投稿画像をアップロード
  ///
  /// [userId] ユーザーID
  /// [imageBytes] 画像のバイトデータ
  /// 戻り値: アップロードされた画像のダウンロードURL
  Future<String> uploadPostImage({
    required String userId,
    required Uint8List imageBytes,
  }) async {
    try {
      // タイムスタンプを使用してユニークなファイル名を生成
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = _storage.ref().child('post_images/$userId/$timestamp.jpg');

      // メタデータを設定（CDNキャッシュ有効化で egress 抑制）
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: _imageCacheControl,
        customMetadata: {'uploaded': DateTime.now().toIso8601String()},
      );

      // アップロード
      final uploadTask = await storageRef.putData(imageBytes, metadata);

      // ダウンロードURLを取得
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      if (kDebugMode) {
        print('Post image uploaded successfully: $downloadUrl');
      }

      return downloadUrl;
    } catch (e) {
      if (kDebugMode) {
        print('Error uploading post image: $e');
      }
      rethrow;
    }
  }

  /// 投稿画像をアップロードし、Referenceを返す（getDownloadURLは呼ばない）
  ///
  /// getDownloadURL()を後で並列実行するための分割アップロード用
  Future<Reference> uploadPostImageGetRef({
    required String userId,
    required Uint8List imageBytes,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = _storage.ref().child('post_images/$userId/$timestamp.jpg');
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: _imageCacheControl,
        customMetadata: {'uploaded': DateTime.now().toIso8601String()},
      );
      final taskSnapshot = await storageRef.putData(imageBytes, metadata);
      if (kDebugMode) {
        print('Post image uploaded, ref: ${taskSnapshot.ref.fullPath}');
      }
      return taskSnapshot.ref;
    } catch (e) {
      if (kDebugMode) {
        print('Error uploading post image (get ref): $e');
      }
      rethrow;
    }
  }
}
