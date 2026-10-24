import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/directus_client.dart';
import '../services/organization_service.dart';
import '../services/workspace_selection_service.dart';
import '../services/wellar_v2_client.dart';
import '../state/app_providers.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../utils/app_feedback.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_wellar_card.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/status_chip.dart';
import '../widgets/wellar_button.dart';
import '../widgets/wellar_card.dart';
import '../widgets/wellar_header.dart';
import 'public_entry_screen.dart';
import 'workspace_picker_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _logoutInProgress = false;
  bool _authProbeTriggered = false;
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
                          child: _buildSwitchOrganizationControl(context),
                        ),
                        const SizedBox(height: 8),
                        WellarButton.primary(
                          text: Tr.t(lang, 'logout'),
                          onPressed: _logoutInProgress
                              ? null
                              : () => _confirmLogout(ref),
                        ),
                        if (kDebugMode) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _authProbeTriggered
                                ? null
                                : _runAuthenticatedNoMediaProbe,
                            icon: const Icon(Icons.shield_outlined),
                            label: Text(
                              _authProbeTriggered
                                  ? 'Auth probe triggered'
                                  : 'Run V2 auth probe once',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runAuthenticatedNoMediaProbe() async {
    if (!kDebugMode || _authProbeTriggered) return;
    setState(() => _authProbeTriggered = true);
    try {
      await WellarV2Client.fromSession().debugAuthenticatedNoMediaProbe();
    } catch (_) {
      // The probe service emits only its sanitized result line.
    }
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

        final memberships = WorkspaceSelectionPolicy.eligibleMemberships(
          result.snapshot!.memberships,
        );
        final visibleOrganizationCount = memberships.length;
        if (kDebugMode) {
          debugPrint(
            '[PROFILE_CHANGE_ORG] multi_org=${visibleOrganizationCount > 1} action=${visibleOrganizationCount > 1 ? 'show_notice' : 'hidden'}',
          );
        }
        if (visibleOrganizationCount <= 1) {
          return const SizedBox.expand();
        }

        return WellarButton.secondary(
          text: 'Switch workspace',
          onPressed: () => Navigator.of(context).push<void>(
            fadeSlideRoute(WorkspacePickerScreen(memberships: memberships)),
          ),
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
    DirectusClient.instance.beginLogout();
    final lang = ref.read(appLanguageControllerProvider).language;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final colors = Theme.of(context).colorScheme;
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
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      fadeSlideRoute(const PublicEntryScreen()),
      (_) => false,
    );
    var remoteLogoutFailed = true;
    try {
      remoteLogoutFailed = await AuthService.instance.logout();
    } catch (_) {
      // Local credentials are cleared by AuthService even if a remote step fails.
    }
    if (remoteLogoutFailed && messenger != null) {
      AppFeedback.showErrorOnMessenger(
        messenger,
        colors,
        lang.isRtl
            ? 'تم تسجيل الخروج من هذا الجهاز، لكن تعذّر إنهاء جلسة الخادم بالكامل.'
            : 'You were signed out on this device, but the server session could not be fully ended.',
      );
    }
  }

  Future<void> _confirmLogout(WidgetRef ref) async {
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
    if (confirmed == true && mounted) {
      await _logout(context, ref);
    }
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
