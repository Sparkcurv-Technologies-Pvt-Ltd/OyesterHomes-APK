import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/token_storage.dart';
import 'user.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Mirrors the web AuthContext: GET /auth/me on launch restores the session; login stores the
/// Bearer token the backend returns as `access_token`.
class AuthProvider extends ChangeNotifier {
  final ApiClient _api;
  final TokenStorage _tokens;

  AuthProvider(this._api, this._tokens) {
    _api.onUnauthorized = _onUnauthorized;
  }

  AuthStatus status = AuthStatus.unknown;
  AppUser? user;

  Future<void> bootstrap() async {
    if (await _tokens.read() == null) {
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }
    try {
      user = AppUser.fromJson(Map<String, dynamic>.from(await _api.get('/auth/me')));
      status = AuthStatus.authenticated;
    } on ApiException catch (e) {
      // Only a rejected token signs the user out; a network failure keeps the session for a retry.
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _tokens.clear();
        status = AuthStatus.unauthenticated;
      } else {
        bootError = e.message;
      }
    }
    notifyListeners();
  }

  /// Set when the session could not be checked because the server was unreachable.
  String? bootError;

  Future<void> retryBoot() async {
    bootError = null;
    status = AuthStatus.unknown;
    notifyListeners();
    await bootstrap();
  }

  /// Throws ApiException with the server's message on failure.
  Future<void> login(String email, String password) async {
    final res = Map<String, dynamic>.from(await _api.post('/auth/login', data: {'email': email, 'password': password}));
    await _tokens.save(res['access_token'] as String);
    user = AppUser.fromJson(Map<String, dynamic>.from(res['user']));
    status = AuthStatus.authenticated;
    notifyListeners();
  }

  /// Re-reads /auth/me (after profile or module changes).
  Future<void> refreshUser() async {
    try {
      user = AppUser.fromJson(Map<String, dynamic>.from(await _api.get('/auth/me')));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {
      // The token is dropped locally either way.
    }
    await _tokens.clear();
    user = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void _onUnauthorized() {
    if (status != AuthStatus.authenticated) return;
    _tokens.clear();
    user = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
