// This is a basic Flutter widget test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fifteen/main.dart';

void main() {
  testWidgets('Phone auth screen smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FifteenApp());

    // Verify that the app title is displayed.
    expect(find.text('15s'), findsOneWidget);

    // Verify that the instruction text is displayed.
    expect(find.text('電話番号を入力してください'), findsOneWidget);

    // Verify that the button is displayed.
    expect(find.text('認証メッセージを送信'), findsOneWidget);
  });
}
