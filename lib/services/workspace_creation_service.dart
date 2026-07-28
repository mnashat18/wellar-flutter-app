import 'package:dio/dio.dart';

import 'directus_client.dart';

class WorkspaceCreationResponse {
  final int statusCode;
  final dynamic data;

  const WorkspaceCreationResponse({
    required this.statusCode,
    required this.data,
  });
}

class WorkspaceCreationService {
  WorkspaceCreationService._();

  static final WorkspaceCreationService instance =
      WorkspaceCreationService._();

  Dio get _client => DirectusClient.instance.client;

  String? _activeIdempotencyKey;
  Future<WorkspaceCreationResponse>? _activeRequest;

  Future<WorkspaceCreationResponse> createWorkspace({
    required String idempotencyKey,
    required String companyName,
    required String firstName,
    required String lastName,
    required String workEmail,
    required String country,
    String? city,
    String? website,
  }) {
    final normalizedKey = idempotencyKey.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError.value(idempotencyKey, 'idempotencyKey');
    }

    final active = _activeRequest;
    if (active != null && _activeIdempotencyKey == normalizedKey) {
      return active;
    }

    final future = _createWorkspaceInternal(
      idempotencyKey: normalizedKey,
      companyName: companyName,
      firstName: firstName,
      lastName: lastName,
      workEmail: workEmail,
      country: country,
      city: city,
      website: website,
    );
    _activeIdempotencyKey = normalizedKey;
    _activeRequest = future;
    future.whenComplete(() {
      if (identical(_activeRequest, future)) {
        _activeRequest = null;
        _activeIdempotencyKey = null;
      }
    });
    return future;
  }

  Future<WorkspaceCreationResponse> _createWorkspaceInternal({
    required String idempotencyKey,
    required String companyName,
    required String firstName,
    required String lastName,
    required String workEmail,
    required String country,
    String? city,
    String? website,
  }) async {
    final response = await _client.post(
      '/wellar/workspaces/create',
      data: <String, dynamic>{
        'idempotency_key': idempotencyKey,
        'company_name': companyName.trim(),
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'work_email': workEmail.trim().toLowerCase(),
        'country': country.trim(),
        if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
        if (website != null && website.trim().isNotEmpty) 'website': website.trim(),
      },
    );
    return WorkspaceCreationResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }
}
