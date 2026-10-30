/// The signed-in user, as returned by `user_out()` (POST /auth/login, GET /auth/me).
class AppUser {
  final int id;
  final String email;
  final String name;
  final String role;
  final int? clientId;
  final int? tenantId;
  final int? linkedVendorId;
  final String status;

  /// null = unrestricted (SuperAdmin), [] = locked out, otherwise only these module keys.
  final List<String>? effectiveModules;
  final String? tenantLogoUrl;
  final String? tenantName;
  final Map<String, dynamic> raw;

  AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.clientId,
    this.tenantId,
    this.linkedVendorId,
    this.status = 'Active',
    this.effectiveModules,
    this.tenantLogoUrl,
    this.tenantName,
    this.raw = const {},
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as int,
        email: (j['email'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        role: (j['role'] ?? '') as String,
        clientId: j['client_id'] as int?,
        tenantId: j['tenant_id'] as int?,
        linkedVendorId: j['linked_vendor_id'] as int?,
        status: (j['status'] ?? 'Active') as String,
        effectiveModules: (j['effective_modules'] as List?)?.map((e) => e.toString()).toList(),
        tenantLogoUrl: j['tenant_logo_url'] as String?,
        tenantName: j['tenant_name'] as String?,
        raw: j,
      );

  /// Staff roles, as `STAFF` in the web Layout.jsx.
  static const staffRoles = ['Admin', 'ProjectManager', 'SiteEngineer', 'Accountant', 'ProcurementOfficer'];

  /// Display names, as `ROLE_LABELS` in the web Layout.jsx.
  static const roleLabels = {
    'Admin': 'Admin',
    'ProjectManager': 'Project Manager',
    'SiteEngineer': 'Site Engineer',
    'Accountant': 'Accounts',
    'ProcurementOfficer': 'Purchase Manager',
    'Client': 'Client',
    'Vendor': 'Vendor',
    'SuperAdmin': 'Super Admin',
  };

  String get roleLabel => roleLabels[role] ?? role;

  bool get isSuperAdmin => role == 'SuperAdmin';
  bool get isAdmin => role == 'Admin';
  bool get isStaff => staffRoles.contains(role);
  bool get isClient => role == 'Client';
  bool get isVendor => role == 'Vendor';

  /// `require_roles(...)` semantics: SuperAdmin passes everything; ProjectManager passes wherever
  /// SiteEngineer is allowed (backend core/security.py).
  bool hasRole(List<String> roles) =>
      isSuperAdmin || roles.contains(role) || (role == 'ProjectManager' && roles.contains('SiteEngineer'));

  /// Exact role-list check, as the web's `roles.includes(user.role)` (no SuperAdmin / PM widening).
  bool roleIn(List<String> roles) => roles.contains(role);

  /// Module gate, as the web's `effective == null || effective.includes(module)`. A null module is always on.
  bool hasModule(String? module) => module == null || effectiveModules == null || effectiveModules!.contains(module);

  /// The web AuthContext's `canWrite`: Admin, ProjectManager or SiteEngineer.
  bool get canWrite => ['Admin', 'ProjectManager', 'SiteEngineer'].contains(role);
}
