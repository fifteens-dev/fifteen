import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// AddPhotoFlow.pick が頼っている順序:
//   push した画面が pop() してからコールバックを呼ぶ
//   → await push が返るときには値が入っている
void main() {
  testWidgets('pop してからのコールバックが await に間に合う', (tester) async {
    String? captured;
    late BuildContext ctx;

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));

    Future<String?> pick() async {
      String? value;
      await Navigator.of(ctx).push<void>(MaterialPageRoute(
        builder: (inner) => ElevatedButton(
          onPressed: () {
            Navigator.of(inner).pop();
            value = 'photo.jpg'; // onPhotoTaken 相当
          },
          child: const Text('shutter'),
        ),
      ));
      return value;
    }

    final future = pick().then((v) => captured = v);
    await tester.pumpAndSettle();
    await tester.tap(find.text('shutter'));
    await tester.pumpAndSettle();
    await future;

    expect(captured, 'photo.jpg');
  });
}
