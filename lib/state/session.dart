import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Session {
  Session._();

  static final Session instance = Session._();
  static const _storage = FlutterSecureStorage();
  static const Object _preserve = Object();

  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kUserId = 'user_id';
  static const _kUserEmail = 'user_email';
  static const _kUserName = 'user_name';
  static const _kRoleName = 'role_name';
  static const _kPendingInviteToken = 'pending_invite_token';

  String? accessToken;
  String? refreshToken;
  String? userId;
  String? userEmail;
  String? userName;
  String? roleName;
  String? pendingInviteToken;

  bool get isLoggedIn => accessToken != null && accessToken!.isNotEmpty;

  static Future<void> init() async {
    final s = instance;
    s.accessToken = await _storage.read(key: _kAccessToken);
    s.refreshToken = await _storage.read(key: _kRefreshToken);
    s.userId = await _storage.read(key: _kUserId);
    s.userEmail = await _storage.read(key: _kUserEmail);
    s.userName = await _storage.read(key: _kUserName);
    s.roleName = await _storage.read(key: _kRoleName);
    s.pendingInviteToken = await _storage.read(key: _kPendingInviteToken);
  }

  Future<void> setAuth({
    required String accessToken,
    Object? refreshToken = _preserve,
    Object? userId = _preserve,
    Object? userEmail = _preserve,
    Object? userName = _preserve,
    Object? roleName = _preserve,
  }) async {
    final normalizedAccessToken = accessToken.trim();
    final nextRefreshToken = _resolveUpdatedString(
      currentValue: this.refreshToken,
      update: refreshToken,
    );
    final nextUserId = _resolveUpdatedString(
      currentValue: this.userId,
      update: userId,
    );
    final nextUserEmail = _resolveUpdatedString(
      currentValue: this.userEmail,
      update: userEmail,
    );
    final nextUserName = _resolveUpdatedString(
      currentValue: this.userName,
      update: userName,
    );
    final nextRoleName = _resolveUpdatedString(
      currentValue: this.roleName,
      update: roleName,
    );

    this.accessToken = normalizedAccessToken;
    this.refreshToken = nextRefreshToken;
    this.userId = nextUserId;
    this.userEmail = nextUserEmail;
    this.userName = nextUserName;
    this.roleName = nextRoleName;

    await _storage.write(key: _kAccessToken, value: normalizedAccessToken);
    await _persistOptionalString(_kRefreshToken, nextRefreshToken);
    await _persistOptionalString(_kUserId, nextUserId);
    await _persistOptionalString(_kUserEmail, nextUserEmail);
    await _persistOptionalString(_kUserName, nextUserName);
    await _persistOptionalString(_kRoleName, nextRoleName);
  }

  Future<void> setPendingInviteToken(String? token) async {
    pendingInviteToken = token;
    if (token == null || token.trim().isEmpty) {
      await _storage.delete(key: _kPendingInviteToken);
      return;
    }
    await _storage.write(key: _kPendingInviteToken, value: token.trim());
  }

  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    userId = null;
    userEmail = null;
    userName = null;
    roleName = null;
    pendingInviteToken = null;
    await Future.wait([
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
      _storage.delete(key: _kUserId),
      _storage.delete(key: _kUserEmail),
      _storage.delete(key: _kUserName),
      _storage.delete(key: _kRoleName),
      _storage.delete(key: _kPendingInviteToken),
    ]);
  }

  bool get isAdmin {
    final name = roleName?.toLowerCase() ?? '';
    return name.contains('admin') || name.contains('manager');
  }

  String? _resolveUpdatedString({
    required String? currentValue,
    required Object? update,
  }) {
    if (identical(update, _preserve)) {
      return currentValue;
    }
    if (update == null) {
      return null;
    }
    final normalized = update.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _persistOptionalString(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
      return;
    }
    await _storage.write(key: key, value: value);
  }
}
