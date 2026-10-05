import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../utils/app_log.dart';

/// SF Pro フォントを iOS ネイティブ API 経由でロードするサービス
class FontService {
  static const _channel = MethodChannel('com.fifteen.fonts');

  /// iOS のみ: SF Pro を FontLoader に登録する
  /// 可変フォントの場合は1ファイル、ウェイト別の場合は複数ファイルが返る
  static Future<void> loadSFPro() async {
    if (!Platform.isIOS) return;
    try {
      if (kDebugMode) AppLog.debug('🔤 FontService: getSFProFonts を呼び出し中...');

      final raw = await _channel.invokeMethod<List>('getSFProFonts');

      if (kDebugMode) AppLog.debug('🔤 FontService: 受信データ = ${raw?.length ?? 'null'} 件');

      if (raw == null || raw.isEmpty) {
        if (kDebugMode) AppLog.debug('❌ FontService: フォントデータが空');
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
          if (kDebugMode) AppLog.debug('🔤 FontService: フォントデータ追加 ${item.lengthInBytes} bytes');
          loaded++;
        } else {
          if (kDebugMode) AppLog.debug('⚠️ FontService: 予期しない型 ${item.runtimeType}');
        }
      }

      await loader.load();
      if (kDebugMode) {
        AppLog.debug('✅ FontService: SFPro を $loaded ファイルでロード完了');
        AppLog.debug('🔤 FontService: FontLoader.load() 完了 - SFPro として登録済み');
      }
    } catch (e, st) {
      if (kDebugMode) {
        AppLog.debug('❌ FontService エラー: $e');
        AppLog.debug('   スタックトレース: $st');
      }
    }
  }
}
