import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import 'access_tab.dart';
import 'setup_kit.dart';
import 'staff_attendance_tab.dart';
import 'user_sheets.dart';

/// Users & access (web UsersPage.jsx): Team, Access and (with Leave & Attendance on) Attendance tabs.
/// [initialTab] takes the web's `?tab=` keys: `team`, `access`, `attendance`. Anything else (e.g. `leave`,
/// which the web no longer has) opens Team, as the web does.
class UsersScreen extends StatefulWidget {
  final String? initialTab;
  const UsersScreen({super.key, this.initialTab});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

const _statuses = ['Invited', 'Active', 'Disabled'];

class _UsersScreenState extends State<UsersScreen> {
  List<String>? _tenantAllowed;
  int _usersVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadAllowance();
  }

  Future<void> _loadAllowance() async {
    try {
      final r = await context.read<ApiClient>().get('/users/allowed-modules') as Map;
      if (mounted) setState(() => _tenantAllowed = (r['modules'] as List? ?? const []).map((e) => e.toString()).toList());
    } catch (_) {
      if (mounted) setState(() => _tenantAllowed = const []);
    }
  }

  /// Any user write: reload every user list (web invalidates ["allUsers"]).
  void _usersChanged() => setState(() => _usersVersion++);

  Future<void> _addUser() async {
    if (await showUserForm(context)) _usersChanged();
  }

