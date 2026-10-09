import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Music Memory のカレンダーが「いつ読み直すか」「どこまで読み直すか」の規則。
///
/// 画面そのものは Firestore が要るので組み立てられない。規則だけを同じ形で
/// 置いて確かめる。
void main() {
  group('読み直す条件', () {
    late ValueNotifier<int> postCreated;
    late ValueNotifier<Set<String>> photoAdded;
    late bool stale;

    void markStale() => stale = true;

    setUp(() {
      postCreated = ValueNotifier<int>(0);
      photoAdded = ValueNotifier<Set<String>>(const {});
      stale = false;
      postCreated.addListener(markStale);
      photoAdded.addListener(markStale);
    });

    tearDown(() {
      postCreated.removeListener(markStale);
      photoAdded.removeListener(markStale);
    });

    test('何も起きていなければ読み直さない', () {
      expect(stale, false);
    });

    test('投稿すると読み直す', () {
      postCreated.value++;
      expect(stale, true);
    });

    test('写真を足すと読み直す', () {
      photoAdded.value = {'post1'};
      expect(stale, true);
    });

    test('同じ写真を二度足しても取りこぼさない', () {
      photoAdded.value = {'post1'};
      stale = false;
      photoAdded.value = {'post1', 'post2'};
      expect(stale, true);
    });
  });

  group('読み直す範囲', () {
    const chunkMonths = 3;

    // 読み込み済みのチャンク数ぶん、同じ範囲を取り直す。
    List<int> chunksToRefresh(int loadedChunks) =>
        [for (var c = 0; c < loadedChunks; c++) c];

    test('遡って読んだぶんは捨てずに全部取り直す', () {
      // 12 ヶ月分（4 チャンク）読んでいたら、4 チャンクとも取り直す。
      expect(chunksToRefresh(4), [0, 1, 2, 3]);
      expect(chunksToRefresh(4).length * chunkMonths, 12);
    });

    test('まだ何も読んでいなければ何もしない', () {
      expect(chunksToRefresh(0), isEmpty);
    });

    test('直近 3 ヶ月だけなら 1 チャンク', () {
      expect(chunksToRefresh(1), [0]);
    });
  });
}
