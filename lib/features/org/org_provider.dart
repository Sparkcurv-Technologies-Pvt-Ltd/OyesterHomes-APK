import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/api_client.dart';
import '../auth/user.dart';

/// Which company / branch the user is working in (web CompanyContext). Screens pass [orgParams]
/// (`{company_id}` or `{branch_id}`) to list and dashboard calls, and reload when [orgKey] changes:
///
/// ```dart
/// final org = context.watch<OrgProvider>();
/// AsyncView(depKey: org.orgKey, load: () => api.get('/projects', params: {...org.orgParams}), ...)
/// ```
class OrgProvider extends ChangeNotifier {
  final ApiClient _api;
  OrgProvider(this._api);

  static const _key = 'sitera:org';

  AppUser? _user;
  List<Map<String, dynamic>> companies = [];
  bool loading = false;

  /// Saved selection: companyId is an int, the string "all", or null (never chosen).
  dynamic _savedCompanyId;
  int? _savedBranchId;

  bool get enabled => _user != null && AppUser.staffRoles.contains(_user!.role);

  /// Called by the app when the signed-in user changes.
  Future<void> attach(AppUser? user) async {
    if (user?.id == _user?.id) return;
    _user = user;
    companies = [];
    if (!enabled) {
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = jsonDecode(prefs.getString(_key) ?? '{}') as Map;
      _savedCompanyId = saved['companyId'];
      _savedBranchId = saved['branchId'] as int?;
    } catch (_) {
      _savedCompanyId = null;
      _savedBranchId = null;
    }
    await reload();
  }

  Future<void> reload() async {
    if (!enabled) return;
    loading = true;
    notifyListeners();
    try {
      final data = await _api.get('/org/companies');
      companies = (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      // Keep whatever we had; the switcher simply hides with no companies.
    }
    loading = false;
    notifyListeners();
  }

  /// "All companies" (no filter) is the Admin's default view; others start on their first company.
  bool get allCompanies => _savedCompanyId == 'all' || (_savedCompanyId == null && _user?.role == 'Admin');

  Map<String, dynamic>? get company {
    if (allCompanies || companies.isEmpty) return null;
    return companies.firstWhere((c) => c['id'] == _savedCompanyId, orElse: () => companies.first);
  }

  Map<String, dynamic>? get branch {
    final c = company;
    if (c == null) return null;
    final branches = (c['branches'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map));
    for (final b in branches) {
      if (b['id'] == _savedBranchId) return b;
    }
    return null;
  }

  List<Map<String, dynamic>> branchesOf(Map<String, dynamic> c) =>
      (c['branches'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  /// Query params for the current slice: {} / {company_id} / {branch_id}.
  Map<String, dynamic> get orgParams {
    if (!enabled || company == null) return {};
    final b = branch;
    return b != null ? {'branch_id': b['id']} : {'company_id': company!['id']};
  }

  /// Changes whenever the slice changes; use as an AsyncView depKey.
  String get orgKey {
    final b = branch, c = company;
    return b != null ? 'b${b['id']}' : c != null ? 'c${c['id']}' : 'all';
  }

  /// Short code shown in the switcher chip (web `companyCode`).
  static String codeOf(Map<String, dynamic>? c) {
    if (c == null) return 'ALL';
    final code = (c['code'] as String?)?.trim();
    if (code != null && code.isNotEmpty) return code.toUpperCase().substring(0, code.length.clamp(0, 8));
    final name = (c['name'] ?? '') as String;
    final ini = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase();
    return ini;
  }

  bool get multi => companies.length > 1 || (company != null && branchesOf(company!).length > 1);

  void selectAll() => _save('all', null);
  void selectCompany(int id) => _save(id, null);
  void selectBranch(int companyId, int branchId) => _save(companyId, branchId);

  Future<void> _save(dynamic companyId, int? branchId) async {
    _savedCompanyId = companyId;
    _savedBranchId = branchId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({'companyId': companyId, 'branchId': branchId}));
  }
}
