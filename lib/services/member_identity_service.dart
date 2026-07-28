import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../state/session.dart';
import 'directus_client.dart';

class MemberIdentityRecord {
  final String memberId;
  final String userId;
  final String name;
  final String? email;
  final String? firstName;
  final String? lastName;
  final String? employeeCode;
  final String departmentName;
  final bool requiresLinking;

  const MemberIdentityRecord({
    required this.memberId,
    required this.userId,
    required this.name,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.employeeCode,
    required this.departmentName,
    required this.requiresLinking,
  });

  String get displayEmail {
    final value = email?.trim() ?? '';
    if (value.isNotEmpty) return value;
    return MemberIdentityService.memberProfileUnavailableLabel;
  }
}

class MemberIdentityService {
  MemberIdentityService._();

  static final MemberIdentityService instance = MemberIdentityService._();
  static const String memberProfileUnavailableLabel =
      'Member profile unavailable';
  static const String memberProfileNeedsLinkingLabel =
      memberProfileUnavailableLabel;
  static const String emailUnavailableLabel = memberProfileUnavailableLabel;
  static const String noDepartmentLabel = 'Unassigned';
  static const String memberFields =
      'id,status,member_role,employee_code,job_title,business_profile,'
      'department,department.id,department.name,user,user.id,user.email,'
      'user.first_name,user.last_name,last_scan_at,last_readiness_score,'
      'last_risk_level';
  static const String minimalMemberFields =
      'id,status,member_role,business_profile,department,user';

  Dio get _client => DirectusClient.instance.client;

