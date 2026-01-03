/// 写真関連の定数定義
class PhotoConstants {
  /// Data URLのプレフィックス
  static const String dataUrlPrefix = 'data:image/';

  /// MIMEタイプ
  static const String mimeTypePng = 'image/png';
  static const String mimeTypeJpeg = 'image/jpeg';
  static const String mimeTypeGif = 'image/gif';
  static const String mimeTypeWebp = 'image/webp';

  /// Firestoreのドキュメント最大サイズ（1MB）
  /// Base64エンコード後のサイズを考慮して、元画像は750KB以下に制限
  static const int maxImageSizeBytes = 750000; // 750KB

  /// 画像圧縮品質（0-100）
  static const int compressionQuality = 85;

  /// 画像の最大幅（圧縮時）
  static const int maxImageWidth = 1920;

  /// 画像の最大高さ（圧縮時）
  static const int maxImageHeight = 1920;
}
