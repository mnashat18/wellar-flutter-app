import '../models/request_item.dart';
import 'request_service.dart';

class ManagerRequestService {
  ManagerRequestService._();

  static final ManagerRequestService instance = ManagerRequestService._();

  void clearOrganizationScopedCaches() {
    RequestService.instance.clearScanRequestFieldSupportCache();
  }

  Future<List<RequestItem>> fetchTeamRequests({String? statusFilter}) {
    return RequestService.instance.fetchManagerRequests(
      statusFilter: statusFilter,
    );
  }
}
