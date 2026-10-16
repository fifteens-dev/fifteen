import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 音楽サービスの連携は**端末**に持っていて、アプリ内アカウントには
/// 紐付いていない。ログアウトやアカウント削除で消さないと、次にこの端末で
/// 入った人が前の人の連携を引き継ぐ。
///
/// 実際、ダミーアカウントで連携したまま削除したあと、新しいアカウントが
/// 「連携済み」と判定されて連携し直せなくなった。
///
/// 後始末の規則をここで押さえる（MusicServiceManager.clearDeviceLinkage と
/// 同じ形を置く。本体は secure storage を触るのでテストから呼べない）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const selectedKey = 'selected_music_service';
  const stampedKey = 'music_service_stamped_uid';

  /// clearDeviceLinkage の骨格。
  /// 片方のトークン削除が失敗しても、もう片方と選択の記録は必ず消す。
  Future<void> clear({
    required Future<void> Function() apple,
    required Future<void> Function() spotify,
    required void Function() dropCache,
  }) async {
    try { await apple(); } catch (_) {}
    try { await spotify(); } catch (_) {}
    dropCache();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(selectedKey);
    await prefs.remove(stampedKey);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({
      selectedKey: 'MusicServiceType.appleMusic',
      stampedKey: 'dummy_uid',
    });
  });

  test('選択の記録とスタンプが消える', () async {
    var cacheDropped = false;
    await clear(
      apple: () async {}, spotify: () async {},
      dropCache: () => cacheDropped = true,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(selectedKey), isNull,
        reason: '残っていると「連携済み」と判定され、連携し直せない');
    expect(prefs.getString(stampedKey), isNull);
    expect(cacheDropped, true, reason: 'メモリ上のキャッシュも落とさないと残る');
  });

  test('両方のサービスのトークンを消しにいく', () async {
    var appleCalled = false, spotifyCalled = false;
    await clear(
      apple: () async => appleCalled = true,
      spotify: () async => spotifyCalled = true,
      dropCache: () {},
    );
    // 選択が壊れていても確実に消えるよう、分岐せず両方に行く。
    expect(appleCalled, true);
    expect(spotifyCalled, true);
  });

  test('片方が失敗しても、もう片方と選択の記録は消える', () async {
    var spotifyCalled = false;
    await clear(
      apple: () async => throw Exception('secure storage が読めない'),
      spotify: () async => spotifyCalled = true,
      dropCache: () {},
    );
    expect(spotifyCalled, true, reason: '1 つ目の失敗で止まってはいけない');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(selectedKey), isNull);
  });
}
