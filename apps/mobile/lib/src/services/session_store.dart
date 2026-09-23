import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_models.dart';

class SessionStore {
  const SessionStore(this._storage);

  static const _accessToken = 'access_token';
  static const _refreshToken = 'refresh_token';
  static const _userId = 'user_id';
  static const _expiresAt = 'access_token_expires_at';

  final FlutterSecureStorage _storage;

  Future<void> save(AuthSession session) async {
    await _storage.write(key: _accessToken, value: session.accessToken);
    await _storage.write(key: _refreshToken, value: session.refreshToken);
    await _storage.write(key: _userId, value: session.userId);
    await _storage.write(key: _expiresAt, value: session.accessTokenExpiresAt.toIso8601String());
  }

  Future<AuthSession?> read() async {
    final values = await _storage.readAll();
    final access = values[_accessToken];
    final refresh = values[_refreshToken];
    final userId = values[_userId];
    final expiresAt = values[_expiresAt];
    if (access == null || refresh == null || userId == null || expiresAt == null) return null;
    final parsedExpiry = DateTime.tryParse(expiresAt);
    if (parsedExpiry == null) return null;
    return AuthSession(userId: userId, accessToken: access, refreshToken: refresh, accessTokenExpiresAt: parsedExpiry);
  }

  Future<void> clear() => _storage.deleteAll();
}
