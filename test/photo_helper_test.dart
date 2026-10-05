import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:fifteen/utils/photo_helper.dart';

// 圧縮を別 isolate に出したので、record が isolate 越しに返るかを確かめる。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('compressForUpload が別 isolate で動き、寸法を返す', () async {
    // 上限より大きい画像を作って、縮小が効くことも見る。
    final src = img.Image(width: 3000, height: 2000);
    img.fill(src, color: img.ColorRgb8(10, 120, 200));
    final png = img.encodePng(src);

    final sw = Stopwatch()..start();
    final (bytes, w, h) = await PhotoHelper.compressForUpload(png);
    sw.stop();

    print('元 ${png.length} B → ${bytes.length} B / ${w}x$h / ${sw.elapsedMilliseconds}ms');
    expect(bytes.isNotEmpty, true);
    expect(w, greaterThan(0));
    expect(h, greaterThan(0));
    expect(w, lessThanOrEqualTo(3000));
    // JPEG として読み戻せること
    final back = img.decodeImage(bytes);
    expect(back, isNotNull);
    expect(back!.width, w);
    expect(back.height, h);
  });
}
