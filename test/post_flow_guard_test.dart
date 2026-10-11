import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 最終確認画面はホームを作り直してから上に載る。作り直されたホームは
/// initState で「未投稿なら投稿フローを開く」を走らせるので、曲選びに
/// 戻されないよう、開いている間は止めている。
///
/// その仕組みは「フラグがホームの initState より先に立つ」ことに乗って
/// いる。Navigator の操作と initState の順序を実際に動かして確かめる。
void main() {
  testWidgets('作り直されたホームの initState から、確認画面の印が見える', (t) async {
    var openCount = 0;
    bool isOpen() => openCount > 0;

    // 作り直されたホームが initState で見た値
    bool? seenByHome;

    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      routes: {
        '/': (_) => const _Probe(label: '最初の画面'),
        '/home': (_) => _Probe(
              label: 'ホーム',
              onInit: () => seenByHome ??= isOpen(),
            ),
      },
    ));
    await t.pumpAndSettle();

    // MoodPostFinalPreviewScreen.open と同じ順序
    nav.currentState!.pushNamedAndRemoveUntil('/home', (r) => false);
    openCount++;
    final pushed = nav.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const _Probe(label: '確認画面'),
    ))..whenComplete(() {
        if (openCount > 0) openCount--;
      });
    await t.pumpAndSettle();

    expect(seenByHome, true,
        reason: 'ホームの initState の時点で印が立っていないと、曲選びに戻される');

    // 閉じたら印が降りる
    nav.currentState!.pop();
    await t.pumpAndSettle();
    await pushed;
    expect(isOpen(), false);
  });

  testWidgets('二重に開いても、両方閉じるまで印は降りない', (t) async {
    var openCount = 0;
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: const _Probe(label: '最初の画面'),
    ));
    await t.pumpAndSettle();

    for (var i = 0; i < 2; i++) {
      openCount++;
      nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const _Probe(label: '確認画面'),
      )).whenComplete(() {
        if (openCount > 0) openCount--;
      });
    }
    await t.pumpAndSettle();
    expect(openCount, 2);

    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(openCount, 1, reason: '1 枚閉じただけでは降りない');

    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(openCount, 0);
  });
}

class _Probe extends StatefulWidget {
  final String label;
  final VoidCallback? onInit;
  const _Probe({required this.label, this.onInit});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit?.call();
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(widget.label))); 
}
