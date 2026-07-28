import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/request_item.dart';
import 'directus_client.dart';
import 'member_identity_service.dart';
import 'organization_service.dart';
import 'request_service.dart';
import '../state/session.dart';

class RequestMemberOption {
  final String memberId;
  final String userId;
  final String name;
  final String email;
  final String? departmentId;
  final String? departmentName;
  final String role;
  final String status;

  const RequestMemberOption({
    required this.memberId,
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.departmentId,
    this.departmentName,
  });
}

class AdminRequestService {
  AdminRequestService._();

  static final AdminRequestService instance = AdminRequestService._();

  Dio get _client => DirectusClient.instance.client;

  Future<List<RequestItem>> fetchWorkspaceRequests({
    String? statusFilter,
  }) async {
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final session = Session.instance;
    final effectiveRole =
        workspace?.finalEffectiveRole.trim().toLowerCase() ?? '';
    final membershipRole = workspace?.memberRole.trim().toLowerCase() ?? '';
    final directusRole =
        workspace?.directusRoleName?.trim().toLowerCase() ?? '';

    debugPrint(
      '[REQUESTS_PAGE_OPEN] currentUserId=${session.userId} currentUserEmail=${session.userEmail} effectiveRole=$effectiveRole directusRole=${workspace?.directusRoleName} membershipId=${workspace?.membershipId} membershipRole=${workspace?.memberRole} businessProfileId=${workspace?.businessProfileId} departmentId=${workspace?.departmentId}',
    );

    final isOwner =
        effectiveRole == 'owner' ||
        membershipRole == 'owner' ||
        directusRole == 'owner';
    final isHr =
        effectiveRole == 'hr' || membershipRole == 'hr' || directusRole == 'hr';

    if (isOwner) {
      return RequestService.instance.fetchOwnerRequests(
        statusFilter: statusFilter,
      );
    }
    if (isHr) {
      return RequestService.instance.fetchHrRequests(
        statusFilter: statusFilter,
      );
    }
    throw const RequestRoleUnavailableException(
      'This information is not available for your role.',
    );
  }

  Future<List<RequestMemberOption>> fetchWorkspaceMembers() async {
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    if (workspace == null || workspace.businessProfileId.isEmpty) {
      return const [];
    }
    final rows = await MemberIdentityService.instance
        .fetchBusinessProfileMembers(
          screen: 'RequestsForm',
          businessProfileId: workspace.businessProfileId,
          limit: 300,
          activeOnly: true,
        );
    final members = rows
        .map((m) {
          final user = m['user'];
          final dep = m['department'];
          final departmentName = dep is Map ? dep['name']?.toString() : null;
          final identity = MemberIdentityService.instance
              .resolveFromUserRelation(
                user,
                context: 'request_member_selector',
                memberId: m['id']?.toString() ?? '',
                role: m['member_role']?.toString(),
                departmentRaw: dep,
                employeeCode: m['employee_code']?.toString(),
              );
          return RequestMemberOption(
            memberId: m['id']?.toString() ?? '',
            userId: identity.userId,
            name: identity.name,
            email: identity.displayEmail,
            role: m['member_role']?.toString() ?? '',
            status: m['status']?.toString() ?? '',
            departmentId: dep is Map ? dep['id']?.toString() : dep?.toString(),
            departmentName: departmentName?.trim().isNotEmpty == true
                ? departmentName!.trim()
                : identity.departmentName,
          );
        })
        .where(
          (m) =>
              m.memberId.isNotEmpty &&
              m.userId.isNotEmpty &&
              m.status.trim().toLowerCase() == 'active' &&
              m.role.trim().toLowerCase() != 'owner',
        )
        .toList();
    members.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) return byName;
      return a.email.toLowerCase().compareTo(b.email.toLowerCase());
    });
    return members;
  }

  Future<void> createPersonalRequest({
    required String targetMemberId,
    DateTime? dueAt,
  }) async {
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    if (workspace == null) {
      throw const RequestCreateException(
        'Request could not be created. Please check workspace permissions.',
      );
    }
    if (targetMemberId.trim().isEmpty) {
      throw const RequestCreateException(
        'Select a valid member before sending the request.',
      );
    }
    await RequestService.instance.createPersonalScanRequest(
      businessProfileId: workspace.businessProfileId,
      targetMemberId: targetMemberId,
      dueAt: dueAt,
    );
  }
}
