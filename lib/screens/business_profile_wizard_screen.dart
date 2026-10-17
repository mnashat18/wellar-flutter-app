import '../utils/safe_debug_log.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/locations_data.dart';
import '../models/plan.dart';
import '../services/directus_client.dart';
import '../services/organization_service.dart';
import '../services/push_notification_service.dart';
import '../services/workspace_creation_service.dart';
import '../state/app_providers.dart';
import '../state/session.dart';
import '../utils/app_feedback.dart';
import '../utils/business_profile_validators.dart';
import '../utils/page_transition.dart';
import '../theme/app_theme.dart';
import '../widgets/searchable_picker_field.dart';
import '../widgets/wellar_button.dart';
import '../widgets/wellar_card.dart';
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
  final _locationSelection = CascadingLocationSelection();

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
      backgroundColor: WellarTheme.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: WellarTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
                  child: _header(context),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                  child: _progress(),
                ),
                Expanded(
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        20 + MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: _stepBody(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                  child: _actions(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: _submitting ? null : () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: WellarTheme.text),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create your company',
                style: WellarTheme.heading.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.plan.name} • ${_titleCase(widget.billingCycle)}',
                style: const TextStyle(
                  color: WellarTheme.textMuted,
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
        final color = done || current ? WellarTheme.primary : Colors.white24;
        return Expanded(
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.16),
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
                    color: index < _step ? WellarTheme.primary : Colors.white12,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _stepBody() {
    return WellarCard(
      highlighted: true,
      padding: const EdgeInsets.all(18),
      child: switch (_step) {
        0 => _stepBusiness(),
        1 => _stepContact(),
        _ => _stepLocation(),
      },
    );
  }

  Widget _stepBusiness() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Business details', 'Company identity and team size'),
        _field(
          label: 'Business Name',
          controller: _businessName,
          validator: _requiredText('Business Name', minimumLength: 2),
        ),
        _field(
          label: 'Industry',
          controller: _industry,
          validator: _requiredText('Industry', minimumLength: 2),
        ),
        _field(
          label: 'Team Size',
          controller: _teamSize,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          validator: _teamSizeValidator,
        ),
      ],
    );
  }

  Widget _stepContact() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Contact details',
          'Who should we reach about this workspace?',
        ),
        _field(
          label: 'Contact Name',
          controller: _contactName,
          validator: _requiredText('Contact Name', minimumLength: 2),
        ),
        _field(
          label: 'Work Email',
          controller: _workEmail,
          keyboardType: TextInputType.emailAddress,
          readOnly: true,
          helperText:
              'This company will be created under your signed-in account.',
          validator: (value) => BusinessProfileValidators.email(
            value,
            expected: _authenticatedEmail,
          ),
        ),
        _field(
          label: 'Phone',
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')),
          ],
          validator: _phoneValidator,
        ),
      ],
    );
  }

  Widget _stepLocation() {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final country = _locationSelection.country;
    final region = _locationSelection.region;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Location', 'Choose the workspace location'),
        SearchablePickerField(
          label: 'Country',
          searchHint: 'Search countries',
          value: country,
          options: LocationsData.countries,
          enabled: true,
          onSelected: (selection) => setState(() {
            _locationSelection.selectCountry(selection);
            _country.text = selection.localizedName(isArabic);
            _city.clear();
          }),
        ),
        SearchablePickerField(
          label: 'Governorate / State',
          searchHint: 'Search regions',
          value: region,
          options: country?.children ?? const [],
          enabled: country != null,
          onSelected: (selection) => setState(() {
            _locationSelection.selectRegion(selection);
            _city.clear();
          }),
        ),
        SearchablePickerField(
          label: 'City / District',
          searchHint: 'Search cities',
          value: _locationSelection.city,
          options: region?.children ?? const [],
          enabled: region != null,
          onSelected: (selection) => setState(() {
            _locationSelection.selectCity(selection);
            _city.text = selection.localizedName(isArabic);
          }),
        ),
        _field(
          label: 'Address',
          controller: _address,
          validator: BusinessProfileValidators.address,
        ),
        _field(
          label: 'Website (optional)',
          controller: _website,
          keyboardType: TextInputType.url,
          validator: _websiteValidator,
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    final stepLabel = switch (_step) {
      0 => 'STEP 1 OF 3',
      1 => 'STEP 2 OF 3',
      _ => 'STEP 3 OF 3',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stepLabel,
            style: WellarTheme.caption.copyWith(
              color: WellarTheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 5),
          Text(title, style: WellarTheme.heading.copyWith(fontSize: 21)),
          const SizedBox(height: 4),
          Text(subtitle, style: WellarTheme.caption),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
    bool readOnly = false,
    String? helperText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: TextInputAction.next,
        inputFormatters: inputFormatters,
        validator: validator,
        readOnly: readOnly,
        style: TextStyle(
          color: readOnly ? WellarTheme.textMuted : WellarTheme.text,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: WellarTheme.textMuted),
          helperText: helperText,
          helperStyle: WellarTheme.caption,
          helperMaxLines: 2,
          filled: true,
          fillColor: readOnly
              ? WellarTheme.surfaceSoft.withValues(alpha: 0.45)
              : WellarTheme.surfaceSoft,
          suffixIcon: readOnly
              ? const Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: WellarTheme.textMuted,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: WellarTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: WellarTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: WellarTheme.primary),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: WellarTheme.danger),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: WellarTheme.danger),
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
          child: WellarButton.secondary(
            text: 'Back',
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
          child: WellarButton.primary(
            text: lastStep ? 'Create workspace' : 'Continue',
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
    final visibleFieldsValid = form.validate();
    if (!visibleFieldsValid) return false;
    if (_step != 2) return true;
    return _allFieldsValid();
  }

  bool _allFieldsValid() {
    return BusinessProfileValidators.requiredText(
              _businessName.text,
              'Business Name',
            ) ==
            null &&
        BusinessProfileValidators.requiredText(_industry.text, 'Industry') ==
            null &&
        BusinessProfileValidators.teamSize(_teamSize.text) == null &&
        BusinessProfileValidators.requiredText(
              _contactName.text,
              'Contact Name',
            ) ==
            null &&
        BusinessProfileValidators.email(
              _workEmail.text,
              expected: _authenticatedEmail,
            ) ==
            null &&
        BusinessProfileValidators.phone(_phone.text) == null &&
        _locationSelection.country != null &&
        _locationSelection.region != null &&
        _locationSelection.city != null &&
        BusinessProfileValidators.address(_address.text) == null &&
        BusinessProfileValidators.website(_website.text) == null;
  }

  Future<void> _submit() async {
    if (!_allFieldsValid()) {
      _formKey.currentState?.validate();
      return;
    }
    if (ref.read(connectivityStatusProvider).asData?.value == false) {
      AppFeedback.showOffline(context);
      return;
    }
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
        AppFeedback.showError(
          context,
          'We could not verify your account profile right now. Try again.',
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
            requestOptions: RequestOptions(
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
        AppFeedback.showError(
          context,
          'Your workspace was created successfully, but we could not refresh access. Please sign in again to complete setup.',
        );
        return;
      }

      final workspace = await _resolveConfirmedOwnerWorkspace();
      if (workspace != null) {
        OrganizationService.instance.applyActiveWorkspaceContext(workspace);
        safeDebugLog('[ORG_SWITCH_VERIFY] context_applied=true');
        safeDebugLog('[ORG_SWITCH_VERIFY] owner_hr_reload_requested=true');
        try {
          await PushNotificationService.instance.syncCurrentDevice(
            trigger: 'workspace_ready',
            workspaceContext: workspace,
          );
        } catch (_) {}
        if (!context.mounted) return;
        final navigator = Navigator.of(context);
        safeDebugLog('[ORG_SWITCH_VERIFY] role_shell_rebuilt=true');
        navigator.pushReplacement(
          fadeSlideRoute(RoleShellRouter(initialContext: workspace)),
        );
        return;
      }

      AppFeedback.showError(
        context,
        'Your workspace was created, but access is not ready yet. Please sign in again to complete setup.',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      safeDebugLog(
        '[BUSINESS_PROFILE_CREATE] endpoint=${e.requestOptions.method} ${e.requestOptions.path} status=$status body=${e.response?.data}',
      );
      if (!context.mounted) return;
      if (ref.read(connectivityStatusProvider).asData?.value == false) {
        AppFeedback.showOffline(context);
        return;
      }
      final message = _messageForCreateStatus(status);
      AppFeedback.showError(context, message);
    } on Exception catch (_) {
      if (!context.mounted) return;
      if (ref.read(connectivityStatusProvider).asData?.value == false) {
        AppFeedback.showOffline(context);
        return;
      }
      AppFeedback.showError(
        context,
        'We could not create your workspace right now. Try again.',
      );
    } catch (_) {
      if (!context.mounted) return;
      if (ref.read(connectivityStatusProvider).asData?.value == false) {
        AppFeedback.showOffline(context);
        return;
      }
      AppFeedback.showError(
        context,
        'We could not create your workspace right now. Try again.',
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

  String? Function(String?) _requiredText(
    String label, {
    required int minimumLength,
  }) {
    return (value) {
      return BusinessProfileValidators.requiredText(
        value,
        label,
        minimumLength: minimumLength,
      );
    };
  }

  String? _teamSizeValidator(String? value) =>
      BusinessProfileValidators.teamSize(value);

  String? _phoneValidator(String? value) =>
      BusinessProfileValidators.phone(value);

  String? _websiteValidator(String? value) =>
      BusinessProfileValidators.website(value);

  String _titleCase(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return '-';
    return '${v[0].toUpperCase()}${v.substring(1)}';
  }
}
