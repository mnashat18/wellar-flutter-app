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

  testWidgets('unauthenticated join path requires sign in before workspace access', (
    WidgetTester tester,
  ) async {
    await _prepareSession();

    await tester.pumpWidget(_wrappedIntent());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Join an organisation'));
    await tester.pumpAndSettle();
    // WorkspaceAccessScreen has an authenticated-user guard and redirects an
    // anonymous visitor to sign in before showing invite/workspace controls.
    expect(find.byType(WorkspaceAccessScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 10)));

  testWidgets('registration enables submit on the final password character', (
    WidgetTester tester,
  ) async {
    await _prepareSession();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLanguageControllerProvider.overrideWith(
            (ref) => AppLanguageController(
              initialLanguage: AppLanguage.english,
              loaded: true,
            ),
          ),
        ],
        child: const MaterialApp(home: RegisterScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(5));
    await tester.ensureVisible(fields.at(0));
    await tester.enterText(fields.at(0), 'Riley');
    await tester.ensureVisible(fields.at(1));
    await tester.enterText(fields.at(1), 'Wellar');
    await tester.ensureVisible(fields.at(2));
    await tester.enterText(fields.at(2), 'riley@example.com');
    await tester.ensureVisible(fields.at(3));
    await tester.enterText(fields.at(3), 'Password123');
    final legalCheckbox = find.byType(CheckboxListTile);
    await tester.ensureVisible(legalCheckbox);
    await tester.tap(legalCheckbox);
    await tester.pump();

    await tester.ensureVisible(fields.at(4));
    await tester.enterText(fields.at(4), 'Password12');
    await tester.pump();

    final submitButton = find.ancestor(
      of: find.text('Create account'),
      matching: find.byType(InkWell),
    );
    expect(submitButton, findsOneWidget);
    expect(tester.widget<InkWell>(submitButton).onTap, isNull);
    expect(tester.widget<TextField>(fields.at(4)).focusNode?.hasFocus, isTrue);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Password123',
        selection: TextSelection.collapsed(offset: 11),
      ),
    );
    await tester.pump();

    expect(tester.widget<TextField>(fields.at(4)).focusNode?.hasFocus, isTrue);
    expect(tester.widget<InkWell>(submitButton).onTap, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 15)));

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
