import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../i18n/tr.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/organization_service.dart';
import '../state/app_language_state.dart';
import '../state/app_providers.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_wellar_card.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/status_chip.dart';
import '../widgets/wellar_button.dart';
import '../widgets/wellar_card.dart';
import '../widgets/wellar_error_state.dart';
import '../widgets/wellar_header.dart';
import '../widgets/wellar_skeleton_shimmer.dart';
import 'login_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _deleteInProgress = false;
  bool _logoutInProgress = false;
  late Future<CanonicalWorkspaceContextResult> _switchableOrganizationsFuture;
  ProviderSubscription? _workspaceSubscription;
  String _workspaceIdentity = '';

  @override
  void initState() {
    super.initState();
    _workspaceIdentity = _workspaceIdentityOf(
      ref.read(activeWorkspaceContextProvider),
    );
    _switchableOrganizationsFuture = _loadSwitchableOrganizations();
    _workspaceSubscription = ref.listenManual<ActiveWorkspaceContext?>(
      activeWorkspaceContextProvider,
      (previous, next) {
        final nextIdentity = _workspaceIdentityOf(next);
        if (nextIdentity == _workspaceIdentity) return;
        if (!mounted) return;
        setState(() {
          _workspaceIdentity = nextIdentity;
          _switchableOrganizationsFuture = _loadSwitchableOrganizations();
        });
      },
    );
  }

  @override
  void dispose() {
    _workspaceSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final workspace = ref.watch(activeWorkspaceContextProvider);
    final lang = ref.watch(appLanguageControllerProvider).language;
    final profile = profileAsync.valueOrNull;
    final workspaceName = workspace?.businessProfileName.isNotEmpty == true
        ? workspace!.businessProfileName
        : Tr.t(lang, 'workspace_default');
    final profileName = _resolvedProfileName(profile, lang);
    final profileEmail = _resolvedProfileEmail(profile);
    final role = _roleLabel(
      workspace?.finalEffectiveRole ?? workspace?.memberRole,
    );
    final initials = _initials(profileName, profileEmail);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          AnimatedWellarScreen(
            showBackground: false,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                WellarHeader(
                  title: Tr.t(lang, 'profile'),
                  subtitle: Tr.t(lang, 'account_workspace_settings'),
                ),
                const SizedBox(height: WellarTheme.sectionGap),
                AnimatedWellarCard(
                  delay: const Duration(milliseconds: 50),
                  child: WellarCard(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: WellarTheme.primary.withValues(
                                  alpha: 0.18,
                                ),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: WellarTheme.primary),
                              ),
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  color: WellarTheme.text,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    profileName.isEmpty
                                        ? Tr.t(lang, 'unknown_user')
                                        : profileName,
                                    style: const TextStyle(
                                      color: WellarTheme.text,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    profileEmail,
                                    style: const TextStyle(
                                      color: WellarTheme.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      StatusChip(role),
                                      StatusChip(workspaceName),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (profileAsync.hasError) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Some profile information is unavailable right now.',
                              style: const TextStyle(
                                color: WellarTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedWellarCard(
                  delay: const Duration(milliseconds: 120),
                  child: WellarCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Tr.t(lang, 'account'),
                          style: const TextStyle(
                            color: WellarTheme.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _row(Tr.t(lang, 'role'), role),
                        _row(Tr.t(lang, 'email'), profileEmail),
                        _row(Tr.t(lang, 'status'), Tr.t(lang, 'active')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedWellarCard(
                  delay: const Duration(milliseconds: 180),
                  child: WellarCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Tr.t(lang, 'workspace'),
                          style: const TextStyle(
                            color: WellarTheme.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _row(Tr.t(lang, 'workspace'), workspaceName),
                        _row(
                          Tr.t(lang, 'department'),
                          workspace?.departmentName?.isNotEmpty == true
                              ? workspace!.departmentName!
                              : '-',
                        ),
                        _row(
                          Tr.t(lang, 'membership'),
                          workspace?.membershipStatus ?? Tr.t(lang, 'active'),
                        ),
                        _row(Tr.t(lang, 'scope'), workspace?.scopeLabel ?? '-'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedWellarCard(
                  delay: const Duration(milliseconds: 195),
                  child: WellarCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Tr.t(lang, 'security_privacy'),
                          style: const TextStyle(
                            color: WellarTheme.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          Tr.t(lang, 'privacy_note'),
                          style: const TextStyle(
                            color: WellarTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedWellarCard(
                  delay: const Duration(milliseconds: 210),
                  child: WellarCard(
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: _buildSwitchOrganizationControl(
                            context,
                          ),
                        ),
                        const SizedBox(height: 8),
                        WellarButton.primary(
                          text: Tr.t(lang, 'logout'),
                          onPressed: (_deleteInProgress || _logoutInProgress)
                              ? null
                              : () => _confirmLogout(context, ref),
                        ),
                        const SizedBox(height: 10),
                        WellarButton.secondary(
                          text: 'Delete account',
                          onPressed: _deleteInProgress
                              ? null
                              : () => _openDeleteAccount(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_deleteInProgress)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(color: WellarTheme.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSwitchOrganizationControl(BuildContext context) {
    return FutureBuilder<CanonicalWorkspaceContextResult>(
      future: _switchableOrganizationsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !snapshot.hasData) {
          return const SizedBox.expand();
        }

        final result = snapshot.data!;
        if (result.status != CanonicalWorkspaceContextStatus.ok ||
            result.snapshot == null) {
          return const SizedBox.expand();
        }

        final visibleOrganizationCount = _countSelectableOrganizations(
          result.snapshot!,
        );
        if (kDebugMode) {
          debugPrint(
            '[PROFILE_CHANGE_ORG] multi_org=${visibleOrganizationCount > 1} action=${visibleOrganizationCount > 1 ? 'show_notice' : 'hidden'}',
          );
        }
        if (visibleOrganizationCount <= 1) {
          return const SizedBox.expand();
        }

        return WellarButton.secondary(
          text: 'Switch organization',
          onPressed: _deleteInProgress
              ? null
              : () => _showSwitchOrganizationNotice(context),
        );
      },
    );
  }

  Future<CanonicalWorkspaceContextResult> _loadSwitchableOrganizations() {
    return OrganizationService.instance.fetchCanonicalWorkspaceContext(
      forceRefresh: true,
    );
  }

  String _workspaceIdentityOf(ActiveWorkspaceContext? workspace) {
    return [
      workspace?.membershipId.trim() ?? '',
      workspace?.businessProfileId.trim() ?? '',
      workspace?.departmentId?.trim() ?? '',
    ].join('|');
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: WellarTheme.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: WellarTheme.text),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  String _resolvedProfileName(UserProfile? profile, dynamic lang) {
    final name = profile?.name.trim() ?? '';
    if (name.isNotEmpty) return name;
    final sessionName = Session.instance.userName?.trim() ?? '';
    if (sessionName.isNotEmpty) return sessionName;
    final email = _resolvedProfileEmail(profile);
    if (email.isNotEmpty) return email;
    return Tr.t(lang, 'unknown_user');
  }

  String _resolvedProfileEmail(UserProfile? profile) {
    final email = profile?.email.trim() ?? '';
    if (email.isNotEmpty) return email;
    final sessionEmail = Session.instance.userEmail?.trim() ?? '';
    if (sessionEmail.isNotEmpty) return sessionEmail;
    return 'Identity unavailable right now';
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    if (_logoutInProgress) return;
    _logoutInProgress = true;
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushAndRemoveUntil(fadeSlideRoute(const LoginScreen()), (_) => false);
    Future.microtask(() {
      ref.read(activeWorkspaceContextProvider.notifier).state = null;
      ref.read(refreshTickProvider.notifier).state++;
      ref.read(latestScanResultProvider.notifier).state = null;
      ref.read(notificationReadOverrideProvider.notifier).state = <String>{};
      ref.read(localNotificationsProvider.notifier).state = const [];
      ref.invalidate(profileProvider);
      ref.invalidate(notificationsProvider);
      ref.invalidate(ownerHistoryTimelineProvider);
      ref.invalidate(historyTimelineProvider);
      ref.invalidate(homeDataProvider);
      ref.invalidate(incomingRequestsProvider);
      ref.invalidate(sentRequestsProvider);
      ref.invalidate(alertsProvider);
    });
    unawaited(AuthService.instance.logout());
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final lang = ref.read(appLanguageControllerProvider).language;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: WellarTheme.surface,
        title: Text(
          Tr.t(lang, 'logout_confirm_title'),
          style: const TextStyle(color: WellarTheme.text),
        ),
        content: Text(
          Tr.t(lang, 'logout_confirm_body'),
          style: const TextStyle(color: WellarTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(Tr.t(lang, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _logout(context, ref);
    }
  }

  int _countSelectableOrganizations(
    CanonicalWorkspaceContextSnapshot snapshot,
  ) {
    final organizationIds = <String>{};
    for (final membership in snapshot.memberships) {
      final status = membership.status.trim().toLowerCase();
      final role = membership.memberRole.trim().toLowerCase();
      if (status.isNotEmpty && status != 'active' && status != 'accepted') {
        continue;
      }
      final organizationId = membership.businessProfileId.trim();
      if (organizationId.isEmpty) continue;
      if (!(role == 'owner' ||
          role == 'hr' ||
          role == 'manager' ||
          role == 'manger' ||
          role == 'employee')) {
        continue;
      }
      organizationIds.add(organizationId);
    }
    return organizationIds.length;
  }

  Future<void> _openDeleteAccount(BuildContext context) async {
    if (_deleteInProgress) return;
    final rawUrl = AppConfig.accountDeletionUrl.trim();
    final parsed = rawUrl.isEmpty ? null : Uri.tryParse(rawUrl);
    final urlIsHttps =
        parsed != null &&
        parsed.hasScheme &&
        parsed.scheme.toLowerCase() == 'https' &&
        parsed.host.isNotEmpty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WellarTheme.surface,
        title: const Text(
          'Delete your account',
          style: TextStyle(
            color: WellarTheme.text,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          'This will permanently delete your Wellar account and personal data '
          'associated with it, subject to any legally required retention. '
          'Continuing will open the secure account deletion page.',
          style: TextStyle(color: WellarTheme.textMuted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Continue',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    if (!urlIsHttps) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: WellarTheme.surface,
          title: const Text(
            'Account deletion not configured',
            style: TextStyle(
              color: WellarTheme.text,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: const Text(
            'Account deletion is not available in this build. Please contact '
            'your Wellar administrator to have your account removed.',
            style: TextStyle(color: WellarTheme.textMuted, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _deleteInProgress = true);
    try {
      final launched = await launchUrl(
        parsed,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open the account deletion page. Try again later.',
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open the account deletion page. Try again later.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleteInProgress = false);
    }
  }

  Future<void> _showSwitchOrganizationNotice(BuildContext context) async {
    if (_deleteInProgress) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: WellarTheme.surface,
        title: const Text(
          'Switch organization on the web',
          style: TextStyle(
            color: WellarTheme.text,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          'Organization switching is currently available in the Wellar web app. Please switch to your preferred organization on the web, then reopen the mobile app.',
          style: TextStyle(color: WellarTheme.textMuted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  String _roleLabel(String? role) {
    final r = role?.trim().toLowerCase() ?? '';
    if (r == 'owner') return 'Owner';
    if (r == 'hr') return 'HR';
    if (r == 'manager' || r == 'manger') return 'Manager';
    if (r == 'employee') return 'Employee';
    return 'Role unavailable';
  }

  String _initials(String name, String email) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isNotEmpty) {
      return parts.map((e) => e[0]).take(2).join().toUpperCase();
    }
    if (email.isNotEmpty) return email[0].toUpperCase();
    return 'U';
  }
}
