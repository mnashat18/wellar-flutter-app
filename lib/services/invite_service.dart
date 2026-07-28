import 'package:dio/dio.dart';
import '../models/invite_details.dart';
import '../state/session.dart';
import 'directus_client.dart';

class InviteService {
  InviteService._();

  static final InviteService instance = InviteService._();

  Dio get _client => DirectusClient.instance.client;

  Future<InviteDetails?> fetchInviteDetails(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) return null;

    final attempts = [
      _InviteFieldAttempt(requestField: 'request', includeExtended: true),
      _InviteFieldAttempt(requestField: 'request_id', includeExtended: true),
      _InviteFieldAttempt(requestField: 'request', includeExtended: false),
      _InviteFieldAttempt(requestField: 'request_id', includeExtended: false),
    ];

    for (final attempt in attempts) {
      try {
        final response = await _client.get(
          '/items/request_invites',
          queryParameters: {
            'filter[token][_eq]': normalized,
            'limit': 1,
            'fields': _inviteFields(
              requestField: attempt.requestField,
              includeExtended: attempt.includeExtended,
            ),
          },
        );
        final data = response.data['data'];
        if (data is List && data.isNotEmpty) {
          final record = data.first;
          if (record is Map<String, dynamic>) {
            return _parseInviteDetails(
              record,
              token: normalized,
              requestField: attempt.requestField,
            );
          }
        }
      } on DioException catch (e) {
        final message = _extractMessage(e).toLowerCase();
        if (message.contains('does not exist') ||
            message.contains('field') ||
            message.contains('request')) {
          continue;
        }
        rethrow;
      }
    }
    return null;
  }

  Future<InviteClaimResult?> claimInviteByToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) return null;

    final attempts = [
      _InviteFieldAttempt(requestField: 'request', includeExtended: false),
      _InviteFieldAttempt(requestField: 'request_id', includeExtended: false),
    ];

    for (final attempt in attempts) {
      try {
        final response = await _client.get(
          '/items/request_invites',
          queryParameters: {
            'filter[token][_eq]': normalized,
            'limit': 1,
            'fields': 'id,token,status,email,${attempt.requestField}',
          },
        );
        final data = response.data['data'];
        if (data is! List || data.isEmpty) return null;
        final record = data.first;
        if (record is! Map<String, dynamic>) return null;

        final inviteId = record['id']?.toString();
        if (inviteId == null || inviteId.isEmpty) return null;

        final status = record['status']?.toString().toLowerCase() ?? '';
        if (status.isNotEmpty && status != 'pending' && status != 'sent') {
          return null;
        }

        final requestRef = record[attempt.requestField];
        String? requestId;
        if (requestRef is Map) {
          requestId = requestRef['id']?.toString();
        } else if (requestRef != null) {
          requestId = requestRef.toString();
        }

        if (requestId == null || requestId.isEmpty) return null;

        final userId = Session.instance.userId;
        if (userId == null || userId.isEmpty) return null;

        await _claimInvite(inviteId);
        await _attachRequestToUser(
          requestId,
          userId,
          email: record['email']?.toString(),
        );

        return InviteClaimResult(inviteId: inviteId, requestId: requestId);
      } on DioException catch (e) {
        final message = _extractMessage(e).toLowerCase();
        if (message.contains('does not exist') ||
            message.contains('field') ||
            message.contains('request')) {
          continue;
        }
        rethrow;
      }
    }
    return null;
  }

  Future<int> claimInvitesForCurrentUser() async {
    final userId = Session.instance.userId;
    final email = Session.instance.userEmail;
    if (userId == null || userId.isEmpty) return 0;
    if (email == null || email.trim().isEmpty) return 0;

    try {
      return await _claimInvites(
        userId: userId,
        email: email.trim().toLowerCase(),
        requestField: 'request',
      );
    } on DioException catch (e) {
      final message = _extractMessage(e).toLowerCase();
      if (message.contains('request') && message.contains('does not exist')) {
        try {
          return await _claimInvites(
            userId: userId,
            email: email.trim().toLowerCase(),
            requestField: 'request_id',
          );
        } on DioException {
          return 0;
        }
      }
      return 0;
    }
  }

  Future<int> _claimInvites({
    required String userId,
    required String email,
    required String requestField,
  }) async {
    final response = await _client.get(
      '/items/request_invites',
      queryParameters: {
        'filter[email][_eq]': email,
        'filter[status][_in]': 'pending,sent,Pending,Sent',
        'fields': 'id,email,$requestField',
        'limit': 25,
      },
    );
    final data = response.data['data'];
    if (data is! List || data.isEmpty) return 0;

    var claimed = 0;
    for (final item in data.whereType<Map<String, dynamic>>()) {
      final inviteId = item['id']?.toString();
      final inviteEmail = item['email']?.toString();
      final requestRef = item[requestField];
      if (inviteId == null || inviteId.isEmpty) continue;

      String? requestId;
      if (requestRef is Map) {
        requestId = requestRef['id']?.toString();
      } else if (requestRef != null) {
        requestId = requestRef.toString();
      }

      if (requestId == null || requestId.isEmpty) continue;
      try {
        await _claimInvite(inviteId);
        await _attachRequestToUser(requestId, userId, email: inviteEmail);
        claimed++;
      } catch (_) {
        continue;
      }
    }
    return claimed;
  }

  Future<void> _claimInvite(String inviteId) async {
    await _client.patch(
      '/items/request_invites/$inviteId',
      data: {
        'status': 'claimed',
        'claimed_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<void> _attachRequestToUser(
    String requestId,
    String userId, {
    String? email,
  }) async {
    final normalizedEmail = email?.trim().toLowerCase();
    try {
      await _client.patch(
        '/items/scan_requests/$requestId',
        data: {
          'requested_for': userId,
          if (normalizedEmail != null && normalizedEmail.isNotEmpty)
            'requested_for_email': normalizedEmail,
          'status': 'pending',
        },
      );
    } on DioException catch (e) {
      final message = _extractMessage(e).toLowerCase();
      if (message.contains('status') && message.contains('does not exist')) {
        await _attachRequestToUserWithoutStatus(
          requestId,
          userId,
          email: normalizedEmail,
        );
        return;
      }
      if (message.contains('requested_for_email') &&
          message.contains('does not exist')) {
        await _client.patch(
          '/items/scan_requests/$requestId',
          data: {'requested_for': userId, 'status': 'pending'},
        );
        return;
      }
      if (message.contains('requested_for') &&
          message.contains('does not exist')) {
        await _client.patch(
          '/items/scan_requests/$requestId',
          data: {
            'requested_for': userId,
            if (normalizedEmail != null && normalizedEmail.isNotEmpty)
              'requested_for_email': normalizedEmail,
            'status': 'pending',
          },
        );
        return;
      }
      rethrow;
    }
  }

  Future<void> _attachRequestToUserWithoutStatus(
    String requestId,
    String userId, {
    String? email,
  }) async {
    try {
      await _client.patch(
        '/items/scan_requests/$requestId',
        data: {
          'requested_for': userId,
          if (email != null && email.isNotEmpty) 'requested_for_email': email,
        },
      );
    } on DioException catch (e) {
      final message = _extractMessage(e).toLowerCase();
      if (message.contains('requested_for') &&
          message.contains('does not exist')) {
        await _client.patch(
          '/items/scan_requests/$requestId',
          data: {
            'requested_for': userId,
            if (email != null && email.isNotEmpty) 'requested_for_email': email,
          },
        );
        return;
      }
      if (message.contains('requested_for_email') &&
          message.contains('does not exist')) {
        await _client.patch(
          '/items/scan_requests/$requestId',
          data: {'requested_for': userId},
        );
        return;
      }
      rethrow;
    }
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

  String _inviteFields({
    required String requestField,
    required bool includeExtended,
  }) {
    final fields = <String>[
      'id',
      'token',
      'status',
      'email',
      'phone',
      'sent_at',
      'claimed_at',
      'expires_at',
      'date_created',
      'business_profile',
      'business_profile.id',
      'business_profile.business_name',
      'business_profile.company_name',
      'requested_by_user',
      'requested_by_user.id',
      'requested_by_user.first_name',
      'requested_by_user.last_name',
      'requested_by_user.email',
      requestField,
    ];
    if (requestField == 'request') {
      fields.addAll([
        '$requestField.id',
        '$requestField.required_state',
        '$requestField.target',
        '$requestField.Target',
      ]);
    }
    if (includeExtended) {
      if (requestField == 'request') {
        fields.addAll([
          '$requestField.requested_by_org',
          '$requestField.requested_by_org.name',
          '$requestField.requested_by_user',
          '$requestField.requested_by_user.first_name',
        ]);
      }
    }
    return fields.join(',');
  }

  InviteDetails _parseInviteDetails(
    Map<String, dynamic> record, {
    required String token,
    required String requestField,
  }) {
    final inviteId = record['id']?.toString() ?? '';
    final status = record['status']?.toString() ?? '';
    final email = record['email']?.toString();
    final phone = record['phone']?.toString();
    final sentAt = _parseDate(record['sent_at']);
    final expiresAt = _parseDate(record['expires_at']);
    final request = record[requestField];
    String? requestId;
    String? requiredState;
    String? target;
    String? orgName;
    String? requesterName;

    if (request is Map) {
      requestId = request['id']?.toString();
      requiredState = request['required_state']?.toString();
      target = request['target']?.toString() ?? request['Target']?.toString();

      final org = request['requested_by_org'];
      if (org is Map && org['name'] != null) {
        orgName = org['name']?.toString();
      }
      final requester = request['requested_by_user'];
      if (requester is Map) {
        requesterName = _formatUserName(
          requester['first_name'],
          requester['last_name'],
          requester['email'],
        );
      }
    } else if (request != null) {
      requestId = request.toString();
    }

    if (orgName == null || orgName.trim().isEmpty) {
      final businessProfile = record['business_profile'];
      if (businessProfile is Map) {
        orgName =
            businessProfile['business_name']?.toString() ??
            businessProfile['company_name']?.toString();
      }
    }
    if (requesterName == null || requesterName.trim().isEmpty) {
      final requester = record['requested_by_user'];
      if (requester is Map) {
        requesterName = _formatUserName(
          requester['first_name'],
          requester['last_name'],
          requester['email'],
        );
      }
    }

    return InviteDetails(
      inviteId: inviteId,
      token: token,
      status: status,
      requestId: requestId,
      orgName: orgName,
      requesterName: requesterName,
      requiredState: requiredState,
      target: target,
      email: email,
      phone: phone,
      sentAt: sentAt,
      expiresAt: expiresAt,
    );
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  String? _formatUserName(dynamic first, dynamic last, dynamic email) {
    final firstName = first?.toString().trim();
    final lastName = last?.toString().trim();
    final parts = <String>[];
    if (firstName != null && firstName.isNotEmpty) {
      parts.add(firstName);
    }
    if (lastName != null && lastName.isNotEmpty) {
      parts.add(lastName);
    }
    if (parts.isNotEmpty) return parts.join(' ');
    final fallback = email?.toString().trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return null;
  }
}

class InviteClaimResult {
  final String inviteId;
  final String requestId;

  const InviteClaimResult({required this.inviteId, required this.requestId});
}

class _InviteFieldAttempt {
  final String requestField;
  final bool includeExtended;

  const _InviteFieldAttempt({
    required this.requestField,
    required this.includeExtended,
  });
}
