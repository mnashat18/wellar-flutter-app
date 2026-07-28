// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:waller_app/main.dart';
import 'package:waller_app/screens/public_home_screen.dart';
import 'package:waller_app/screens/splash_screen.dart';
import 'package:waller_app/state/app_language_state.dart';
import 'package:waller_app/state/session.dart';

void main() {
  testWidgets('App shows splash screen', (WidgetTester tester) async {
    final originalErrorWidgetBuilder = ErrorWidget.builder;
    try {
      setupFirebaseCoreMocks();
      FlutterSecureStorage.setMockInitialValues({});
      await Firebase.initializeApp();
      await Session.init();

      await tester.pumpWidget(
        MyApp(
          languageController: AppLanguageController(
            initialLanguage: AppLanguage.english,
            loaded: true,
          ),
        ),
      );

      expect(find.byType(SplashScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 6000));
      await tester.pump();

      expect(find.byType(PublicHomeScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      ErrorWidget.builder = originalErrorWidgetBuilder;
    }
  });
}
