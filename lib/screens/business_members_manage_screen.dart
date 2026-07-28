import 'package:flutter/material.dart';

import '../models/business_profile.dart';
import '../models/business_profile_member.dart';
import '../services/organization_service.dart';
import '../services/subscription_service.dart';
import '../state/session.dart';
import '../utils/app_colors.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import '../widgets/state_views.dart';

class BusinessMembersManageScreen extends StatefulWidget {
  const BusinessMembersManageScreen({super.key});

  @override
  State<BusinessMembersManageScreen> createState() =>
      _BusinessMembersManageScreenState();
}

class _BusinessMembersManageScreenState
    extends State<BusinessMembersManageScreen> {
  static const _roles = ['Owner', 'Admin', 'Manager', 'Member'];

  final _emailController = TextEditingController();
  String _selectedRole = _roles.last;
  bool _saving = false;
  String? _errorMessage;
  List<BusinessProfileMember> _members = const [];
  bool _loading = true;
  bool _subscriptionExpired = false;
  String? _myRole;
  String? _myStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    try {
      final subscription = await SubscriptionService.instance
          .fetchActiveSubscription();
      final access = SubscriptionService.instance.accessForSubscription(
        subscription,
      );

      final profile = await OrganizationService.instance
          .fetchPrimaryBusinessProfile(forceRefresh: force);
      if (profile == null || profile.id.trim().isEmpty) {
        if (!mounted) return;
        setState(() {
          _members = const [];
          _myRole = null;
          _myStatus = null;
          _subscriptionExpired = access.isExpired;
          _loading = false;
        });
        return;
      }

      List<BusinessProfileMember> members = const [];
      String? membersError;
      try {
        members = await OrganizationService.instance.fetchBusinessMembers(
          businessProfileId: profile.id,
          limit: 200,
        );
      } catch (e) {
        membersError = e.toString();
      }

      final selfAccess = await _resolveSelfAccess(
        businessProfileId: profile.id,
        profile: profile,
        members: members,
      );

      if (!mounted) return;
      setState(() {
        final visible = _buildVisibleMembers(
          profile: profile,
          rawMembers: members,
          selfAccess: selfAccess,
        );
        _members = _selfOnlyMembers(
          profile: profile,
          visibleMembers: visible,
          selfAccess: selfAccess,
        );
        _myRole = selfAccess.role;
        _myStatus = selfAccess.status;
        _subscriptionExpired = access.isExpired;
        _loading = false;
        _errorMessage = membersError;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _members = const [];
        _myRole = null;
        _myStatus = null;
        _subscriptionExpired = false;
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _saveMember() async {
    if (!mounted) return;
    _showComingSoonDialog();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: RefreshIndicator(
              color: AppColors.primarySoft,
              onRefresh: () => _load(force: true),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(
                            Icons.arrow_back_ios_new,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Team Members',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_roleSummary()}. Showing your account only. Team management coming soon.',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _countChip(_members.length),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_subscriptionExpired) ...[
                      _expiredBanner(),
                      const SizedBox(height: 12),
                    ],
                    if (_loading)
                      const SkeletonList()
                    else if (_errorMessage != null && _members.isEmpty)
                      StatusCard(
                        title: 'Unable to load members',
                        message: _errorMessage!,
                        icon: Icons.warning_amber_rounded,
                        iconColor: AppColors.highRisk,
                        actionText: 'Retry',
                        onAction: () => _load(force: true),
                      )
                    else ...[
                      _buildMembersTable(),
                      const SizedBox(height: 12),
                      _buildForm(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersTable() {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Team',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppColors.backgroundAlt.withOpacity(0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                _tableHeader(),
                if (_members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'No members yet.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  ..._members.map(_tableRow),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              'MEMBER',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'ROLE',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'STATUS',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableRow(BusinessProfileMember member) {
    final isYou = _isCurrentUser(member);
    final baseLabel = (member.userEmail ?? member.displayName).trim().isEmpty
        ? member.displayName
        : member.userEmail!;
    final label = isYou ? '$baseLabel (You)' : baseLabel;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _titleCase(member.memberRole),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _titleCase(member.status),
              style: TextStyle(
                color: member.status.toLowerCase() == 'active'
                    ? AppColors.stable
                    : AppColors.lowFocus,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add / Update Member',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Member Email',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          _fieldShell(
            child: TextField(
              enabled: !_saving,
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'member@company.com',
                hintStyle: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Role',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          _fieldShell(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedRole,
                isExpanded: true,
                dropdownColor: AppColors.cardAlt,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                items: _roles
                    .map(
                      (role) => DropdownMenuItem<String>(
                        value: role,
                        child: Text(role),
                      ),
                    )
                    .toList(),
                onChanged: !_saving
                    ? (value) {
                        if (value == null) return;
                        setState(() => _selectedRole = value);
                      }
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Role selection is disabled for now. Team management is coming soon.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(
                color: AppColors.highRisk,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            text: 'Save Member',
            isLoading: _saving,
            onPressed: _saving ? null : _saveMember,
          ),
        ],
      ),
    );
  }

  Widget _fieldShell({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: child,
    );
  }

  Widget _countChip(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primarySoft.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primarySoft.withOpacity(0.45)),
      ),
      child: Text(
        '$count members',
        style: const TextStyle(
          color: AppColors.primarySoft,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _expiredBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.highRisk.withOpacity(0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.highRisk.withOpacity(0.6)),
      ),
      child: const Text(
        'Your subscription has expired. Upgrade now.',
        style: TextStyle(
          color: AppColors.highRisk,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _titleCase(String value) {
    final v = value.trim();
    if (v.isEmpty) return '-';
    return v[0].toUpperCase() + v.substring(1).toLowerCase();
  }

  Future<_SelfAccess> _resolveSelfAccess({
    required String businessProfileId,
    required BusinessProfile profile,
    required List<BusinessProfileMember> members,
  }) async {
    final currentUserId = Session.instance.userId?.trim() ?? '';
    if (currentUserId.isEmpty) {
      return const _SelfAccess(role: null, status: null, canManage: false);
    }

    final ownerUserId = profile.ownerUserId?.trim() ?? '';
    if (ownerUserId.isNotEmpty && ownerUserId == currentUserId) {
      return const _SelfAccess(
        role: 'owner',
        status: 'active',
        canManage: true,
      );
    }

    final direct = _findMembershipInList(members, currentUserId);
    if (direct != null) {
      final canManage = _hasManagePermission(direct.memberRole, direct.status);
      return _SelfAccess(
        role: direct.memberRole,
        status: direct.status,
        canManage: canManage,
      );
    }

    try {
      final mine = await OrganizationService.instance
          .fetchMyBusinessMemberships(limit: 200);
      BusinessProfileMember? current;
      for (final membership in mine) {
        final profileId = membership.businessProfileId.trim();
        if (profileId.isNotEmpty && profileId == businessProfileId) {
          current = membership;
          break;
        }
      }
      if (current != null) {
        final canManage = _hasManagePermission(
          current.memberRole,
          current.status,
        );
        return _SelfAccess(
          role: current.memberRole,
          status: current.status,
          canManage: canManage,
        );
      }
    } catch (_) {
      // Best-effort role resolution.
    }

    return const _SelfAccess(role: null, status: null, canManage: false);
  }

  List<BusinessProfileMember> _buildVisibleMembers({
    required BusinessProfile profile,
    required List<BusinessProfileMember> rawMembers,
    required _SelfAccess selfAccess,
  }) {
    final currentUserId = Session.instance.userId?.trim() ?? '';
    final currentEmail = Session.instance.userEmail?.trim().toLowerCase() ?? '';
    final map = <String, BusinessProfileMember>{};

    String keyFor(BusinessProfileMember member) {
      final userId = member.userId.trim();
      if (userId.isNotEmpty) return 'u:$userId';
      final email = member.userEmail?.trim().toLowerCase() ?? '';
      if (email.isNotEmpty) return 'e:$email';
      final id = member.id.trim();
      if (id.isNotEmpty) return 'i:$id';
      return 'x:${map.length}';
    }

    void put(BusinessProfileMember member) {
      map[keyFor(member)] = member;
    }

    for (final member in rawMembers) {
      put(member);
    }

    final ownerUserId = profile.ownerUserId?.trim() ?? '';
    if (ownerUserId.isNotEmpty &&
        !map.containsKey('u:$ownerUserId') &&
        !_containsEmail(map.values, profile.workEmail)) {
      put(
        BusinessProfileMember(
          id: 'synthetic-owner-${profile.id}',
          businessProfileId: profile.id,
          userId: ownerUserId,
          userEmail: profile.workEmail,
          userFirstName: null,
          userLastName: null,
          memberRole: 'owner',
          status: 'active',
        ),
      );
    }

    if (currentUserId.isNotEmpty || currentEmail.isNotEmpty) {
      final selfInList =
          (currentUserId.isNotEmpty && map.containsKey('u:$currentUserId')) ||
          (currentEmail.isNotEmpty && map.containsKey('e:$currentEmail')) ||
          _containsEmail(map.values, currentEmail);
      if (!selfInList) {
        put(
          BusinessProfileMember(
            id: 'synthetic-self-${profile.id}',
            businessProfileId: profile.id,
            userId: currentUserId,
            userEmail: currentEmail.isEmpty
                ? Session.instance.userEmail
                : currentEmail,
            userFirstName: null,
            userLastName: null,
            memberRole: (selfAccess.role ?? 'member').trim(),
            status: (selfAccess.status ?? 'active').trim(),
          ),
        );
      }
    }

    final items = map.values.toList();
    items.sort((a, b) {
      final aSelf = _isCurrentUser(a);
      final bSelf = _isCurrentUser(b);
      if (aSelf && !bSelf) return -1;
      if (!aSelf && bSelf) return 1;
      final roleCmp = _roleRank(
        a.memberRole,
      ).compareTo(_roleRank(b.memberRole));
      if (roleCmp != 0) return roleCmp;
      return _memberLabel(
        a,
      ).toLowerCase().compareTo(_memberLabel(b).toLowerCase());
    });
    return items;
  }

  List<BusinessProfileMember> _selfOnlyMembers({
    required BusinessProfile profile,
    required List<BusinessProfileMember> visibleMembers,
    required _SelfAccess selfAccess,
  }) {
    final self = visibleMembers.where(_isCurrentUser).toList();
    if (self.isNotEmpty) return [self.first];

    final currentUserId = Session.instance.userId?.trim() ?? '';
    final currentEmail = Session.instance.userEmail?.trim();
    return [
      BusinessProfileMember(
        id: 'self-only-${profile.id}',
        businessProfileId: profile.id,
        userId: currentUserId,
        userEmail: currentEmail,
        userFirstName: null,
        userLastName: null,
        memberRole: (selfAccess.role ?? 'member').trim(),
        status: (selfAccess.status ?? 'active').trim(),
      ),
    ];
  }

  bool _containsEmail(Iterable<BusinessProfileMember> members, String? email) {
    final value = email?.trim().toLowerCase() ?? '';
    if (value.isEmpty) return false;
    for (final member in members) {
      final candidate = member.userEmail?.trim().toLowerCase() ?? '';
      if (candidate == value) return true;
    }
    return false;
  }

  bool _isCurrentUser(BusinessProfileMember member) {
    final currentUserId = Session.instance.userId?.trim() ?? '';
    final currentEmail = Session.instance.userEmail?.trim().toLowerCase() ?? '';
    if (currentUserId.isNotEmpty && member.userId.trim() == currentUserId) {
      return true;
    }
    final email = member.userEmail?.trim().toLowerCase() ?? '';
    return currentEmail.isNotEmpty && email == currentEmail;
  }

  int _roleRank(String role) {
    final normalized = role.trim().toLowerCase();
    if (normalized.contains('owner')) return 0;
    if (normalized == 'admin') return 1;
    if (normalized == 'manager') return 2;
    return 3;
  }

  String _memberLabel(BusinessProfileMember member) {
    final email = member.userEmail?.trim();
    if (email != null && email.isNotEmpty) return email;
    return member.displayName;
  }

  BusinessProfileMember? _findMembershipInList(
    List<BusinessProfileMember> members,
    String userId,
  ) {
    for (final member in members) {
      if (member.userId.trim() == userId) return member;
    }
    return null;
  }

  bool _hasManagePermission(String role, String status) {
    return _isOwnerRole(role) && _isMemberActive(status);
  }

  bool _isOwnerRole(String role) {
    final normalized = role.trim().toLowerCase();
    return normalized == 'owner' ||
        normalized == 'business_owner' ||
        normalized == 'team_owner' ||
        normalized.endsWith('_owner') ||
        normalized.contains('owner');
  }

  bool _isMemberActive(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'active';
  }

  String _roleSummary() {
    final role = _myRole?.trim();
    final status = _myStatus?.trim();
    if (role == null || role.isEmpty) {
      return 'Your role: not linked yet';
    }
    if (status != null && status.isNotEmpty) {
      return 'Your role: ${_titleCase(role)} (${_titleCase(status)})';
    }
    return 'Your role: ${_titleCase(role)}';
  }

  void _showComingSoonDialog() {
    showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Coming Soon',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Team member invitations will be available in a future update.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'OK',
                style: TextStyle(
                  color: AppColors.primarySoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SelfAccess {
  final String? role;
  final String? status;
  final bool canManage;

  const _SelfAccess({
    required this.role,
    required this.status,
    required this.canManage,
  });
}
