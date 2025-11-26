import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Firebase Storageサービス
///
/// プロフィール画像などのファイルをFirebase Storageにアップロード
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

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

      // メタデータを設定
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
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
}
