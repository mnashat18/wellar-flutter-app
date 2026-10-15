import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/role_based_shells.dart';
import '../state/app_providers.dart';

const String roleShellRootRouteName = '/role-shell-root';

void goToDashboard(BuildContext context) {
  final workspace = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(activeWorkspaceContextProvider);
  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: roleShellRootRouteName),
      builder: (_) => RoleShellRouter(initialContext: workspace),
    ),
    (route) => false,
  );
}
