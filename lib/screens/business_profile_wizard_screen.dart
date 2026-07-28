import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/plan.dart';
import '../services/directus_client.dart';
import '../services/organization_service.dart';
import '../services/push_notification_service.dart';
import '../services/workspace_creation_service.dart';
import '../state/session.dart';
import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import 'role_based_shells.dart';

class BusinessProfileWizardScreen extends ConsumerStatefulWidget {
  final Plan plan;
  final String billingCycle;

  const BusinessProfileWizardScreen({
    super.key,
    required this.plan,
    required this.billingCycle,
  });

  @override
  ConsumerState<BusinessProfileWizardScreen> createState() =>
      _BusinessProfileWizardScreenState();
}

class _BusinessProfileWizardScreenState
    extends ConsumerState<BusinessProfileWizardScreen> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0;
  bool _submitting = false;

  final _businessName = TextEditingController();
  final _industry = TextEditingController();
  final _teamSize = TextEditingController();
  final _contactName = TextEditingController();
  final _workEmail = TextEditingController();
  final _phone = TextEditingController();
  final _country = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _website = TextEditingController();

  String _authenticatedEmail = '';
  String _authenticatedFirstName = '';
  String _authenticatedLastName = '';

  @override
  void initState() {
    super.initState();
    _seedIdentityFromSession();
    _loadAuthenticatedIdentity();
  }

  void _seedIdentityFromSession() {
    final sessionEmail = Session.instance.userEmail?.trim() ?? '';
    if (sessionEmail.isNotEmpty) {
      _authenticatedEmail = sessionEmail;
      _workEmail.text = sessionEmail;
    }
    final sessionName = Session.instance.userName?.trim() ?? '';
    if (sessionName.isNotEmpty) {
      _contactName.text = sessionName;
      final parts = sessionName.split(RegExp(r'\s+'));
      if (parts.isNotEmpty) {
        _authenticatedFirstName = parts.first;
        if (parts.length > 1) {
          _authenticatedLastName = parts.sublist(1).join(' ');
        }
      }
    }
  }

  Future<void> _loadAuthenticatedIdentity() async {
    try {
      final profile = await OrganizationService.instance
          .fetchAuthenticatedCurrentUserProfile();
      if (!mounted || profile == null) return;
      final email = profile.email.trim();
      final firstName = profile.firstName?.trim() ?? '';
      final lastName = profile.lastName?.trim() ?? '';
      setState(() {
        if (email.isNotEmpty) {
          _authenticatedEmail = email;
          _workEmail.text = email;
        }
        if (firstName.isNotEmpty) _authenticatedFirstName = firstName;
        if (lastName.isNotEmpty) _authenticatedLastName = lastName;
        final composed = [
          firstName,
          lastName,
        ].where((s) => s.isNotEmpty).join(' ').trim();
        if (composed.isNotEmpty && _contactName.text.trim().isEmpty) {
          _contactName.text = composed;
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _businessName.dispose();
    _industry.dispose();
    _teamSize.dispose();
    _contactName.dispose();
    _workEmail.dispose();
    _phone.dispose();
    _country.dispose();
    _city.dispose();
    _address.dispose();
    _website.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(context),
                      const SizedBox(height: 16),
                      _progress(),
                      const SizedBox(height: 16),
                      AppCard(
                        radius: 16,
                        padding: const EdgeInsets.all(16),
                        child: _stepBody(),
                      ),
                      const SizedBox(height: 14),
                      _actions(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_submitting)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.primarySoft),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: _submitting ? null : () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Business Profile Setup',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.plan.name} • ${_titleCase(widget.billingCycle)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _progress() {
    return Row(
      children: List.generate(3, (index) {
        final current = index == _step;
        final done = index < _step;
        final color = done || current ? AppColors.primarySoft : Colors.white24;
        return Expanded(
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.2),
                  border: Border.all(color: color),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ),
              if (index < 2)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    height: 2,
                    color: index < _step
                        ? AppColors.primarySoft
                        : Colors.white12,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _stepBody() {
    if (_step == 0) return _stepBusiness();
    if (_step == 1) return _stepContact();
    return _stepLocation();
  }

  Widget _stepBusiness() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Step 1 – Company Info',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        _field(
          label: 'Business Name',
          controller: _businessName,
          validator: _required('Business Name'),
        ),
        _field(
          label: 'Industry',
          controller: _industry,
          validator: _required('Industry'),
        ),
        _field(
          label: 'Team Size',
          controller: _teamSize,
          keyboardType: TextInputType.number,
          validator: _required('Team Size'),
        ),
      ],
    );
  }

  Widget _stepContact() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Step 2 – Contact Details',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        _field(
          label: 'Contact Name',
          controller: _contactName,
          validator: _required('Contact Name'),
        ),
        _field(
          label: 'Work Email',
          controller: _workEmail,
          keyboardType: TextInputType.emailAddress,
          readOnly: true,
          helperText:
              'This company will be created under your signed-in account.',
          validator: (value) {
            final text = value?.trim().toLowerCase() ?? '';
            if (text.isEmpty) return 'Work Email is required';
            final expected = _authenticatedEmail.trim().toLowerCase();
            if (expected.isNotEmpty && text != expected) {
              return 'Owner email must match your signed-in account.';
            }
            return null;
          },
        ),
        _field(
          label: 'Phone',
          controller: _phone,
          keyboardType: TextInputType.phone,
          validator: _required('Phone'),
        ),
      ],
    );
  }

  Widget _stepLocation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Step 3 – Location',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        _field(
          label: 'Country',
          controller: _country,
          validator: _required('Country'),
        ),
        _field(label: 'City', controller: _city, validator: _required('City')),
        _field(
          label: 'Address',
          controller: _address,
          validator: _required('Address'),
        ),
        _field(
          label: 'Website (optional)',
          controller: _website,
          keyboardType: TextInputType.url,
        ),
      ],
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool readOnly = false,
    String? helperText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        readOnly: readOnly,
        style: TextStyle(
          color: readOnly ? AppColors.textSecondary : Colors.white,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          helperText: helperText,
          helperStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
          helperMaxLines: 2,
          filled: true,
          fillColor: readOnly
              ? AppColors.backgroundAlt.withOpacity(0.7)
              : AppColors.backgroundAlt,
          suffixIcon: readOnly
              ? const Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: AppColors.textSecondary,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primarySoft),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.highRisk),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.highRisk),
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    final lastStep = _step == 2;
    return Row(
      children: [
        Expanded(
          child: SecondaryButton(
            text: _step == 0 ? 'Back' : 'Back',
            onPressed: _submitting
                ? null
                : () {
                    if (_step == 0) {
                      Navigator.maybePop(context);
                      return;
                    }
                    setState(() => _step--);
                  },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: PrimaryButton(
            text: lastStep ? 'Create workspace' : 'Continue',
            isLoading: _submitting,
            onPressed: _submitting
                ? null
                : () {
                    if (!_validateCurrentStep()) return;
                    if (!lastStep) {
                      setState(() => _step++);
                      return;
                    }
                    _submit();
                  },
          ),
        ),
      ],
    );
  }

  bool _validateCurrentStep() {
    final form = _formKey.currentState;
    if (form == null) return false;
    return form.validate();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final profile = await OrganizationService.instance
          .fetchAuthenticatedCurrentUserProfile();
      final profileFirstName = profile?.firstName?.trim() ?? '';
      final profileLastName = profile?.lastName?.trim() ?? '';
      final profileEmail = profile?.email.trim() ?? '';
      if (profile == null ||
          profileFirstName.isEmpty ||
          profileLastName.isEmpty ||
          profileEmail.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'We could not verify your account profile right now. Try again.',
            ),
            backgroundColor: AppColors.highRisk,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final idempotencyKey = _generateIdempotencyKey();
      final createResponse = await WorkspaceCreationService.instance
          .createWorkspace(
            idempotencyKey: idempotencyKey,
            companyName: _businessName.text,
            firstName: profileFirstName,
            lastName: profileLastName,
            workEmail: profileEmail,
            country: _country.text,
            city: _city.text,
            website: _website.text.trim().isEmpty ? null : _website.text.trim(),
          );

      final status = createResponse.statusCode;
      if (status < 200 || status >= 300) {
        throw DioException(
          requestOptions: RequestOptions(
            path: '/wellar/workspaces/create',
            method: 'POST',
          ),
          response: Response(
            requestOptions:
                RequestOptions(
                  path: '/wellar/workspaces/create',
                  method: 'POST',
                ),
            statusCode: status,
            data: createResponse.data,
          ),
        );
      }

      final refreshed = await DirectusClient.instance.refreshAuthToken();
      if (!refreshed) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'We created your workspace, but could not refresh access. Try again.',
            ),
            backgroundColor: AppColors.highRisk,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final workspace = await _resolveConfirmedOwnerWorkspace();
      if (workspace != null) {
        OrganizationService.instance.applyActiveWorkspaceContext(workspace);
        debugPrint('[ORG_SWITCH_VERIFY] context_applied=true');
        debugPrint('[ORG_SWITCH_VERIFY] owner_hr_reload_requested=true');
        try {
          await PushNotificationService.instance.syncCurrentDevice(
            trigger: 'workspace_ready',
            workspaceContext: workspace,
          );
        } catch (_) {}
        if (!context.mounted) return;
        final navigator = Navigator.of(context);
        debugPrint('[ORG_SWITCH_VERIFY] role_shell_rebuilt=true');
        navigator.pushReplacement(
          fadeSlideRoute(RoleShellRouter(initialContext: workspace)),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your workspace was created. We are still activating access. Refresh access in a moment.',
          ),
          backgroundColor: AppColors.stable,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      debugPrint(
        '[BUSINESS_PROFILE_CREATE] endpoint=${e.requestOptions.method} ${e.requestOptions.path} status=$status body=${e.response?.data}',
      );
      if (!context.mounted) return;
      final message = _messageForCreateStatus(status);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.highRisk,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Exception catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'We could not create your workspace right now. Try again.',
          ),
          backgroundColor: AppColors.highRisk,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'We could not create your workspace right now. Try again.',
          ),
          backgroundColor: AppColors.highRisk,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<ActiveWorkspaceContext?> _resolveConfirmedOwnerWorkspace() async {
    final firstAttempt = await OrganizationService.instance
        .fetchCanonicalWorkspaceContext(forceRefresh: true);
    final firstContext = _verifiedOwnerContext(firstAttempt);
    if (firstContext != null) return firstContext;

    await Future<void>.delayed(const Duration(milliseconds: 700));

    final secondAttempt = await OrganizationService.instance
        .fetchCanonicalWorkspaceContext(forceRefresh: true);
    return _verifiedOwnerContext(secondAttempt);
  }

  ActiveWorkspaceContext? _verifiedOwnerContext(
    CanonicalWorkspaceContextResult result,
  ) {
    final snapshot = result.snapshot;
    if (result.status != CanonicalWorkspaceContextStatus.ok ||
        snapshot == null) {
      return null;
    }
    final context = snapshot.activeContext;
    if (context == null) return null;
    final role = context.finalEffectiveRole.trim().toLowerCase();
    if (role != 'owner') return null;
    if (context.businessProfileId.trim().isEmpty) return null;
    if (context.membershipUserId.trim() != context.currentUserId.trim()) {
      return null;
    }
    return context;
  }

  String _generateIdempotencyKey() {
    return 'workspace-create-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  }

  String _messageForCreateStatus(int status) {
    switch (status) {
      case 401:
        return 'Your session expired. Please sign in again.';
      case 403:
        return 'You are not allowed to create a workspace from this account.';
      case 409:
        return 'This account already has a workspace. Refresh access to continue.';
      default:
        return 'We could not create your workspace right now. Try again.';
    }
  }

  String? Function(String?) _required(String label) {
    return (value) {
      if ((value ?? '').trim().isEmpty) return '$label is required';
      return null;
    };
  }

  String _titleCase(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return '-';
    return '${v[0].toUpperCase()}${v.substring(1)}';
  }
}
