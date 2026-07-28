import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../services/member_identity_service.dart';
import 'owner/owner_design_system.dart';

class WorkforceMemberCardData {
  final String name;
  final String email;
  final String status;
  final String department;
  final String role;
  final String latestReadiness;
  final String lastCheck;
  final String membershipId;
  final String userId;
  final bool requiresLinking;
  final Color accent;

  const WorkforceMemberCardData({
    required this.name,
    required this.email,
    required this.status,
    required this.department,
    required this.role,
    required this.latestReadiness,
    required this.lastCheck,
    required this.membershipId,
    required this.userId,
    required this.requiresLinking,
    required this.accent,
  });
}

class WorkforceMemberCard extends StatelessWidget {
  final WorkforceMemberCardData data;

  const WorkforceMemberCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final metadata = '${_roleLabel(data.role)} • ${data.department} • ${data.membershipId}';

    return OwnerSurfaceCard(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xC4111B31), Color(0xB9132036)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(label: data.name, size: 50, accent: data.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WellarTheme.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      data.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WellarTheme.textMuted,
                        fontSize: 12.5,
                        height: 1.2,
                      ),
                    ),
                    if (data.requiresLinking) ...[
                      const SizedBox(height: 7),
                      Text(
                        metadata,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8FA4C7),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _statusBadge(data.status),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _softBadge(
                label: data.department,
                icon: Icons.apartment_rounded,
                color: const Color(0xFF8FB7FF),
                maxWidth: 190,
              ),
              _softBadge(
                label: _roleLabel(data.role),
                icon: Icons.verified_user_rounded,
                color: const Color(0xFF6EE7D1),
                maxWidth: 150,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _infoPanel(
                  title: 'Latest Readiness',
                  value: data.latestReadiness,
                  icon: Icons.favorite_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _infoPanel(
                  title: 'Last Check',
                  value: data.lastCheck,
                  icon: Icons.schedule_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  context: context,
                  label: 'View Details',
                  icon: Icons.open_in_new_rounded,
                  onTap: () => _showDetails(context, metadata),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  context: context,
                  label: 'Copy ID',
                  icon: Icons.copy_rounded,
                  onTap: () => _copyMembershipId(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String rawStatus) {
    final normalized = rawStatus.trim().toLowerCase();
    final isActive = normalized == 'active';
    final label = isActive ? 'Active' : 'Pending';
    final color = isActive
        ? const Color(0xFF6EE7A8)
        : const Color(0xFFFFC46B);
    return TonePill(
      label: label,
      color: color,
      fontSize: 11,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    );
  }

  Widget _softBadge({
    required String label,
    required IconData icon,
    required Color color,
    required double maxWidth,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoPanel({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0x12FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: const Color(0xFF8FA4C7)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WellarTheme.textMuted,
                    fontSize: 10.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: WellarTheme.text,
              fontSize: 12.6,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0x12FFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x12FFFFFF)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: WellarTheme.text),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WellarTheme.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyMembershipId(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: data.membershipId));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Membership ID copied')),
    );
  }

  Future<void> _showDetails(BuildContext context, String metadata) async {
    await showPremiumBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InitialsAvatar(
                    label: data.name,
                    size: 44,
                    accent: data.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: WellarTheme.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          data.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: WellarTheme.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (data.requiresLinking) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0x14FFC46B),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x28FFC46B)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        MemberIdentityService.memberProfileUnavailableLabel,
                        style: TextStyle(
                          color: Color(0xFFFFD28B),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        metadata,
                        style: const TextStyle(
                          color: Color(0xFFBFCBE0),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _detailRow('Status', _statusLabel(data.status)),
              _detailRow('Role', _roleLabel(data.role)),
              _detailRow('Department', data.department),
              _detailRow('Latest Readiness', data.latestReadiness),
              _detailRow('Last Check', data.lastCheck),
              _detailRow('Membership ID', data.membershipId),
              if (data.userId.trim().isNotEmpty) _detailRow('User ID', data.userId),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: WellarTheme.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String rawStatus) {
    return rawStatus.trim().toLowerCase() == 'active' ? 'Active' : 'Pending';
  }

  String _roleLabel(String rawRole) {
    switch (rawRole.trim().toLowerCase()) {
      case 'owner':
        return 'Owner';
      case 'admin':
      case 'hr':
        return 'HR';
      case 'manager':
      case 'manger':
        return 'Manager';
      default:
        return 'Employee';
    }
  }
}