  Future<void> _roleAccess() async {
    if (await showBulkModules(context, _tenantAllowed ?? const [])) _usersChanged();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthProvider>().user;
    final hrOn = me?.hasModule('leave_attendance') ?? false;
    final tabs = ['team', 'access', if (hrOn) 'attendance'];
    final labels = {'team': 'Team', 'access': 'Access', 'attendance': 'Attendance'};
    final initial = tabs.indexOf(widget.initialTab ?? 'team');
    final allowed = _tenantAllowed ?? const <String>[];

    return DefaultTabController(
      key: ValueKey(tabs.length),
      length: tabs.length,
      initialIndex: initial < 0 ? 0 : initial,
      child: Scaffold(
        floatingActionButton:
            FloatingActionButton.extended(onPressed: _addUser, icon: const Icon(Icons.person_add_alt), label: const Text('Add User')),
        body: Column(children: [
          Material(
            color: context.pal.card,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final t in tabs) Tab(text: labels[t])],
            ),
          ),
          Expanded(
            child: TabBarView(children: [
              _TeamTab(
                version: _usersVersion,
                tenantAllowed: allowed,
                onChanged: _usersChanged,
                onRoleAccess: _roleAccess,
              ),
              AccessTab(tenantAllowed: allowed, onRoleAccess: _roleAccess, refreshKey: '$_usersVersion|${allowed.length}'),
              if (hrOn) const StaffAttendanceTab(),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _TeamTab extends StatefulWidget {
  final int version;
  final List<String> tenantAllowed;
  final VoidCallback onChanged;
  final VoidCallback onRoleAccess;
  const _TeamTab({required this.version, required this.tenantAllowed, required this.onChanged, required this.onRoleAccess});

  @override
  State<_TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends State<_TeamTab> with AutomaticKeepAliveClientMixin {
  String _role = 'all';
  String _status = 'all';

  @override
  bool get wantKeepAlive => true;

  ApiClient get _api => context.read<ApiClient>();

  Future<void> _run(Future<void> Function() fn, String ok, Map<String, dynamic> u) async {
    final done = await runAction(context, fn, success: ok);
    if (!done || !mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.user?.id == u['id']) auth.refreshUser();
    widget.onChanged();
  }

  Future<void> _resetPassword(Map<String, dynamic> u) async {
    final pw = await promptText(context,
        title: 'New password for ${u['name']} (min 6 chars):', label: 'New password', maxLines: 1, confirmLabel: 'Reset');
    if (pw == null || pw.isEmpty || !mounted) return;
    if (pw.length < 6) {
      showToast(context, 'Password must be at least 6 characters', error: true);
      return;
    }
    _run(() => _api.post('/users/${u['id']}/reset-password', data: {'new_password': pw}), 'Password reset', u);
  }

  Future<void> _delete(Map<String, dynamic> u) async {
    if (!await confirmDialog(context,
        title: 'Delete ${u['name']}? This cannot be undone.', confirmLabel: 'Delete', destructive: true)) {
      return;
    }
    if (!mounted) return;
    _run(() => _api.delete('/users/${u['id']}'), 'User deleted', u);
  }

  String _modulesLabel(Map<String, dynamic> u) {
    final n = widget.tenantAllowed.length;
    final a = (u['allowed_modules'] as List? ?? const []);
    if (a.isNotEmpty) return '${a.length}/$n';
    return u['role'] == 'Admin' ? 'Full' : 'All $n';
  }

  Future<void> _actions(Map<String, dynamic> u) async {
    final disabled = u['status'] == 'Disabled';
    final assignable = ['ProjectManager', 'SiteEngineer', 'ProcurementOfficer'].contains(u['role']);
    final p = context.pal;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text((u['name'] ?? '').toString(), style: Theme.of(ctx).textTheme.titleMedium),
            subtitle: Text((u['email'] ?? '').toString()),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Modules'),
            trailing: Text(_modulesLabel(u), style: tabular(Theme.of(ctx).textTheme.bodyMedium)),
            onTap: () => Navigator.pop(ctx, 'modules'),
          ),
          if (assignable)
            ListTile(
                leading: const Icon(Icons.engineering_outlined),
                title: const Text('Assign to project'),
                onTap: () => Navigator.pop(ctx, 'assign')),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit'), onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('Reset password'),
              onTap: () => Navigator.pop(ctx, 'reset')),
          if (!disabled)
            ListTile(
                leading: Icon(Icons.person_off_outlined, color: p.danger),
                title: Text('Disable', style: TextStyle(color: p.danger)),
                onTap: () => Navigator.pop(ctx, 'disable'))
          else
            ListTile(
                leading: Icon(Icons.person_outline, color: p.success),
                title: Text('Enable', style: TextStyle(color: p.success)),
                onTap: () => Navigator.pop(ctx, 'enable')),
          ListTile(
              leading: Icon(Icons.delete_outline, color: p.danger),
              title: Text('Delete', style: TextStyle(color: p.danger)),
              onTap: () => Navigator.pop(ctx, 'delete')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'modules':
        if (await showUserModules(context, u, widget.tenantAllowed) && mounted) {
          final auth = context.read<AuthProvider>();
          if (auth.user?.id == u['id']) auth.refreshUser();
          widget.onChanged();
        }
      case 'assign':
        await showAssignProject(context, u);
      case 'edit':
        if (await showUserForm(context, user: u) && mounted) {
          final auth = context.read<AuthProvider>();
          if (auth.user?.id == u['id']) auth.refreshUser();
          widget.onChanged();
        }
      case 'reset':
        await _resetPassword(u);
      case 'disable':
        await _run(() => _api.post('/users/${u['id']}/disable'), '${u['name']} disabled', u);
      case 'enable':
        await _run(() => _api.patch('/users/${u['id']}', data: {'status': 'Active'}), '${u['name']} enabled', u);
      case 'delete':
        await _delete(u);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tt = Theme.of(context).textTheme;
    return AsyncView<List<Map<String, dynamic>>>(
      depKey: '$_role|$_status|${widget.version}',
      load: () async => asMaps(await _api.get('/users/all', params: {
            'role': _role == 'all' ? null : _role,
            'status': _status == 'all' ? null : _status,
          })),
      builder: (context, users, reload) => RefreshList(
        onRefresh: reload,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: AppDropdown<String>(
                    label: 'Role',
                    value: _role,
                    items: [('all', 'All Roles'), for (final r in userRoles) (r, roleWords(r))],
                    onChanged: (v) => setState(() => _role = v ?? 'all'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppDropdown<String>(
                    label: 'Status',
                    value: _status,
                    items: [('all', 'All Statuses'), for (final s in _statuses) (s, s)],
                    onChanged: (v) => setState(() => _status = v ?? 'all'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: widget.onRoleAccess,
                  icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                  label: const Text('Role access'),
                ),
              ),
            ]),
          ),
          if (users.isEmpty)
            const EmptyState(icon: Icons.person_search_outlined, title: 'No users match the filters.')
          else
            RowGroup(children: [
              for (final u in users)
                RowTile(
                  onTap: () => _actions(u),
                  title: (u['name'] ?? '').toString(),
                  subtitleWidget: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((u['email'] ?? '').toString(), style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      'Modules ${_modulesLabel(u)} · Last login ${fmtDate(u['last_login_at'], empty: 'Never')}',
                      style: tabular(tt.bodySmall),
                    ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      RoleBadge(u['role']?.toString()),
                      StatusChip(u['status']?.toString(),
                          dense: true, tone: u['status'] == 'Invited' ? Tone.warning : null),
                    ]),
                  ]),
                  trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    Text(toNum(u['base_salary']) == 0 ? '—' : inr(u['base_salary']), style: tabular(tt.titleSmall)),
                    Text('base salary', style: tt.bodySmall),
                  ]),
                ),
            ]),
        ],
      ),
    );
  }
}
