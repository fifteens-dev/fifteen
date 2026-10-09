import 'package:flutter_test/flutter_test.dart';

/// 他人のプロフィールは相手との関係で見せるものが変わる。
/// 判定は following / followers の組み合わせだけで決まる。
enum Relation { none, pending, friend }

Relation relationOf({required bool iFollow, required bool followsMe}) {
  if (iFollow && followsMe) return Relation.friend;
  if (iFollow) return Relation.pending;
  return Relation.none;
}

void main() {
  test('追加していなければ未追加', () {
    expect(relationOf(iFollow: false, followsMe: false), Relation.none);
  });

  test('相手からだけ来ていても、自分が追加していなければ未追加', () {
    // 相手が先に追加してきた状態。こちらは「＋追加」を出して返せるようにする。
    expect(relationOf(iFollow: false, followsMe: true), Relation.none);
  });

  test('自分から追加しただけなら承認待ち', () {
    expect(relationOf(iFollow: true, followsMe: false), Relation.pending);
  });

  test('相互なら友達', () {
    expect(relationOf(iFollow: true, followsMe: true), Relation.friend);
  });

  test('追加を押した直後は承認待ちになる', () {
    // 押す前は未追加、押した瞬間に iFollow が立つ。
    var iFollow = false;
    expect(relationOf(iFollow: iFollow, followsMe: false), Relation.none);
    iFollow = true;
    expect(relationOf(iFollow: iFollow, followsMe: false), Relation.pending);
  });
}
