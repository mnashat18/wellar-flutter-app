import 'package:flutter/material.dart';

import '../models/business_profile.dart';
import '../services/organization_service.dart';
import '../state/session.dart';
import '../utils/app_colors.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_cards.dart';
import '../widgets/responsive_card_grid.dart';
import '../widgets/state_views.dart';

class BusinessProfileSummaryScreen extends StatefulWidget {
  const BusinessProfileSummaryScreen({super.key});

  @override
  State<BusinessProfileSummaryScreen> createState() =>
      _BusinessProfileSummaryScreenState();
}

class _BusinessProfileSummaryScreenState
    extends State<BusinessProfileSummaryScreen> {
  late Future<BusinessProfile?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<BusinessProfile?> _load({bool force = false}) {
    return OrganizationService.instance.fetchPrimaryBusinessProfile(
      forceRefresh: force,
    );
  }

  Future<void> _refresh() async {
    final next = _load(force: true);
    setState(() => _future = next);
    await next;
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
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                child: FutureBuilder<BusinessProfile?>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SkeletonList();
                    }
                    if (snapshot.hasError) {
                      return StatusCard(
                        title: 'Business profile unavailable',
                        message: snapshot.error.toString(),
                        icon: Icons.warning_amber_rounded,
                        iconColor: AppColors.highRisk,
                        actionText: 'Retry',
                        onAction: () {
                          setState(() => _future = _load(force: true));
                        },
                      );
                    }
                    final profile = snapshot.data;
                    if (profile == null || profile.id.trim().isEmpty) {
                      final backendError = OrganizationService
                          .instance
                          .lastProfileResolveError
                          ?.trim();
                      return _NoBusinessProfileBody(errorMessage: backendError);
                    }
                    return _BusinessProfileBody(profile: profile);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoBusinessProfileBody extends StatelessWidget {
  final String? errorMessage;

  const _NoBusinessProfileBody({this.errorMessage});

  @override
  Widget build(BuildContext context) {
    final session = Session.instance;
    final name = session.userName?.trim();
    final email = session.userEmail?.trim();
    final role = session.roleName?.trim();
    final userId = session.userId?.trim();

    String safe(String? value) {
      if (value == null || value.isEmpty) return '-';
      return value;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            ),
            const SizedBox(width: 6),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Business Profile Summary',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Business profile not linked yet for this account.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (errorMessage != null && errorMessage!.trim().isNotEmpty) ...[
          StatusCard(
            title: 'Business profile access issue',
            message: errorMessage!,
            icon: Icons.warning_amber_rounded,
            iconColor: AppColors.highRisk,
          ),
          const SizedBox(height: 12),
        ],
        const EmptyStateCard(
          title: 'No business profile yet',
          message:
              'Complete business onboarding, or wait until your business profile is approved and linked.',
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your Account Data',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              _summaryRow('Name', safe(name)),
              _summaryRow('Email', safe(email)),
              _summaryRow('Role', safe(role)),
              _summaryRow('User ID', safe(userId)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 85,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessProfileBody extends StatelessWidget {
  final BusinessProfile profile;

  const _BusinessProfileBody({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            ),
            const SizedBox(width: 6),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Business Profile Summary',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Main company details and billing context.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      profile.companyName.trim().isEmpty
                          ? 'Company details'
                          : profile.companyName,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _tag(_normalizeStatus(profile.billingStatus)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Profile Details',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ResponsiveCardGrid(
                spacing: 10,
                runSpacing: 6,
                children: [
                  ResponsiveCardGridItem(child: _infoCell('ID', profile.id)),
                  ResponsiveCardGridItem(
                    child: _infoCell('Owner User', profile.ownerUserId),
                  ),
                  ResponsiveCardGridItem(
                    child: _infoCell('Source Request', profile.sourceRequestId),
                  ),
                  ResponsiveCardGridItem(child: _infoCell('Company', profile.companyName)),
                  ResponsiveCardGridItem(
                    child: _infoCell('Business Name', profile.businessName),
                  ),
                  ResponsiveCardGridItem(
                    child: _infoCell('Contact Name', profile.contactName),
                  ),
                  ResponsiveCardGridItem(
                    child: _infoCell('Work Email', profile.workEmail),
                  ),
                  ResponsiveCardGridItem(child: _infoCell('Phone', profile.phone)),
                  ResponsiveCardGridItem(
                    child: _infoCell('Industry', profile.industry),
                  ),
                  ResponsiveCardGridItem(
                    child: _infoCell('Team Size', profile.teamSize),
                  ),
                  ResponsiveCardGridItem(child: _infoCell('Country', profile.country)),
                  ResponsiveCardGridItem(child: _infoCell('City', profile.city)),
                  ResponsiveCardGridItem(
                    child: _infoCell('Address', profile.address),
                  ),
                  ResponsiveCardGridItem(
                    child: _infoCell('Website', profile.website),
                  ),
                  ResponsiveCardGridItem(
                    child: _infoCell('Plan Code', profile.planCode),
                  ),
                  ResponsiveCardGridItem(
                    child: _infoCell('Billing Status', profile.billingStatus),
                  ),
                  ResponsiveCardGridItem(
                    child: _infoCell('Is Active', profile.isActive ? 'true' : 'false'),
                  ),
                  ResponsiveCardGridItem(
                    child: _infoCell(
                      'Trial Start',
                      _formatDate(profile.trialStartedAt) ?? '-',
                    ),
                  ),
                  ResponsiveCardGridItem.fullWidth(
                    child: _infoCell('Trial Expires', _formatExpires(profile)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoCell(String label, String? value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.backgroundAlt.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _safe(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text) {
    final isActive = text.toLowerCase() == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (isActive ? AppColors.stable : AppColors.lowFocus).withOpacity(
          0.2,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isActive ? AppColors.stable : AppColors.lowFocus).withOpacity(
            0.5,
          ),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isActive ? AppColors.stable : AppColors.lowFocus,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  String _safe(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty || v.toLowerCase() == 'null') return '-';
    return v;
  }

  String _normalizeStatus(String? status) {
    final v = status?.trim();
    if (v == null || v.isEmpty) return 'unknown';
    return v;
  }

  String? _formatDate(DateTime? value) {
    if (value == null) return null;
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  String _formatExpires(BusinessProfile profile) {
    final parsed = _formatDate(profile.trialExpiresAt);
    if (parsed != null) return parsed;
    final raw = profile.trialExpiresRaw?.trim();
    if (raw == null || raw.isEmpty) return '-';
    return raw;
  }
}
