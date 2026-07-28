import 'package:dio/dio.dart';

import '../models/business_automation_rule.dart';
import '../models/business_invoice.dart';
import '../models/business_location.dart';
import '../models/business_upgrade_request.dart';
import '../state/session.dart';
import 'directus_client.dart';
import 'organization_service.dart';

class BusinessCenterService {
  BusinessCenterService._();

  static final BusinessCenterService instance = BusinessCenterService._();

  Dio get _client => DirectusClient.instance.client;

  Future<BusinessUpgradeRequest?>
  fetchLatestUpgradeRequestForCurrentUser() async {
    final userId = Session.instance.userId;
    if (userId == null || userId.isEmpty) return null;

    final response = await _client.get(
      '/items/business_upgrade_requests',
      queryParameters: {
        'limit': 1,
        'sort': '-requested_at,-date_created',
        'filter[requested_by_user][_eq]': userId,
        'fields':
            'id,requested_by_user,requested_at,status,requested_plan,current_plan,billing_cycle,notes,'
            'base_price_usd,discount_usd,final_price_usd,is_new_user_offer,'
            'company_name,business_name,owner_name,work_email,phone,industry,team_size,country,city,address,website,date_created',
      },
    );
    final data = response.data['data'];
    if (data is List && data.isNotEmpty) {
      final first = data.first;
      if (first is Map<String, dynamic>) {
        return BusinessUpgradeRequest.fromJson(first);
      }
    }
    return null;
  }

  Future<String?> createUpgradeRequest({
    String status = 'pending',
    String? requestedPlan,
    String? currentPlan,
    String? billingCycle,
    String? notes,
    double? basePriceUsd,
    double? discountUsd,
    double? finalPriceUsd,
    bool? isNewUserOffer,
    String? companyName,
    String? businessName,
    String? ownerName,
    String? workEmail,
    String? phone,
    String? industry,
    String? teamSize,
    String? country,
    String? city,
    String? address,
    String? website,
  }) async {
    final userId = Session.instance.userId;
    final payload = <String, dynamic>{
      if (userId != null && userId.isNotEmpty) 'requested_by_user': userId,
      'requested_at': DateTime.now().toUtc().toIso8601String(),
      'status': status,
      if (requestedPlan != null && requestedPlan.trim().isNotEmpty)
        'requested_plan': requestedPlan.trim(),
      if (currentPlan != null && currentPlan.trim().isNotEmpty)
        'current_plan': currentPlan.trim(),
      if (billingCycle != null && billingCycle.trim().isNotEmpty)
        'billing_cycle': billingCycle.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (basePriceUsd != null) 'base_price_usd': basePriceUsd,
      if (discountUsd != null) 'discount_usd': discountUsd,
      if (finalPriceUsd != null) 'final_price_usd': finalPriceUsd,
      if (isNewUserOffer != null) 'is_new_user_offer': isNewUserOffer,
      if (companyName != null && companyName.trim().isNotEmpty)
        'company_name': companyName.trim(),
      if (businessName != null && businessName.trim().isNotEmpty)
        'business_name': businessName.trim(),
      if (ownerName != null && ownerName.trim().isNotEmpty)
        'owner_name': ownerName.trim(),
      if (workEmail != null && workEmail.trim().isNotEmpty)
        'work_email': workEmail.trim().toLowerCase(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (industry != null && industry.trim().isNotEmpty)
        'industry': industry.trim(),
      if (teamSize != null && teamSize.trim().isNotEmpty)
        'team_size': teamSize.trim(),
      if (country != null && country.trim().isNotEmpty)
        'country': country.trim(),
      if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
      if (address != null && address.trim().isNotEmpty)
        'address': address.trim(),
      if (website != null && website.trim().isNotEmpty)
        'website': website.trim(),
    };

    final response = await _client.post(
      '/items/business_upgrade_requests',
      data: payload,
    );
    return _extractCreatedId(response);
  }

  Future<List<BusinessLocation>> fetchLocations({
    String? orgId,
    int limit = 100,
  }) async {
    final scopedOrgId = await _resolveOrgId(orgId);
    final response = await _client.get(
      '/items/business_locations',
      queryParameters: {
        'limit': limit,
        'sort': '-date_created',
        if (scopedOrgId != null && scopedOrgId.isNotEmpty)
          'filter[org_id][_eq]': scopedOrgId,
        'fields':
            'id,org_id,location_name,code,city,country,address,manager,is_active,date_created',
      },
    );
    final data = response.data['data'];
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(BusinessLocation.fromJson)
          .toList();
    }
    return const [];
  }

  Future<List<BusinessAutomationRule>> fetchAutomationRules({
    String? orgId,
    int limit = 100,
  }) async {
    final scopedOrgId = await _resolveOrgId(orgId);
    final response = await _client.get(
      '/items/business_automation_rules',
      queryParameters: {
        'limit': limit,
        'sort': '-date_created',
        if (scopedOrgId != null && scopedOrgId.isNotEmpty)
          'filter[org_id][_eq]': scopedOrgId,
        'fields':
            'id,org_id,rule_name,trigger,action,threshold,cooldown_minutes,is_active,date_created',
      },
    );
    final data = response.data['data'];
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(BusinessAutomationRule.fromJson)
          .toList();
    }
    return const [];
  }

  Future<List<BusinessInvoice>> fetchInvoices({
    String? orgId,
    int limit = 100,
  }) async {
    final scopedOrgId = await _resolveOrgId(orgId);
    final response = await _client.get(
      '/items/business_invoices',
      queryParameters: {
        'limit': limit,
        'sort': '-date_created',
        if (scopedOrgId != null && scopedOrgId.isNotEmpty)
          'filter[org_id][_eq]': scopedOrgId,
        'fields':
            'id,org_id,invoice_number,amount,currency,billing_cycle,due_date,status,payment_reference,date_created',
      },
    );
    final data = response.data['data'];
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(BusinessInvoice.fromJson)
          .toList();
    }
    return const [];
  }

  Future<String?> _resolveOrgId(String? provided) async {
    if (provided != null && provided.trim().isNotEmpty) {
      return provided.trim();
    }
    final org = await OrganizationService.instance.fetchPrimaryOrganization();
    if (org == null || org.id.trim().isEmpty) return null;
    return org.id.trim();
  }

  String? _extractCreatedId(Response response) {
    final data = response.data;
    if (data is Map && data['data'] is Map) {
      return data['data']['id']?.toString();
    }
    if (data is Map && data['data'] is List && data['data'].isNotEmpty) {
      final first = data['data'].first;
      if (first is Map && first['id'] != null) {
        return first['id'].toString();
      }
    }
    return null;
  }
}
