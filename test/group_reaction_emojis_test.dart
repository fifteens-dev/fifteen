import 'package:flutter_test/flutter_test.dart';
import 'package:fifteen/models/post_model.dart';
import 'package:fifteen/widgets/home/group_home_view.dart';

PostReaction _r(String uid, String emoji, int ts) =>
    PostReaction(userId: uid, emoji: emoji, ts: ts);

void main() {
  const mates = {'a', 'b', 'c', 'd'};

  test('多い順に並び、同じ絵文字は 1 つにまとまる', () {
    final out = groupReactionEmojis([
      _r('a', '🔥', 1),
      _r('b', '😭', 2),
      _r('c', '😭', 3),
    ], mates);
    expect(out, ['😭', '🔥']);
  });

  test('グループ外の人のリアクションは数えない', () {
    final out = groupReactionEmojis([
      _r('a', '🔥', 1),
      _r('x', '👍', 2),
      _r('y', '👍', 3),
    ], mates);
    expect(out, ['🔥']);
  });

  test('同数なら新しく付いた方が先', () {
    final out = groupReactionEmojis([
      _r('a', '🔥', 1),
      _r('b', '😭', 5),
    ], mates);
    expect(out, ['😭', '🔥']);
  });

  test('最大数で切る', () {
    final out = groupReactionEmojis([
      for (final (i, e) in ['1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣'].indexed)
        _r('a', e, i),
    ], mates, max: 4);
    expect(out.length, 4);
  });
}
