import 'package:flutter/material.dart';

import '../models/invite_details.dart';
import '../services/invite_service.dart';
import '../state/session.dart';
import '../utils/app_colors.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import '../widgets/fade_slide.dart';
import '../widgets/lux_header.dart';
import '../widgets/state_views.dart';
import '../utils/page_transition.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'scan_flow_impl_normalized.dart';
import 'role_based_shells.dart';

class InviteScreen extends StatefulWidget {
  final String token;

  const InviteScreen({super.key, required this.token});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  late Future<InviteDetails?> _detailsFuture;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _detailsFuture = InviteService.instance.fetchInviteDetails(widget.token);
    Session.instance.setPendingInviteToken(widget.token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: [
                FadeSlide(child: _buildHeader()),
                const SizedBox(height: 16),
                FadeSlide(
                  delay: const Duration(milliseconds: 120),
                  child: FutureBuilder<InviteDetails?>(
                    future: _detailsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SkeletonList();
                      }
                      final details = snapshot.data;
                      if (details == null) {
                        return _buildErrorCard(
                          'Invalid invite',
                          'This invite link is not valid or has expired.',
                        );
                      }
                      return _buildInviteCard(details);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return LuxHeader(
      title: 'Invitation',
      subtitle: 'Secure request invitation',
      icon: Icons.mark_email_unread_outlined,
      onBack: () => Navigator.pop(context),
    );
  }

  Widget _buildInviteCard(InviteDetails details) {
    final isLoggedIn = Session.instance.isLoggedIn;
    final statusLabel = _statusLabel(details);
    final statusColor = _statusColor(details);
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invite from ${details.senderLabel}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          if (statusLabel != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withOpacity(0.5)),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            details.requiredState?.isNotEmpty == true
                ? 'Required state: ${details.requiredState}'
                : 'A pre-shift clearance request is waiting for you.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          if (details.target != null && details.target!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Requested by: ${details.target}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          if (details.email != null && details.email!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Invite sent to: ${details.email}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          if (details.phone != null && details.phone!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Invite phone: ${details.phone}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          if (details.expiresAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Expires: ${_formatDate(details.expiresAt)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (!details.isActionable) ...[
            PrimaryButton(
              text: 'Back to Home',
              icon: Icons.home_outlined,
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  fadeSlideRoute(const RoleShellRouter()),
                );
              },
            ),
          ] else if (isLoggedIn) ...[
            PrimaryButton(
              text: 'Continue',
              icon: Icons.play_arrow_rounded,
              isLoading: _claiming,
              onPressed: _claiming ? null : () => _claimInvite(details),
            ),
          ] else ...[
            PrimaryButton(
              text: 'Create account',
              icon: Icons.person_add_alt_1,
              onPressed: () => _goToRegister(details.token),
            ),
            const SizedBox(height: 12),
            SecondaryButton(
              text: 'Sign in',
              onPressed: () => _goToLogin(details.token),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorCard(String title, String message) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            text: 'Back to Home',
            onPressed: () {
              Navigator.pushReplacement(
                context,
                fadeSlideRoute(const RoleShellRouter()),
              );
            },
          ),
        ],
      ),
    );
  }

  String? _statusLabel(InviteDetails details) {
    if (details.isExpired) return 'Invite expired';
    if (details.isClaimed) return 'Invite already claimed';
    return null;
  }

  Color _statusColor(InviteDetails details) {
    if (details.isExpired) return AppColors.highRisk;
    if (details.isClaimed) return AppColors.elevated;
    return AppColors.primarySoft;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final d = date.toLocal();
    return
        '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _claimInvite(InviteDetails details) async {
    setState(() => _claiming = true);
    try {
      final result = await InviteService.instance.claimInviteByToken(
        details.token,
      );
      await Session.instance.setPendingInviteToken(null);
      if (!mounted) return;
      if (result != null) {
        Navigator.pushReplacement(
          context,
          fadeSlideRoute(
            ScanFlowScreen(
              requestId: result.requestId,
              forceCompletion: true,
            ),
          ),
        );
        return;
      }
      Navigator.pushReplacement(
        context,
        fadeSlideRoute(const RoleShellRouter()),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to claim invite.'),
          backgroundColor: AppColors.cardAlt,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  Future<void> _goToRegister(String token) async {
    await Session.instance.setPendingInviteToken(token);
    if (!mounted) return;
    Navigator.push(
      context,
      fadeSlideRoute(RegisterScreen(inviteToken: token)),
    );
  }

  Future<void> _goToLogin(String token) async {
    await Session.instance.setPendingInviteToken(token);
    if (!mounted) return;
    Navigator.push(
      context,
      fadeSlideRoute(LoginScreen(inviteToken: token)),
    );
  }
}




