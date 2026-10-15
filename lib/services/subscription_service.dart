import 'package:dio/dio.dart';

import '../models/plan.dart';
import '../models/user_subscription.dart';
import '../state/session.dart';
import 'directus_client.dart';
import 'organization_service.dart';

enum PlanTier { free, business, unknown }

class PlanAccess {
  final PlanTier tier;
  final bool canUseBusiness;
  final bool isTrial;
  final bool isExpired;
  final int? daysRemaining;

  const PlanAccess({
    required this.tier,
    required this.canUseBusiness,
    required this.isTrial,
    required this.isExpired,
    required this.daysRemaining,
  });

  bool get canCreateRequest => canUseBusiness;
  bool get canInviteExternal => canUseBusiness;
  bool get canViewAuditLogs => canUseBusiness;
  bool get canExportReports => canUseBusiness;
  bool get canViewAnalytics => canUseBusiness;
  bool get canViewActivity => canUseBusiness;
  bool get showExpiredBanner => isExpired;

  String get label {
    switch (tier) {
      case PlanTier.business:
        return 'Business';
      case PlanTier.free:
        return 'Free';
      case PlanTier.unknown:
        return 'Unknown';
    }
  }
}

class BusinessProfileDraft {
  final String businessName;
  final String industry;
  final String teamSize;
  final String contactName;
  final String workEmail;
  final String phone;
  final String country;
  final String city;
  final String address;
  final String? website;

  const BusinessProfileDraft({
    required this.businessName,
    required this.industry,
    required this.teamSize,
    required this.contactName,
    required this.workEmail,
    required this.phone,
    required this.country,
    required this.city,
    required this.address,
    required this.website,
  });
}

class TrialActivationResult {
  final String businessProfileId;
  final UserSubscription subscription;

  const TrialActivationResult({
    required this.businessProfileId,
    required this.subscription,
  });
}

class SubscriptionService {
  SubscriptionService._();

  static final SubscriptionService instance = SubscriptionService._();

  Dio get _client => DirectusClient.instance.client;

  static const String _planFields =
      'id,name,code,description,monthly_price,yearly_price,trial_days,max_members,is_business,'
      'features,is_popular,is_active,sort_order';

  static const String _subscriptionFields =
      'id,status,billing_cycle,started_at,expires_at,date_created,current_members_count,'
      'user,business_profile,'
      'plan.id,plan.name,plan.code,plan.description,plan.monthly_price,plan.yearly_price,'
      'plan.trial_days,plan.max_members,plan.is_business,plan.features,plan.is_popular,plan.is_active,plan.sort_order';

