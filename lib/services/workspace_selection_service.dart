import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'organization_service.dart';

class WorkspaceSelectionDecision {
  final WorkspaceMembershipChoice? selection;
  final bool requiresPicker;
  final List<WorkspaceMembershipChoice> memberships;

  const WorkspaceSelectionDecision({
    required this.selection,
    required this.requiresPicker,
    required this.memberships,
  });
}

class WorkspaceSelectionPolicy {
  static List<WorkspaceMembershipChoice> eligibleMemberships(
    Iterable<WorkspaceMembershipChoice> memberships,
  ) {
    return memberships
        .where((membership) {
          final status = membership.status.trim().toLowerCase();
          final role = membership.memberRole.trim().toLowerCase();
          return membership.membershipId.trim().isNotEmpty &&
              membership.businessProfileId.trim().isNotEmpty &&
              (status == 'active' || status == 'accepted') &&
              const {
                'owner',
                'hr',
                'manager',
                'manger',
                'employee',
              }.contains(role);
        })
        .toList(growable: false);
  }

  static WorkspaceSelectionDecision decide({
    required Iterable<WorkspaceMembershipChoice> memberships,
    required String? storedMembershipId,
  }) {
    final eligible = eligibleMemberships(memberships);
    if (eligible.length == 1) {
      return WorkspaceSelectionDecision(
        selection: eligible.single,
        requiresPicker: false,
        memberships: eligible,
      );
    }
    final savedId = storedMembershipId?.trim() ?? '';
    for (final membership in eligible) {
      if (savedId.isNotEmpty && membership.membershipId == savedId) {
        return WorkspaceSelectionDecision(
          selection: membership,
          requiresPicker: false,
          memberships: eligible,
        );
      }
    }
    return WorkspaceSelectionDecision(
      selection: null,
      requiresPicker: eligible.length > 1,
      memberships: eligible,
    );
  }
}

class WorkspaceSelectionStore {
  WorkspaceSelectionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static final WorkspaceSelectionStore instance = WorkspaceSelectionStore();
  static const _keyPrefix = 'last_workspace_membership_';

  final FlutterSecureStorage _storage;

  String _keyForUser(String userId) => '$_keyPrefix${userId.trim()}';

  Future<String?> read(String userId) async {
    if (userId.trim().isEmpty) return null;
    return _storage.read(key: _keyForUser(userId));
  }

  Future<void> save({
    required String userId,
    required String membershipId,
  }) async {
    if (userId.trim().isEmpty || membershipId.trim().isEmpty) return;
    await _storage.write(key: _keyForUser(userId), value: membershipId.trim());
  }

  Future<void> clearForUser(String userId) async {
    if (userId.trim().isEmpty) return;
    await _storage.delete(key: _keyForUser(userId));
  }
}
