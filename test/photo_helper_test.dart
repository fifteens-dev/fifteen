import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:fifteen/constants/photo_constants.dart';
import 'package:fifteen/utils/photo_helper.dart';

/// 画像の圧縮は別 isolate（compute）で走らせている。
/// UI を止めないための変更なので、isolate を挟んでも結果と例外の扱いが
/// 変わっていないことをここで押さえる。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List png(int w, int h) {
    final im = img.Image(width: w, height: h);
    img.fill(im, color: img.ColorRgb8(10, 120, 200));
    return Uint8List.fromList(img.encodePng(im));
  }

  test('別 isolate で動き、寸法を返す', () async {
    final sw = Stopwatch()..start();
    final (bytes, w, h) = await PhotoHelper.compressForUpload(png(3000, 2000));
    sw.stop();
    // ignore: avoid_print  実測を目で見たいのでテストでは出す
    print('  3000x2000 → ${w}x$h / ${bytes.length} B / ${sw.elapsedMilliseconds}ms');
    expect(w, lessThanOrEqualTo(PhotoConstants.maxImageWidth));
    expect(img.decodeImage(bytes)!.width, w);
    expect(img.decodeImage(bytes)!.height, h);
  });

  test('上限以下の画像は縮小しない', () async {
    final (_, w, h) = await PhotoHelper.compressForUpload(png(800, 600));
    expect(w, 800);
    expect(h, 600);
  });

  test('横長でも縦横比を保って長辺を上限に収める', () async {
    final (_, w, h) = await PhotoHelper.compressForUpload(png(4000, 1000));
    expect(w, PhotoConstants.maxImageWidth);
    expect(h, (1000 * PhotoConstants.maxImageWidth / 4000).round());
  });

  test('二度圧縮しても寸法は変わらない', () async {
    // uploadCompressedSplit の alreadyCompressed はこの前提に立っている。
    // 二度目は無駄なだけで結果は変わらない、ということを押さえておく。
    final (once, w1, h1) = await PhotoHelper.compressForUpload(png(3000, 2000));
    final (_, w2, h2) = await PhotoHelper.compressForUpload(once);
    expect(w2, w1);
    expect(h2, h1);
  });

  test('壊れたバイト列の例外は isolate の境界を越えて伝わる', () async {
    // compute が例外を飲み込むと、投稿が黙って失敗する。
    // 呼び出し側（PostSubmission / PostPhotoService.attach）は try/catch で
    // 拾って「投稿に失敗しました」を出す前提になっている。
    await expectLater(
      PhotoHelper.compressForUpload(Uint8List.fromList([1, 2, 3, 4, 5])),
      throwsA(isA<Object>()),
    );
  });
}