  Future<List<Plan>> fetchPlans() async {
    try {
      final response = await _client.get(
        '/items/plans',
        queryParameters: {
          'limit': 50,
          'sort': 'sort_order',
          'filter[is_active][_eq]': 'true',
          'fields': _planFields,
        },
      );
      final data = response.data['data'];
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(Plan.fromJson)
            .toList();
      }
      return const [];
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 403 || status == 404) return const [];
      rethrow;
    }
  }

  Future<UserSubscription?> fetchActiveSubscription() async {
    final context = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final profileId = context?.businessProfileId.trim();
    if (profileId == null || profileId.isEmpty) return null;
    final subscription = await _fetchLatestSubscriptionByBusinessProfile(
      profileId,
    );
    if (subscription?.businessProfileId?.trim() != profileId) return null;
    return subscription;
  }

  Future<TrialActivationResult> startBusinessTrial({
    required Plan plan,
    required String billingCycle,
    required BusinessProfileDraft draft,
  }) async {
    throw const _SubscriptionException(
      'Subscriptions are not available yet. A verified payment service is required.',
    );
  }

  Future<UserSubscription?> activatePlan({
    required Plan plan,
    required String billingCycle,
  }) async {
    final profileId = await OrganizationService.instance
        .fetchPrimaryBusinessProfileId();
    if (profileId == null || profileId.trim().isEmpty) {
      throw const _SubscriptionException(
        'No business profile found. Complete onboarding first.',
      );
    }
    return upsertSubscriptionForProfile(
      plan: plan,
      billingCycle: billingCycle,
      businessProfileId: profileId,
      status: 'active',
    );
  }

  Future<UserSubscription?> upsertSubscriptionForProfile({
    required Plan plan,
    required String billingCycle,
    required String businessProfileId,
    String status = 'active',
  }) async {
    // SECURITY: never write active/trial entitlement from a client action.
    // Replace with a protected server entitlement action driven by verified provider webhooks.
    throw const _SubscriptionException(
      'Subscriptions are not available yet. A verified payment service is required.',
    );
  }

  Future<UserSubscription?> renewSubscription(UserSubscription current) async {
    final plan = current.plan;
    if (plan == null) return null;
    final profileId = current.businessProfileId?.trim();
    if (profileId == null || profileId.isEmpty) {
      throw const _SubscriptionException('Business profile is required.');
    }
    return upsertSubscriptionForProfile(
      plan: plan,
      billingCycle: current.billingCycle,
      businessProfileId: profileId,
      status: 'active',
    );
  }

  Future<UserSubscription?> cancelSubscription(UserSubscription current) async {
    throw const _SubscriptionException(
      'Subscription changes are not available yet. Contact support for help.',
    );
  }

  Future<int> fetchCurrentMembersCount(String businessProfileId) async {
    if (businessProfileId.trim().isEmpty) return 0;
    try {
      final members = await OrganizationService.instance.fetchBusinessMembers(
        businessProfileId: businessProfileId.trim(),
        limit: 300,
      );
      return members.where((m) {
        final status = m.status.trim().toLowerCase();
        return status.isEmpty ||
            status == 'active' ||
            status == 'pending' ||
            status == 'invited';
      }).length;
    } catch (_) {
      return 0;
    }
  }

  PlanAccess accessForSubscription(UserSubscription? subscription) {
    final tier = _tierFromPlan(subscription?.plan);
    final canUse = canUseBusinessSubscription(subscription);
    final expired = isExpiredSubscription(subscription);
    return PlanAccess(
      tier: tier,
      canUseBusiness: canUse,
      isTrial: isTrialSubscription(subscription),
      isExpired: expired,
      daysRemaining: daysRemaining(subscription),
    );
  }

  bool canUseBusinessSubscription(UserSubscription? subscription) {
    if (subscription == null || subscription.plan == null) return false;
    if (!_isBusinessPlan(subscription.plan!)) return false;

    final status = _normalizeStatus(subscription.status);
    final expiresAt = _safeUtc(subscription.expiresAt);
    final now = DateTime.now().toUtc();

    if (status == 'active') {
      if (expiresAt == null) return false;
      return now.isBefore(expiresAt);
    }

    if (status == 'trial') {
      if (expiresAt == null) return false;
      return now.isBefore(expiresAt);
    }

    return false;
  }

  bool isTrialSubscription(UserSubscription? subscription) {
    if (subscription == null) return false;
    return _normalizeStatus(subscription.status) == 'trial';
  }

  bool isExpiredSubscription(UserSubscription? subscription) {
    if (subscription == null || subscription.plan == null) return false;
    if (!_isBusinessPlan(subscription.plan!)) return false;
    if (canUseBusinessSubscription(subscription)) return false;

    final status = _normalizeStatus(subscription.status);
    if (status == 'expired' || status == 'canceled' || status == 'inactive') {
      return true;
    }

    final expiresAt = _safeUtc(subscription.expiresAt);
    final now = DateTime.now().toUtc();
    return expiresAt != null && !now.isBefore(expiresAt);
  }

  int? daysRemaining(UserSubscription? subscription) {
    final expiresAt = _safeUtc(subscription?.expiresAt);
    if (expiresAt == null) return null;
    final now = DateTime.now().toUtc();
    final diff = expiresAt.difference(now);
    if (diff.isNegative) return 0;
    return ((diff.inMinutes / Duration.minutesPerDay).ceil()).clamp(0, 9999);
  }

  Duration? remainingDuration(UserSubscription? subscription) {
    final expiresAt = _safeUtc(subscription?.expiresAt);
    if (expiresAt == null) return null;
    final now = DateTime.now().toUtc();
    final diff = expiresAt.difference(now);
    if (diff.isNegative) return Duration.zero;
    return diff;
  }

  Future<UserSubscription?> _fetchLatestSubscriptionByBusinessProfile(
    String businessProfileId,
  ) async {
    final attempts = [
      {'filter[business_profile][_eq]': businessProfileId},
      {'filter[business_profile][id][_eq]': businessProfileId},
    ];

    for (final filter in attempts) {
      try {
        final response = await _client.get(
          '/items/subscriptions',
          queryParameters: {
            'limit': 1,
            'sort': '-date_created,-started_at',
            'fields': _subscriptionFields,
            ...filter,
          },
        );
        final parsed = _firstSubscription(response.data['data']);
        if (parsed != null) return parsed;
      } on DioException catch (e) {
        if (_isQueryFieldIssue(e)) continue;
        rethrow;
      }
    }
    return null;
  }

  Future<String> _ensureBusinessProfile({
    required String userId,
    required BusinessProfileDraft draft,
    required Plan plan,
    required String billingStatus,
    required DateTime trialStartedAt,
    required DateTime trialExpiresAt,
  }) async {
    final existing = await OrganizationService.instance
        .fetchPrimaryBusinessProfile(forceRefresh: true);

    final payload = _buildBusinessProfilePayload(
      userId: userId,
      draft: draft,
      plan: plan,
      billingStatus: billingStatus,
      trialStartedAt: trialStartedAt,
      trialExpiresAt: trialExpiresAt,
    );

    if (existing != null && existing.id.trim().isNotEmpty) {
      await _client.patch(
        '/items/business_profiles/${existing.id}',
        data: payload,
      );
      return existing.id.trim();
    }

    final response = await _client.post(
      '/items/business_profiles',
      data: payload,
    );
    final createdId = _extractCreatedId(response.data);
    if (createdId == null || createdId.isEmpty) {
      throw const _SubscriptionException('Failed to create business profile.');
    }
    return createdId;
  }

  Future<void> _syncBusinessProfileBilling({
    required String businessProfileId,
    required Plan? plan,
    required String billingStatus,
    required DateTime? trialStartedAt,
    required DateTime? trialExpiresAt,
  }) async {
    final payload = <String, dynamic>{
      if (plan != null) 'plan_code': plan.code.trim().toLowerCase(),
      'billing_status': billingStatus,
      if (trialStartedAt != null)
        'trial_started_at': trialStartedAt.toIso8601String(),
      if (trialExpiresAt != null)
        'trial_expires_at': trialExpiresAt.toIso8601String(),
      'is_active': billingStatus == 'trial' || billingStatus == 'active',
    };
    await _client.patch(
      '/items/business_profiles/$businessProfileId',
      data: payload,
    );
  }

  Future<UserSubscription> _upsertSubscriptionRecord({
    required String userId,
    required String businessProfileId,
    required Plan plan,
    required String billingCycle,
    required String status,
    required DateTime startedAt,
    required DateTime expiresAt,
  }) async {
    final payload = <String, dynamic>{
      'user': userId,
      'business_profile': businessProfileId,
      'plan': plan.id.isNotEmpty ? plan.id : plan.code,
      'status': status,
      'billing_cycle': billingCycle,
      'started_at': startedAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'current_members_count': await fetchCurrentMembersCount(
        businessProfileId,
      ),
    };

    final existing = await _fetchLatestSubscriptionByBusinessProfile(
      businessProfileId,
    );

    Response<dynamic> response;
    if (existing != null &&
        existing.id.trim().isNotEmpty &&
        !existing.id.startsWith('synthetic:')) {
      response = await _client.patch(
        '/items/subscriptions/${existing.id}',
        data: payload,
      );
    } else {
      response = await _client.post('/items/subscriptions', data: payload);
    }

    final data = response.data['data'];
    if (data is Map<String, dynamic>) {
      return UserSubscription.fromJson({
        ...data,
        'business_profile': businessProfileId,
        'user': userId,
        'plan': data['plan'] is Map ? data['plan'] : _planToJson(plan),
      });
    }

    return UserSubscription(
      id: _extractCreatedId(response.data) ?? existing?.id ?? '',
      plan: plan,
      businessProfileId: businessProfileId,
      userId: userId,
      status: status,
      billingCycle: billingCycle,
      startedAt: startedAt,
      expiresAt: expiresAt,
      createdAt: DateTime.now().toUtc(),
      currentMembersCount: payload['current_members_count'] as int?,
    );
  }

  Map<String, dynamic> _buildBusinessProfilePayload({
    required String userId,
    required BusinessProfileDraft draft,
    required Plan plan,
    required String billingStatus,
    required DateTime trialStartedAt,
    required DateTime trialExpiresAt,
  }) {
    return {
      'owner_user': userId,
      'company_name': draft.businessName.trim(),
      'business_name': draft.businessName.trim(),
      'work_email': draft.workEmail.trim().toLowerCase(),
      'phone': draft.phone.trim(),
      'industry': draft.industry.trim(),
      'team_size': draft.teamSize.trim(),
      'country': draft.country.trim(),
      'city': draft.city.trim(),
      'address': draft.address.trim(),
      if (draft.website != null && draft.website!.trim().isNotEmpty)
        'website': draft.website!.trim(),
      'plan_code': plan.code.trim().toLowerCase(),
      'billing_status': billingStatus,
      'trial_started_at': trialStartedAt.toIso8601String(),
      'trial_expires_at': trialExpiresAt.toIso8601String(),
      'is_active': true,
    };
  }

  UserSubscription? _firstSubscription(dynamic data) {
    if (data is List && data.isNotEmpty) {
      final first = data.first;
      if (first is Map<String, dynamic>) {
        return UserSubscription.fromJson(first);
      }
    }
    return null;
  }

  PlanTier _tierFromPlan(Plan? plan) {
    if (plan == null) return PlanTier.unknown;
    if (_isBusinessPlan(plan)) return PlanTier.business;
    if (plan.code.trim().toLowerCase() == 'free') return PlanTier.free;
    return PlanTier.unknown;
  }

  bool _isBusinessPlan(Plan plan) {
    return plan.isBusiness || plan.code.trim().toLowerCase() == 'business';
  }

  String _normalizeStatus(String? status) {
    if (status == null) return '';
    final normalized = status.trim().toLowerCase();
    if (normalized == 'cancelled') return 'canceled';
    return normalized;
  }

  String _normalizeBillingCycle(String billingCycle) {
    final normalized = billingCycle.trim().toLowerCase();
    return normalized == 'yearly' ? 'yearly' : 'monthly';
  }

  String _requireUserId() {
    final userId = Session.instance.userId?.trim();
    if (userId == null || userId.isEmpty) {
      throw const _SubscriptionException('Login required.');
    }
    return userId;
  }

  DateTime? _safeUtc(DateTime? value) => value?.toUtc();

  DateTime _computeExpiry(DateTime start, String billingCycle) {
    final cycle = _normalizeBillingCycle(billingCycle);
    final targetYear = cycle == 'yearly' ? start.year + 1 : start.year;
    final targetMonth = cycle == 'yearly' ? start.month : start.month + 1;
    final daysInTargetMonth = DateTime.utc(targetYear, targetMonth + 1, 0).day;
    return DateTime.utc(
      targetYear,
      targetMonth,
      start.day.clamp(1, daysInTargetMonth),
      start.hour,
      start.minute,
      start.second,
      start.millisecond,
      start.microsecond,
    );
  }

  String? _extractCreatedId(dynamic raw) {
    if (raw is Map && raw['data'] is Map) {
      return raw['data']['id']?.toString();
    }
    if (raw is Map && raw['data'] is List && raw['data'].isNotEmpty) {
      final first = raw['data'].first;
      if (first is Map && first['id'] != null) {
        return first['id'].toString();
      }
    }
    return null;
  }

  bool _isQueryFieldIssue(DioException e) {
    final message = _extractMessage(e).toLowerCase();
    return message.contains('field') ||
        message.contains('unknown') ||
        message.contains("doesn't exist") ||
        message.contains('does not exist') ||
        message.contains('invalid query');
  }

  String _extractMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final errors = data['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        if (first is Map && first['message'] != null) {
          return first['message'].toString();
        }
      }
      if (data['message'] != null) {
        return data['message'].toString();
      }
    }
    return e.message ?? 'Request failed';
  }

  String _planName(String code) {
    final normalized = code.trim().toLowerCase();
    if (normalized == 'business') return 'Business';
    if (normalized == 'free' || normalized.isEmpty) return 'Free';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  Map<String, dynamic> _planToJson(Plan plan) {
    return {
      'id': plan.id,
      'name': plan.name,
      'code': plan.code,
      'description': plan.description,
      'monthly_price': plan.monthlyPrice,
      'yearly_price': plan.yearlyPrice,
      'trial_days': plan.trialDays,
      'max_members': plan.maxMembers,
      'is_business': plan.isBusiness,
      'features': plan.features,
      'is_popular': plan.isPopular,
      'is_active': plan.isActive,
      'sort_order': plan.sortOrder,
    };
  }
}

class _SubscriptionException implements Exception {
  final String message;
  const _SubscriptionException(this.message);

  @override
  String toString() => message;
}
