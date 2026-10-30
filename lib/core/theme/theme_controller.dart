import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// System / Light / Dark, remembered. Dark is the default, as on the web.
class ThemeController extends ChangeNotifier {
  static const _key = 'oyster_theme_mode';
  ThemeMode mode = ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    mode = ThemeMode.values.firstWhere((m) => m.name == prefs.getString(_key), orElse: () => ThemeMode.dark);
    notifyListeners();
  }

  Future<void> set(ThemeMode m) async {
    mode = m;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, m.name);
  }
}
