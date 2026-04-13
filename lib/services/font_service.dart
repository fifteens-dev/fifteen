import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// SF Pro フォントを iOS ネイティブ API 経由でロードするサービス
class FontService {
  static const _channel = MethodChannel('com.fifteen.fonts');

  /// iOS のみ: SF Pro を FontLoader に登録する
  /// 可変フォントの場合は1ファイル、ウェイト別の場合は複数ファイルが返る
  static Future<void> loadSFPro() async {
    if (!Platform.isIOS) return;
    try {
      if (kDebugMode) print('🔤 FontService: getSFProFonts を呼び出し中...');

      final raw = await _channel.invokeMethod<List>('getSFProFonts');

      if (kDebugMode) print('🔤 FontService: 受信データ = ${raw?.length ?? 'null'} 件');

      if (raw == null || raw.isEmpty) {
        if (kDebugMode) print('❌ FontService: フォントデータが空');
        return;
      }

      final loader = FontLoader('SFPro');
      int loaded = 0;
      for (final item in raw) {
        if (item is Uint8List) {
          // offsetInBytes と lengthInBytes を明示してバッファのパディングを除外する
          final byteData = ByteData.view(
            item.buffer,
            item.offsetInBytes,
            item.lengthInBytes,
          );
          loader.addFont(Future.value(byteData));
          if (kDebugMode) print('🔤 FontService: フォントデータ追加 ${item.lengthInBytes} bytes');
          loaded++;
        } else {
          if (kDebugMode) print('⚠️ FontService: 予期しない型 ${item.runtimeType}');
        }
      }

      await loader.load();
      if (kDebugMode) {
        print('✅ FontService: SFPro を $loaded ファイルでロード完了');
        print('🔤 FontService: FontLoader.load() 完了 - SFPro として登録済み');
      }
    } catch (e, st) {
      if (kDebugMode) {
        print('❌ FontService エラー: $e');
        print('   スタックトレース: $st');
      }
    }
  }
}
