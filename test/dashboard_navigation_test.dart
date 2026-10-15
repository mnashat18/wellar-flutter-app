import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waller_app/screens/role_based_shells.dart';
import 'package:waller_app/services/organization_service.dart';
import 'package:waller_app/state/app_language_state.dart';
import 'package:waller_app/state/app_providers.dart';
import 'package:waller_app/utils/dashboard_navigation.dart';

class _NavigationObserver extends NavigatorObserver {
  final pushedRoutes = <Route<dynamic>>[];
  final removedRoutes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    removedRoutes.add(route);
  }
}

class _HomeHarness extends StatelessWidget {
  const _HomeHarness();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const _ScanHarness()),
          ),
          child: const Text('Open scan'),
        ),
      ),
    );
  }
}

class _ScanHarness extends StatelessWidget {
  const _ScanHarness();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Deep scan route'),
            TextButton(
              onPressed: () => goToDashboard(context),
              child: const Text('Back to dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('dashboard action replaces the deep stack with the role root', (
    tester,
  ) async {
    const workspace = ActiveWorkspaceContext(
      currentUserId: 'user-1',
      currentUserEmail: 'person@example.com',
      currentUserFirstName: 'Test',
      currentUserLastName: 'Person',
      directusRoleId: null,
      directusRoleName: null,
      membershipUserId: 'user-1',
      businessProfileId: 'workspace-1',
      businessProfileName: 'Example Workspace',
      businessProfileStatus: 'active',
      businessPlanCode: null,
      businessBillingStatus: null,
      membershipId: 'membership-1',
      memberRole: 'employee',
      membershipRole: 'employee',
      finalEffectiveRole: 'test-placeholder',
      membershipStatus: 'active',
      departmentId: null,
      departmentName: null,
      scopeLabel: 'workspace',
    );
    final observer = _NavigationObserver();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceContextProvider.overrideWith((ref) => workspace),
          appLanguageControllerProvider.overrideWith(
            (ref) => AppLanguageController(
              initialLanguage: AppLanguage.english,
              loaded: true,
            ),
          ),
        ],
        child: MaterialApp(
          navigatorObservers: [observer],
          home: const _HomeHarness(),
        ),
      ),
    );
    await tester.tap(find.text('Open scan'));
    await tester.pumpAndSettle();
    expect(find.text('Deep scan route'), findsOneWidget);

    await tester.tap(find.text('Back to dashboard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byType(RoleShellRouter), findsOneWidget);
    final router = tester.widget<RoleShellRouter>(find.byType(RoleShellRouter));
    expect(router.initialContext, same(workspace));
    expect(observer.pushedRoutes.last.settings.name, roleShellRootRouteName);
    expect(observer.removedRoutes, hasLength(2));
  });
}