  Future<List<Map<String, dynamic>>> fetchBusinessProfileMembers({
    required String screen,
    required String businessProfileId,
    int limit = 500,
    String? sort,
    bool activeOnly = false,
    String? departmentId,
    Iterable<String>? memberIds,
    String? role,
    String? membershipId,
  }) async {
    final profileId = businessProfileId.trim();
    if (profileId.isEmpty) return const [];

    final ids = (memberIds ?? const <String>[])
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    debugPrint(
      '[MOBILE_MEMBER_IDENTITY_FETCH_START] screen=$screen business_profile=$profileId limit=$limit active_only=$activeOnly department_id=${departmentId?.trim() ?? ''} member_ids=${ids.join(",")}',
    );
    debugPrint(
      '[WORKFORCE_SOURCE] screen=$screen role=${role?.trim().isNotEmpty == true ? role!.trim() : "unknown"} business_profile=$profileId membership_id=${membershipId?.trim().isNotEmpty == true ? membershipId!.trim() : "missing"} department=${departmentId?.trim().isNotEmpty == true ? departmentId!.trim() : "none"}',
    );
    final normalizedRole =
        role?.trim().isNotEmpty == true ? role!.trim() : 'unknown';
    final normalizedMembershipId = membershipId?.trim() ?? '';
    if (normalizedMembershipId.isEmpty &&
        (screen == 'OwnerWorkforce' ||
            screen == 'HrWorkforce' ||
            screen == 'ManagerWorkforce' ||
            screen == 'ManagerTeam')) {
      debugPrint(
        '[WORKFORCE_CONTEXT_MISMATCH] expected_role=$normalizedRole',
      );
      debugPrint('[WORKFORCE_CONTEXT_MISMATCH] membership_id_missing=true');
    }

    final query = <String, dynamic>{
      'limit': limit,
      'fields': memberFields,
      'filter[business_profile][_eq]': profileId,
      if (sort != null && sort.trim().isNotEmpty) 'sort': sort.trim(),
      if (departmentId != null && departmentId.trim().isNotEmpty)
        'filter[department][_eq]': departmentId.trim(),
      if (activeOnly &&
          (screen == 'OwnerWorkforce' ||
              screen == 'HrWorkforce' ||
              screen == 'ManagerWorkforce'))
        'filter[status][_in]': 'active,pending',
      if (activeOnly &&
          screen != 'OwnerWorkforce' &&
          screen != 'HrWorkforce' &&
          screen != 'ManagerWorkforce')
        'filter[status][_eq]': 'active',
      if (ids.isNotEmpty) 'filter[id][_in]': ids.join(','),
    };

    debugPrint(
      '[WORKFORCE_QUERY] screen=$screen business_profile=$profileId query=$query fields=${query['fields']}',
    );
    debugPrint(
      '[WORKFORCE_CLIENT_STATE] screen=$screen client_instance_id=${DirectusClient.instance.instanceId} dio_instance_id=${DirectusClient.instance.dioInstanceId} token_fp=${DirectusClient.tokenFingerprint(Session.instance.accessToken)} membership_id=${normalizedMembershipId.isNotEmpty ? normalizedMembershipId : 'missing'} business_profile=$profileId',
    );
    debugPrint(
      '[WORKFORCE_PRIMARY] query_scope=${_describeQueryScope(departmentId: departmentId, memberIds: ids)}',
    );
    debugPrint(
      '[WORKFORCE_IDENTITY_REQUEST] membership_id_present=${normalizedMembershipId.isNotEmpty} business_profile_present=${profileId.isNotEmpty} member_count=${ids.length}',
    );

    try {
      final response = await _client.get(
        '/items/business_profile_members',
        queryParameters: query,
      );
      final hydrated = await _handleMembersResponse(
        screen: screen,
        businessProfileId: profileId,
        response: response,
      );
      debugPrint(
        '[WORKFORCE_PRIMARY] status=${response.statusCode} count=${hydrated.length}',
      );
      if (activeOnly && hydrated.isEmpty) {
        final fallbackQuery = Map<String, dynamic>.from(query)
          ..remove('filter[status][_eq]')
          ..['filter[status][_in]'] = 'active,accepted';
        debugPrint(
          '[WORKFORCE_FALLBACK] primary_zero=true fallback_query=$fallbackQuery',
        );
        try {
          final fallbackResponse = await _client.get(
            '/items/business_profile_members',
            queryParameters: fallbackQuery,
          );
          final fallbackHydrated = await _handleMembersResponse(
            screen: screen,
            businessProfileId: profileId,
            response: fallbackResponse,
          );
          debugPrint(
            '[WORKFORCE_FALLBACK] primary_zero=true fallback_used=${fallbackHydrated.isNotEmpty} count=${fallbackHydrated.length}',
          );
          if (fallbackHydrated.isNotEmpty) {
            debugPrint('[WORKFORCE_FINAL] count=${fallbackHydrated.length} source=fallback');
            return fallbackHydrated;
          }
        } on DioException catch (fallbackError, fallbackSt) {
          debugPrint(
            '[WORKFORCE_FALLBACK] primary_zero=true fallback_used=false status=${fallbackError.response?.statusCode} body=${fallbackError.response?.data} message=${fallbackError.message}',
          );
          debugPrint('[WORKFORCE_FALLBACK] stackTrace=$fallbackSt');
        }

        final identityFallback = await _fetchAuthorizedVisibleMemberRows(
          screen: screen,
          businessProfileId: profileId,
          limit: limit,
          sort: sort,
          departmentId: departmentId,
          role: role,
          membershipId: normalizedMembershipId,
        );
        if (identityFallback.isNotEmpty) {
          debugPrint(
            '[WORKFORCE_FALLBACK] primary_zero=true fallback_used=true count=${identityFallback.length}',
          );
          debugPrint(
            '[WORKFORCE_FINAL] count=${identityFallback.length} source=identity',
          );
          return identityFallback;
        }
      }
      debugPrint('[WORKFORCE_FINAL] count=${hydrated.length} source=primary');
      return hydrated;
    } on DioException catch (e, st) {
      debugPrint(
        '[WORKFORCE_QUERY] screen=$screen business_profile=$profileId status=${e.response?.statusCode} body=${e.response?.data} message=${e.message}',
      );
      debugPrint('[WORKFORCE_QUERY] stackTrace=$st');
      final status = e.response?.statusCode ?? 0;
      final isMembershipScopeUnavailable =
          status == 403 &&
          e.response?.data.toString().contains('MEMBERSHIP_SCOPE_UNAVAILABLE') ==
              true;
      if (isMembershipScopeUnavailable) {
        debugPrint(
          '[WORKFORCE_QUERY_FALLBACK] screen=$screen business_profile=$profileId status=${e.response?.statusCode} body=${e.response?.data} message=${e.message}',
        );
        debugPrint('[WORKFORCE_QUERY_FALLBACK] stackTrace=$st');
        debugPrint('[WORKFORCE_FINAL] count=0 source=scope_error');
        rethrow;
      }
      if (status == 403) {
        debugPrint(
          '[WORKFORCE_QUERY_FIELD_MISMATCH] screen=$screen business_profile=$profileId failing_fields=${query['fields']} retry_fields=$minimalMemberFields',
        );
        try {
          final fallbackResponse = await _client.get(
            '/items/business_profile_members',
            queryParameters: {
              ...query,
              'fields': minimalMemberFields,
            },
          );
          return _handleMembersResponse(
            screen: screen,
            businessProfileId: profileId,
            response: fallbackResponse,
          );
        } on DioException catch (fallbackError, fallbackSt) {
          debugPrint(
            '[WORKFORCE_QUERY_FALLBACK] screen=$screen business_profile=$profileId status=${fallbackError.response?.statusCode} body=${fallbackError.response?.data} message=${fallbackError.message}',
          );
          debugPrint('[WORKFORCE_QUERY_FALLBACK] stackTrace=$fallbackSt');
          if (fallbackError.response?.statusCode == 403) {
            debugPrint(
              '[MEMBERS_PERMISSION_REQUIRED] screen=$screen required_permissions=business_profile_members.read departments.read member_identity_endpoint',
            );
          }
          rethrow;
        }
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAuthorizedVisibleMemberRows({
    required String screen,
    required String businessProfileId,
    required int limit,
    required String? sort,
    required String? departmentId,
    required String? role,
    required String membershipId,
  }) async {
    debugPrint(
      '[WORKFORCE_FALLBACK] attempted=true reason=primary_zero_authorized_identity',
    );
    final normalizedRole =
        role?.trim().isNotEmpty == true ? role!.trim() : 'unknown';
    if (membershipId.trim().isEmpty &&
        (screen == 'OwnerWorkforce' ||
            screen == 'HrWorkforce' ||
            screen == 'ManagerWorkforce' ||
            screen == 'ManagerTeam')) {
      debugPrint(
        '[WORKFORCE_CONTEXT_MISMATCH] role=$normalizedRole membership_id_missing=true business_profile=$businessProfileId',
      );
      debugPrint('[WORKFORCE_FINAL] count=0 source=empty');
      return const [];
    }
    final scopedUsersByMemberId = await _fetchScopedUserRelations(
      businessProfileId: businessProfileId,
      memberIds: const <String>[],
      screen: screen,
      membershipId: membershipId,
    );
    final authorizedIds = scopedUsersByMemberId.keys.toList();
    debugPrint(
      '[WORKFORCE_FALLBACK] member_ids_count=${authorizedIds.length}',
    );
    if (authorizedIds.isEmpty) {
      debugPrint('[WORKFORCE_FINAL] count=0 source=empty');
      return const [];
    }

    final fallbackQuery = <String, dynamic>{
      'limit': authorizedIds.length.clamp(1, limit),
      'fields': minimalMemberFields,
      'filter[business_profile][_eq]': businessProfileId,
      'filter[id][_in]': authorizedIds.join(','),
      if (sort != null && sort.trim().isNotEmpty) 'sort': sort.trim(),
      if (departmentId != null && departmentId.trim().isNotEmpty)
        'filter[department][_eq]': departmentId.trim(),
    };

    debugPrint(
      '[WORKFORCE_QUERY] screen=$screen business_profile=$businessProfileId query=$fallbackQuery fields=${fallbackQuery['fields']}',
    );
    debugPrint(
      '[WORKFORCE_CLIENT_STATE] screen=$screen client_instance_id=${DirectusClient.instance.instanceId} dio_instance_id=${DirectusClient.instance.dioInstanceId} token_fp=${DirectusClient.tokenFingerprint(Session.instance.accessToken)} business_profile=$businessProfileId authorized_member_count=${authorizedIds.length}',
    );
    debugPrint(
      '[WORKFORCE_PRIMARY] query_scope=${_describeQueryScope(departmentId: departmentId, memberIds: authorizedIds)}',
    );

    try {
      final fallbackResponse = await _client.get(
        '/items/business_profile_members',
        queryParameters: fallbackQuery,
      );
      final hydrated = await _handleMembersResponse(
        screen: screen,
        businessProfileId: businessProfileId,
        response: fallbackResponse,
      );
      debugPrint(
        '[WORKFORCE_PRIMARY] status=${fallbackResponse.statusCode} count=${hydrated.length}',
      );
      return hydrated;
    } on DioException catch (e, st) {
      final isMembershipScopeUnavailable =
          e.response?.statusCode == 403 &&
          e.response?.data.toString().contains('MEMBERSHIP_SCOPE_UNAVAILABLE') ==
              true;
      if (isMembershipScopeUnavailable) {
        debugPrint(
          '[WORKFORCE_CONTEXT_MISMATCH] role=$normalizedRole membership_id=${membershipId.trim()} business_profile=$businessProfileId',
        );
        debugPrint(
          '[WORKFORCE_CONTEXT_MISMATCH] membership_scope_unavailable=true',
        );
        debugPrint('[WORKFORCE_FINAL] count=0 source=scope_error');
        rethrow;
      }
      debugPrint(
        '[WORKFORCE_QUERY_FALLBACK] screen=$screen business_profile=$businessProfileId status=${e.response?.statusCode} body=${e.response?.data} message=${e.message}',
      );
      debugPrint('[WORKFORCE_QUERY_FALLBACK] stackTrace=$st');
      debugPrint('[WORKFORCE_FINAL] count=0 source=empty');
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _handleMembersResponse({
    required String screen,
    required String businessProfileId,
    required Response<dynamic> response,
  }) async {
    final data = response.data['data'];
    if (data is! List) return const [];
    final rows = data
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final hydrated = await _hydrateFallbackUsers(
      screen: screen,
      businessProfileId: businessProfileId,
      memberRows: rows,
    );
    debugPrint(
      '[WORKFORCE_QUERY] screen=$screen business_profile=$businessProfileId status=${response.statusCode} count=${hydrated.length}',
    );
    return hydrated;
  }

  Future<Map<String, MemberIdentityRecord>> fetchUsersByIds(
    Iterable<String> userIds, {
    required String context,
  }) async {
    final ids = userIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return const {};
    debugPrint(
      '[MOBILE_MEMBER_IDENTITY_FALLBACK_USED] context=$context directus_users_lookup=disabled user_ids=${ids.join(",")}',
    );
    return const <String, MemberIdentityRecord>{};
  }

  MemberIdentityRecord resolveFromUserRelation(
    dynamic userRelation, {
    required String context,
    required String memberId,
    String? role,
    dynamic departmentRaw,
    String? employeeCode,
    Map<String, MemberIdentityRecord>? hydratedUsersById,
  }) {
    final raw = userRelation;
    String userId = '';
    String? fullName;
    String? firstName;
    String? lastName;
    String? email;

    if (raw is Map) {
      userId = _text(raw['id']) ?? '';
      fullName = _text(raw['full_name']);
      firstName = _text(raw['first_name']);
      lastName = _text(raw['last_name']);
      email = _text(raw['email']);
    } else if (raw != null) {
      userId = raw.toString().trim();
    }

    final hydrated = userId.isNotEmpty && hydratedUsersById != null
        ? hydratedUsersById[userId]
        : null;
    final hasExpandedUserData = raw is Map &&
        (_text(raw['email']) != null ||
            _text(raw['full_name']) != null ||
            _text(raw['first_name']) != null ||
            _text(raw['last_name']) != null);

    if (raw == null) {
      debugPrint(
        '[MOBILE_MEMBER_IDENTITY_RAW_UUID] context=$context member_id=$memberId user_raw=null',
      );
    } else if (raw is Map) {
      if (hasExpandedUserData) {
        debugPrint(
          '[MOBILE_MEMBER_IDENTITY_EXPANDED_USER] context=$context member_id=$memberId user_id=$userId raw=$raw',
        );
      } else if (userId.isNotEmpty) {
        debugPrint(
          '[MOBILE_MEMBER_IDENTITY_RAW_UUID] context=$context member_id=$memberId user_id=$userId raw=$raw',
        );
      } else {
        debugPrint(
          '[MOBILE_MEMBER_IDENTITY_HYDRATION_FAILED] context=$context member_id=$memberId reason=invalid_user_relation raw=$raw',
        );
      }
    } else {
      debugPrint(
        '[MOBILE_MEMBER_IDENTITY_RAW_UUID] context=$context member_id=$memberId user_id=$userId raw=$raw',
      );
    }

    final resolvedFirst = _firstNonEmpty(firstName, hydrated?.firstName);
    final resolvedLast = _firstNonEmpty(lastName, hydrated?.lastName);
    final resolvedEmail = _firstNonEmpty(email, hydrated?.email);
    final displayName = buildDisplayName(
      memberId: memberId,
      fullName: fullName,
      firstName: resolvedFirst,
      lastName: resolvedLast,
      email: resolvedEmail,
      employeeCode: employeeCode,
    );
    final resolvedDepartment = resolveDepartmentName(
      departmentRelation: departmentRaw,
    );
    final requiresLinking = displayName == memberProfileUnavailableLabel;
    final displayEmail = _text(resolvedEmail);

    final resolvedViaHydration = hydrated != null ||
        hasExpandedUserData ||
        (_text(fullName) != null ||
            _text(firstName) != null ||
            _text(lastName) != null ||
            _text(email) != null);
    if (!resolvedViaHydration) {
      final missingReason = _describeMissingUserRelationReason(
        raw: raw,
        userId: userId,
        hydrated: hydrated,
      );
      debugPrint(
        '[MOBILE_MEMBER_IDENTITY_HYDRATION_FAILED] context=$context member_id=$memberId user_id=$userId reason=$missingReason raw=$raw',
      );
    }

    debugPrint(
      '[MOBILE_MEMBER_IDENTITY_RESOLVED] context=$context member_id=$memberId member_role=${role ?? ''} department=$resolvedDepartment user_id=$userId first_name=${resolvedFirst ?? ''} last_name=${resolvedLast ?? ''} email=${resolvedEmail ?? ''} display_name=$displayName display_email=${displayEmail ?? emailUnavailableLabel} requires_linking=$requiresLinking',
    );

    if (requiresLinking) {
      debugPrint(
        '[MOBILE_MEMBER_IDENTITY_FALLBACK_USED] context=$context member_id=$memberId user_id=$userId reason=member_profile_needs_linking',
      );
    }

    return MemberIdentityRecord(
      memberId: memberId,
      userId: userId,
      name: displayName,
      email: displayEmail,
      firstName: resolvedFirst,
      lastName: resolvedLast,
      employeeCode: _text(employeeCode),
      departmentName: resolvedDepartment,
      requiresLinking: requiresLinking,
    );
  }

  String buildDisplayName({
    required String memberId,
    String? fullName,
    String? firstName,
    String? lastName,
    String? email,
    String? employeeCode,
  }) {
    final normalizedFullName = _text(fullName);
    if (normalizedFullName != null && normalizedFullName.isNotEmpty) {
      return normalizedFullName;
    }
    final first = _text(firstName);
    final last = _text(lastName);
    if (first != null && first.isNotEmpty) {
      if (last != null && last.isNotEmpty) return '$first $last';
      return first;
    }
    final normalizedEmail = _text(email);
    if (normalizedEmail != null && normalizedEmail.isNotEmpty) {
      return normalizedEmail;
    }
    return memberProfileUnavailableLabel;
  }

  String resolveDepartmentName({required dynamic departmentRelation}) {
    final relationName = departmentRelation is Map
        ? _text(departmentRelation['name'])
        : null;
    return relationName ?? noDepartmentLabel;
  }

  String? resolveDepartmentId(dynamic departmentRelation) {
    if (departmentRelation is Map) {
      return _text(departmentRelation['id']);
    }
    return _text(departmentRelation);
  }

  Future<List<Map<String, dynamic>>> _hydrateFallbackUsers({
    required String screen,
    required String businessProfileId,
    required List<Map<String, dynamic>> memberRows,
  }) async {
    final unresolvedMemberIds = memberRows
        .where((row) => _needsUserFallback(row['user']))
        .map((row) => row['id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (unresolvedMemberIds.isEmpty) return memberRows;

    debugPrint(
      '[WORKFORCE_USER_FALLBACK] screen=$screen business_profile=$businessProfileId member_ids=${unresolvedMemberIds.join(",")}',
    );

    try {
      final response = await _client.get(
        '/items/business_profile_members',
        queryParameters: {
          'limit': unresolvedMemberIds.length.clamp(1, 500),
          'fields': 'id,user',
          'filter[business_profile][_eq]': businessProfileId,
          'filter[id][_in]': unresolvedMemberIds.join(','),
        },
      );
      final data = response.data['data'];
      if (data is! List) return memberRows;

      final fallbackRows = data.whereType<Map<String, dynamic>>().toList();
      final fallbackByMemberId = <String, Map<String, dynamic>>{
        for (final row in fallbackRows)
          if ((row['id']?.toString().trim() ?? '').isNotEmpty)
            row['id'].toString().trim(): row,
      };
      final endpointUsersByMemberId = await _fetchScopedUserRelations(
        businessProfileId: businessProfileId,
        memberIds: unresolvedMemberIds,
        screen: screen,
      );

      var mergedCount = 0;
      for (final row in memberRows) {
        final memberId = row['id']?.toString().trim() ?? '';
        if (!unresolvedMemberIds.contains(memberId)) continue;

        final mergedUser = _mergeUserRelation(
          currentUserRelation: row['user'],
          fallbackUserRelation:
              endpointUsersByMemberId[memberId] ??
              fallbackByMemberId[memberId]?['user'],
          usersById: const <String, MemberIdentityRecord>{},
        );
        if (mergedUser != null) {
          row['user'] = mergedUser;
          mergedCount += 1;
        }

        final finalUserId = _extractUserId(row['user']);
        final finalUser = row['user'];
        if (_needsUserFallback(finalUser) && finalUserId.isEmpty) {
          debugPrint(
            '[WORKFORCE_NULL_USER_CONFIRMED] screen=$screen member_id=$memberId role=${row["member_role"] ?? ""} department=${resolveDepartmentName(departmentRelation: row["department"])}',
          );
        }
      }

      debugPrint(
        '[WORKFORCE_USER_MERGED] screen=$screen business_profile=$businessProfileId requested_members=${unresolvedMemberIds.length} merged_members=$mergedCount hydrated_users=${endpointUsersByMemberId.length}',
      );
      if (mergedCount == 0 && unresolvedMemberIds.isNotEmpty) {
        debugPrint(
          '[MOBILE_MEMBER_IDENTITY_HYDRATION_FAILED] screen=$screen business_profile=$businessProfileId unresolved_members=${unresolvedMemberIds.join(",")} endpoint_members=${endpointUsersByMemberId.length}',
        );
      }
    } on DioException catch (e) {
      debugPrint(
        '[WORKFORCE_USER_FALLBACK] screen=$screen business_profile=$businessProfileId status=${e.response?.statusCode} body=${e.response?.data} message=${e.message}',
      );
      debugPrint(
        '[MOBILE_MEMBER_IDENTITY_HYDRATION_FAILED] screen=$screen business_profile=$businessProfileId status=${e.response?.statusCode} message=${e.message}',
      );
    }

    return memberRows;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchScopedUserRelations({
    required String businessProfileId,
    required List<String> memberIds,
    required String screen,
    String? membershipId,
  }) async {
    final inferredRole = screen == 'OwnerWorkforce'
        ? 'owner'
        : screen == 'HrWorkforce'
            ? 'hr'
            : screen == 'ManagerWorkforce'
                ? 'manager'
                : 'unknown';
    final normalizedMembershipId = membershipId?.trim() ?? '';

    try {
      final body = <String, dynamic>{
        'business_profile': businessProfileId,
        if (memberIds.isNotEmpty) 'member_ids': memberIds,
        if (normalizedMembershipId.isNotEmpty)
          'membership_id': normalizedMembershipId,
      };
      final response = await _client.post(
        AppConfig.scopedMemberIdentityPath,
        data: body,
      );
      debugPrint(
        '[WORKFORCE_IDENTITY_CLIENT_STATE] screen=$screen client_instance_id=${DirectusClient.instance.instanceId} dio_instance_id=${DirectusClient.instance.dioInstanceId} token_fp=${DirectusClient.tokenFingerprint(Session.instance.accessToken)} membership_id=${normalizedMembershipId.isNotEmpty ? normalizedMembershipId : 'missing'} business_profile=$businessProfileId',
      );
      final data = response.data['data'];
      if (data is! List) return const {};
      final hydrated = <String, Map<String, dynamic>>{};
      for (final row in data.whereType<Map<String, dynamic>>()) {
        final memberId = row['id']?.toString().trim() ?? '';
        final user = row['user'];
        if (memberId.isEmpty || user is! Map<String, dynamic>) continue;
        hydrated[memberId] = user;
      }
      debugPrint(
        '[WORKFORCE_IDENTITY_ENDPOINT] screen=$screen business_profile=$businessProfileId requested_members=${memberIds.length} hydrated_members=${hydrated.length}',
      );
      return hydrated;
    } on DioException catch (e) {
      final isMembershipScopeUnavailable =
          e.response?.statusCode == 403 &&
          e.response?.data.toString().contains('MEMBERSHIP_SCOPE_UNAVAILABLE') ==
              true;
      if (isMembershipScopeUnavailable) {
        debugPrint(
          '[WORKFORCE_CONTEXT_MISMATCH] role=$inferredRole membership_id=$normalizedMembershipId business_profile=$businessProfileId',
        );
        debugPrint(
          '[WORKFORCE_CONTEXT_MISMATCH] membership_scope_unavailable=true',
        );
        debugPrint('[WORKFORCE_FINAL] count=0 source=scope_error');
        rethrow;
      }
      debugPrint(
        '[WORKFORCE_IDENTITY_ENDPOINT] screen=$screen business_profile=$businessProfileId status=${e.response?.statusCode} body=${e.response?.data} message=${e.message}',
      );
      return const {};
    } catch (e) {
      debugPrint(
        '[WORKFORCE_IDENTITY_ENDPOINT] screen=$screen business_profile=$businessProfileId error=$e',
      );
      return const {};
    }
  }

  String _describeQueryScope({
    required String? departmentId,
    required List<String> memberIds,
  }) {
    final parts = <String>['business_profile'];
    if (departmentId != null && departmentId.trim().isNotEmpty) {
      parts.add('department');
    }
    if (memberIds.isNotEmpty) {
      parts.add('ids');
    }
    return parts.join('/');
  }

  bool _needsUserFallback(dynamic userRelation) {
    if (userRelation == null) return true;
    if (userRelation is Map) {
      return _text(userRelation['email']) == null &&
          _text(userRelation['first_name']) == null &&
          _text(userRelation['last_name']) == null &&
          _text(userRelation['full_name']) == null;
    }
    return true;
  }

  String _extractUserId(dynamic userRelation) {
    if (userRelation is Map) {
      return _text(userRelation['id']) ?? '';
    }
    return _text(userRelation) ?? '';
  }

  String _describeMissingUserRelationReason({
    required dynamic raw,
    required String userId,
    required MemberIdentityRecord? hydrated,
  }) {
    if (raw == null) return 'user_null';
    if (raw is Map) {
      if (userId.isEmpty) return 'invalid_user_id';
      if (hydrated != null) return 'relation_not_expanded';
      return 'user_permission_denied_or_not_found';
    }
    if (raw.toString().trim().isEmpty) return 'invalid_user_id';
    if (hydrated != null) return 'relation_not_expanded';
    return 'relation_not_expanded_or_user_hidden';
  }

  dynamic _mergeUserRelation({
    required dynamic currentUserRelation,
    required dynamic fallbackUserRelation,
    required Map<String, MemberIdentityRecord> usersById,
  }) {
    final userId = _extractUserId(currentUserRelation).isNotEmpty
        ? _extractUserId(currentUserRelation)
        : _extractUserId(fallbackUserRelation);
    if (userId.isEmpty) return null;

    final hydrated = usersById[userId];
    if (hydrated != null) {
      return <String, dynamic>{
        'id': userId,
        'email': hydrated.email,
        'first_name': hydrated.firstName,
        'last_name': hydrated.lastName,
      };
    }
    if (currentUserRelation is Map) return currentUserRelation;
    if (fallbackUserRelation is Map) return fallbackUserRelation;
    return userId;
  }

  String? _firstNonEmpty(String? a, String? b) {
    final first = _text(a);
    if (first != null && first.isNotEmpty) return first;
    final second = _text(b);
    if (second != null && second.isNotEmpty) return second;
    return null;
  }

  static String? _text(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }
}
