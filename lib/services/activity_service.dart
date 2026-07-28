import 'package:dio/dio.dart';
import '../models/activity_event.dart';
import '../state/session.dart';
import 'directus_client.dart';
import 'organization_service.dart';

class ActivityService {
  ActivityService._();

  static final ActivityService instance = ActivityService._();

  Dio get _client => DirectusClient.instance.client;

  Future<List<ActivityEvent>> fetchEvents({int limit = 50}) async {
    final userId = Session.instance.userId;
    if (userId == null || userId.isEmpty) {
      return const [];
    }

    String? businessProfileId;
    List<String> teamUserIds = const [];
    try {
      businessProfileId = await OrganizationService.instance
          .fetchPrimaryBusinessProfileId();
      teamUserIds = await OrganizationService.instance.fetchBusinessTeamUserIds(
        businessProfileId: businessProfileId,
        limit: 250,
      );
    } on DioException {
      // Best-effort business scoping.
    }

    if (Session.instance.isAdmin) {
      final adminQuery = <String, dynamic>{
        'sort': '-date_created',
        'limit': limit,
        'fields':
            'id,action,entity_type,entity_id,payload,date_created,'
            'business_profile,business_profile.id,'
            'actor,actor.id,actor.email,actor.first_name,actor.last_name,'
            'target_user,target_user.id,target_user.email,target_user.first_name,target_user.last_name',
      };
      final adminResults = await _fetch(baseQuery: adminQuery);
      if (adminResults.isNotEmpty) {
        return adminResults;
      }
    }
    final baseQuery = <String, dynamic>{
      'sort': '-date_created',
      'limit': limit,
      'fields':
          'id,action,entity_type,entity_id,payload,date_created,'
          'business_profile,business_profile.id,'
          'actor,actor.id,actor.email,actor.first_name,actor.last_name,'
          'target_user,target_user.id,target_user.email,target_user.first_name,target_user.last_name',
    };

    if (businessProfileId != null && businessProfileId.isNotEmpty) {
      final profileQuery = <String, dynamic>{
        ...baseQuery,
        'filter[business_profile][_eq]': businessProfileId,
      };
      final profileEvents = await _fetch(baseQuery: profileQuery);
      if (profileEvents.isNotEmpty) {
        return profileEvents;
      }
      final profileIdQuery = <String, dynamic>{
        ...baseQuery,
        'filter[business_profile][id][_eq]': businessProfileId,
      };
      final profileIdEvents = await _fetch(baseQuery: profileIdQuery);
      if (profileIdEvents.isNotEmpty) {
        return profileIdEvents;
      }
    }

    if (teamUserIds.isNotEmpty) {
      final ids = teamUserIds.where((id) => id.trim().isNotEmpty).join(',');
      if (ids.isNotEmpty) {
        final teamQuery = <String, dynamic>{
          ...baseQuery,
          'filter[_or][0][actor][_in]': ids,
          'filter[_or][1][target_user][_in]': ids,
        };
        final teamEvents = await _fetch(baseQuery: teamQuery);
        if (teamEvents.isNotEmpty) {
          return teamEvents;
        }
        final teamIdQuery = <String, dynamic>{
          ...baseQuery,
          'filter[_or][0][actor][id][_in]': ids,
          'filter[_or][1][target_user][id][_in]': ids,
        };
        final teamIdEvents = await _fetch(baseQuery: teamIdQuery);
        if (teamIdEvents.isNotEmpty) {
          return teamIdEvents;
        }
      }
    }

    final filteredQuery = <String, dynamic>{
      ...baseQuery,
      'filter[_or][0][actor][_eq]': userId,
      'filter[_or][1][target_user][_eq]': userId,
    };
    final altQuery = <String, dynamic>{
      ...baseQuery,
      'filter[_or][0][actor][id][_eq]': userId,
      'filter[_or][1][target_user][id][_eq]': userId,
    };
    try {
      final primary = await _fetch(baseQuery: filteredQuery);
      if (primary.length >= 5) {
        return primary;
      }
      final alt = await _fetch(baseQuery: altQuery);
      if (alt.length >= 5) {
        return alt;
      }
      final merged = <String, ActivityEvent>{};
      for (final item in primary) {
        merged[item.id] = item;
      }
      for (final item in alt) {
        merged[item.id] = item;
      }

      final actorQuery = <String, dynamic>{
        ...baseQuery,
        'filter[actor][_eq]': userId,
      };
      final targetQuery = <String, dynamic>{
        ...baseQuery,
        'filter[target_user][_eq]': userId,
      };
      final actorIdQuery = <String, dynamic>{
        ...baseQuery,
        'filter[actor][id][_eq]': userId,
      };
      final targetIdQuery = <String, dynamic>{
        ...baseQuery,
        'filter[target_user][id][_eq]': userId,
      };

      final extra = await Future.wait([
        _fetch(baseQuery: actorQuery),
        _fetch(baseQuery: targetQuery),
        _fetch(baseQuery: actorIdQuery),
        _fetch(baseQuery: targetIdQuery),
      ]);
      for (final list in extra) {
        for (final item in list) {
          merged[item.id] = item;
        }
      }

      final values = merged.values.toList()
        ..sort((a, b) {
          final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
          return bTime.compareTo(aTime);
        });
      if (values.length >= 5) {
        return values;
      }

      final unfiltered = await _fetch(baseQuery: baseQuery);
      if (unfiltered.isEmpty) return values;
      final filteredLocal = _filterForUser(
        unfiltered,
        userId,
        includeOrphans: true,
      );
      if (filteredLocal.length >= values.length) {
        return filteredLocal;
      }
      return values;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? 0;
      if (status != 403 && status != 400) rethrow;
      if (status == 400) {
        final retry = await _fetch(baseQuery: altQuery);
        if (retry.isNotEmpty) return retry;
      }
      return const [];
    }
  }

  List<ActivityEvent> _filterForUser(
    List<ActivityEvent> items,
    String userId, {
    required bool includeOrphans,
  }) {
    final email = Session.instance.userEmail?.toLowerCase();
    return items.where((event) {
      final actorId = event.actorId?.trim();
      final targetId = event.targetUserId?.trim();
      if (actorId != null && actorId == userId) return true;
      if (targetId != null && targetId == userId) return true;
      if (email != null) {
        final actorEmail = event.actorEmail?.toLowerCase();
        final targetEmail = event.targetUserEmail?.toLowerCase();
        if (actorEmail == email || targetEmail == email) return true;
      }
      final payload = event.payload;
      final payloadUser =
          payload['user'] ??
          payload['user_id'] ??
          payload['target_user'] ??
          payload['requested_for'];
      if (payloadUser != null && payloadUser.toString() == userId) {
        return true;
      }
      if (includeOrphans &&
          (actorId == null || actorId.isEmpty) &&
          (targetId == null || targetId.isEmpty)) {
        return true;
      }
      return false;
    }).toList();
  }

  Future<List<ActivityEvent>> _fetch({
    required Map<String, dynamic> baseQuery,
  }) async {
    try {
      final response = await _client.get(
        '/items/activity_events',
        queryParameters: baseQuery,
      );
      final data = response.data['data'];
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(ActivityEvent.fromJson)
            .toList();
      }
      return const [];
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? 0;
      if (status != 403 && status != 400) rethrow;
      return const [];
    }
  }
}
