import 'package:flutter_test/flutter_test.dart';
import 'package:waller_app/services/organization_service.dart';
import 'package:waller_app/services/workspace_selection_service.dart';

void main() {
  final owner = _membership(
    id: 'membership-owner',
    businessProfileId: 'workspace-owner',
    role: 'owner',
    company: 'Owner Company',
  );
  final manager = _membership(
    id: 'membership-manager',
    businessProfileId: 'workspace-manager',
    role: 'manager',
    company: 'Manager Company',
  );

  test('single membership enters directly without picker', () {
    final decision = WorkspaceSelectionPolicy.decide(
      memberships: [owner],
      storedMembershipId: null,
    );

    expect(decision.selection, owner);
    expect(decision.requiresPicker, isFalse);
  });

  test('multiple memberships use a valid stored workspace choice', () {
    final decision = WorkspaceSelectionPolicy.decide(
      memberships: [owner, manager],
      storedMembershipId: manager.membershipId,
    );

    expect(decision.selection, manager);
    expect(decision.requiresPicker, isFalse);
  });

  test('multiple memberships without a stored choice require picker', () {
    final decision = WorkspaceSelectionPolicy.decide(
      memberships: [owner, manager],
      storedMembershipId: null,
    );

    expect(decision.selection, isNull);
    expect(decision.requiresPicker, isTrue);
  });

  test('stale stored choice requires picker', () {
    final decision = WorkspaceSelectionPolicy.decide(
      memberships: [owner, manager],
      storedMembershipId: 'removed-membership',
    );

    expect(decision.selection, isNull);
    expect(decision.requiresPicker, isTrue);
  });
}

WorkspaceMembershipChoice _membership({
  required String id,
  required String businessProfileId,
  required String role,
  required String company,
}) {
  return WorkspaceMembershipChoice(
    membershipId: id,
    businessProfileId: businessProfileId,
    companyName: company,
    memberRole: role,
    departmentId: null,
    departmentName: null,
    businessProfileStatus: 'true',
    businessPlanCode: null,
    businessBillingStatus: null,
    status: 'active',
    isCurrent: false,
  );
}
