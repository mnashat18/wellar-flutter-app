import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:waller_app/screens/auth_intent_screen.dart';
import 'package:waller_app/screens/auth_welcome_screen.dart';
import 'package:waller_app/screens/login_screen.dart';
import 'package:waller_app/screens/register_screen.dart';
import 'package:waller_app/state/app_language_state.dart';
import 'package:waller_app/state/app_providers.dart';
import 'package:waller_app/screens/workspace_access_screen.dart';
import 'package:waller_app/state/session.dart';

class _DestinationScreen extends StatelessWidget {
  const _DestinationScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('Destination reached'));
  }
}

Future<void> _prepareSession() async {
  setupFirebaseCoreMocks();
  FlutterSecureStorage.setMockInitialValues({});
  await Firebase.initializeApp();
  await Session.init();
}

void main() {
  Widget _wrappedIntent() {
    return ProviderScope(
      overrides: [
        appLanguageControllerProvider.overrideWith(
          (ref) => AppLanguageController(
            initialLanguage: AppLanguage.english,
            loaded: true,
          ),
        ),
      ],
      child: const MaterialApp(home: AuthIntentScreen()),
    );
  }

  testWidgets('auth intent create path opens register screen', (
    WidgetTester tester,
  ) async {
    await _prepareSession();

    await tester.pumpWidget(_wrappedIntent());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create an organisation'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
  });

  testWidgets('auth intent sign in path opens login screen', (
    WidgetTester tester,
  ) async {
    await _prepareSession();

    await tester.pumpWidget(_wrappedIntent());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('auth intent join path opens workspace access screen', (
    WidgetTester tester,
  ) async {
    await _prepareSession();

    await tester.pumpWidget(_wrappedIntent());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Join an organisation'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceAccessScreen), findsOneWidget);
  });

  testWidgets('welcome screen auto-continues to the next screen', (
    WidgetTester tester,
  ) async {
    await _prepareSession();

    await tester.pumpWidget(
      const MaterialApp(
        home: AuthWelcomeScreen(
          headline: 'Welcome back',
          body: 'Your account is ready.',
          primaryLabel: 'Continue',
          nextScreen: _DestinationScreen(),
          autoContinueDelay: Duration(milliseconds: 20),
        ),
      ),
    );

    expect(find.text('Welcome back'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();

    expect(find.text('Destination reached'), findsOneWidget);
  });
}
