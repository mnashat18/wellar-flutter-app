import '../models/request_item.dart';
import '../state/session.dart';
import 'request_service.dart';

class EmployeeRequestService {
  EmployeeRequestService._();

  static final EmployeeRequestService instance = EmployeeRequestService._();

  Future<List<RequestItem>> fetchAssignedRequests({String? statusFilter}) {
    final userId = Session.instance.userId?.trim() ?? '';
    return RequestService.instance.fetchIncomingRequests(
      userId: userId,
      statusFilter: statusFilter,
    );
  }
}
