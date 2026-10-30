import 'package:flutter/material.dart';
import '../auth/user.dart';
import '../boq/boq_library_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../finance/finance_screen.dart';
import '../finance/payroll_screen.dart';
import '../finance/petty_cash_screen.dart';
import '../inventory/inventory_screen.dart';
import '../labour/labour_attendance_screen.dart';
import '../procurement/vendors_screen.dart';
import '../projects/project_list_screen.dart';
import '../setup/clients_screen.dart';
import '../setup/companies_screen.dart';
import '../setup/company_settings_screen.dart';
import '../setup/users_screen.dart';

const _staff = AppUser.staffRoles;

/// One top-level page. Same roles and module keys as the web's GEARS in Layout.jsx.
class NavPage {
  final String path;
  final String label;
  final IconData icon;
  final List<String> roles;
  final String? module;
  final Widget Function(String? initialTab) builder;
  const NavPage(this.path, this.label, this.icon, this.roles, this.module, this.builder);
}

class NavGear {
  final String key;
  final String label;
  final List<NavPage> pages;
  const NavGear(this.key, this.label, this.pages);
}

/// The workflow as gears, in order (web Layout.jsx GEARS). N = the dashboard.
final gears = <NavGear>[
  NavGear('N', 'Dashboard', [
    NavPage('/admin', 'Dashboard', Icons.space_dashboard_outlined, _staff, null, (_) => const DashboardScreen()),
  ]),
  NavGear('1', 'Setup', [
    NavPage('/admin/companies', 'Companies & branches', Icons.domain_outlined, ['Admin'], null, (_) => const CompaniesScreen()),
    NavPage('/admin/setup/boq-library', 'BOQ library', Icons.library_books_outlined, ['Admin', 'ProjectManager'], 'projects',
        (_) => const BoqLibraryScreen()),
    NavPage('/admin/users', 'Users & access', Icons.manage_accounts_outlined, ['Admin'], null, (t) => UsersScreen(initialTab: t)),
    NavPage('/admin/clients', 'Clients', Icons.people_outline, ['Admin', 'ProjectManager', 'SiteEngineer', 'Accountant'], 'clients',
        (_) => const ClientsScreen()),
    NavPage('/admin/company', 'Company settings', Icons.tune_outlined, ['Admin'], null, (_) => const CompanySettingsScreen()),
  ]),
  NavGear('2', 'Projects & BOQ', [
    NavPage('/admin/projects', 'Projects', Icons.apartment_outlined, _staff, 'projects', (_) => const ProjectListScreen()),
  ]),
  NavGear('3', 'Site', [
    NavPage('/portal/site-engineer', 'Labour attendance', Icons.engineering_outlined, ['Admin', 'ProjectManager', 'SiteEngineer'],
        'field_ops', (_) => const LabourAttendanceScreen()),
  ]),
  NavGear('4', 'Purchase', [
    NavPage('/admin/procurement/vendors', 'Vendors', Icons.storefront_outlined,
        ['Admin', 'ProjectManager', 'SiteEngineer', 'ProcurementOfficer'], 'procurement', (_) => const VendorsScreen()),
  ]),
  NavGear('5', 'Stock', [
    NavPage('/admin/inventory', 'Inventory', Icons.inventory_2_outlined, _staff, 'inventory', (t) => InventoryScreen(initialTab: t)),
  ]),
  NavGear('6', 'Money', [
    NavPage('/admin/finance', 'Finance', Icons.account_balance_wallet_outlined, ['Admin', 'Accountant'], 'finance',
        (_) => const FinanceScreen()),
    NavPage('/admin/finance/payroll', 'Payroll', Icons.payments_outlined, ['Admin', 'Accountant'], 'finance',
        (_) => const PayrollScreen()),
    NavPage('/admin/petty-cash', 'Petty cash', Icons.wallet_outlined, ['Admin', 'ProjectManager', 'SiteEngineer'], null,
        (_) => const PettyCashScreen()),
  ]),
];

/// The gears and pages this user can open: role in the list AND module switched on (web `useGears`).
List<NavGear> gearsFor(AppUser? user) {
  if (user == null) return const [];
  bool ok(NavPage p) => user.roleIn(p.roles) && user.hasModule(p.module);
  return [
    for (final g in gears)
      if (g.pages.any(ok)) NavGear(g.key, g.label, g.pages.where(ok).toList()),
  ];
}

/// Bottom-bar destinations: the dashboard plus the first gears that matter most on site,
/// up to five (Material 3 limit). Everything else lives in the drawer, grouped by gear.
List<NavPage> bottomPagesFor(AppUser? user) {
  final pages = {for (final g in gearsFor(user)) for (final p in g.pages) p.path: p};
  const order = ['/admin', '/admin/projects', '/portal/site-engineer', '/admin/inventory', '/admin/finance', '/admin/procurement/vendors'];
  final out = <NavPage>[for (final path in order) if (pages[path] != null) pages[path]!];
  return out.take(5).toList();
}

/// Short labels for the bottom bar.
const bottomLabels = {
  '/admin': 'Home',
  '/admin/projects': 'Projects',
  '/portal/site-engineer': 'Site',
  '/admin/inventory': 'Stock',
  '/admin/finance': 'Money',
  '/admin/procurement/vendors': 'Purchase',
};

NavPage? pageForPath(String path) {
  for (final g in gears) {
    for (final p in g.pages) {
      if (p.path == path) return p;
    }
  }
  return null;
}
