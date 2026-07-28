import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:waller_app/screens/push_diagnostics_screen.dart';

void main() {
  testWidgets('push diagnostics screen does not expose raw token actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PushDiagnosticsScreen()));

    expect(find.text('Push diagnostics'), findsOneWidget);
    expect(find.text('Copy FCM test token'), findsNothing);
    expect(
      find.textContaining('Token values are never shown here.'),
      findsOneWidget,
    );
  });
}
