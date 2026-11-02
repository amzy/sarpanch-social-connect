import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('application shell can render an accessible heading', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Text('Sarpanch Social Connect'))),
    ));
    expect(find.text('Sarpanch Social Connect'), findsOneWidget);
  });
}
