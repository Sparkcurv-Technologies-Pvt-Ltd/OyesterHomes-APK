import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the bearer token across restarts. The backend has no refresh endpoint, so a missing
/// or expired token just means "sign in again".
class TokenStorage {
  static const _key = 'oyster_access_token';
  final _storage = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  Future<String?> read() => _storage.read(key: _key);
  Future<void> save(String token) => _storage.write(key: _key, value: token);
  Future<void> clear() => _storage.delete(key: _key);
}
