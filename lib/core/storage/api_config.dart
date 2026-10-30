import 'package:shared_preferences/shared_preferences.dart';

/// The backend base URL, the app's equivalent of the web's REACT_APP_BACKEND_URL. ApiClient adds `/api`.
/// Defaults to the production server; editable from the login screen's "Server settings".
class ApiConfig {
  static const _key = 'oyster_backend_url';
  static const defaultUrl = 'https://oyesterhomes.sparkcurv.com';
  static String? _cached;

  static Future<String> getBaseUrl() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    return _cached = prefs.getString(_key) ?? defaultUrl;
  }

  /// Last known base URL without waiting (the default until the first read).
  static String get baseUrlSync => _cached ?? defaultUrl;

  /// Turns a server-relative path (`/api/uploads/x.pdf`) into a full URL; full URLs pass through.
  static String fileUrl(String path) => path.startsWith('http') ? path : '$baseUrlSync$path';

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    _cached = url.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(_key, _cached!);
  }
}
