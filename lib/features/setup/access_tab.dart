import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import 'setup_kit.dart';

// Users × modules (web AccessMatrixTab.jsx). The web grid is too wide for a phone, so each person is a row
// and tapping it opens their module switches; every switch saves straight away, as the matrix checkboxes do.
//
// A user's `allowed_modules` of [] / null means "everything the company has", so a full set is saved as []
// and an empty set is refused (it would read as "everything").

const _matrixRoles = ['ProjectManager', 'SiteEngineer', 'Admin'];

List<String> _has(Map<String, dynamic> u, List<String> tenantAllowed) {
  final a = (u['allowed_modules'] as List? ?? const []).map((e) => e.toString()).toList();
  return a.isNotEmpty ? a : tenantAllowed;
}

class AccessTab extends StatelessWidget {
  final List<String> tenantAllowed;
  final VoidCallback onRoleAccess;
  final Object? refreshKey;
  const AccessTab({super.key, required this.tenantAllowed, required this.onRoleAccess, this.refreshKey});

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final tt = Theme.of(context).textTheme;
    return AsyncView<List<Map<String, dynamic>>>(
      depKey: refreshKey,
      load: () async => asMaps(await api.get('/users/all')),
      builder: (context, users, reload) {
        final rows =
            users.where((u) => _matrixRoles.contains(u['role']) && u['status'] != 'Disabled').toList();
        return RefreshList(
          onRefresh: reload,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  'Tick what each person can open. Changes save straight away and apply at their next page load. '
                  'Admins always see everything.',
                  style: tt.bodySmall,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onRoleAccess,
                  icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                  label: const Text('Role access'),
                ),
              ]),
            ),
            if (tenantAllowed.isEmpty)
              const EmptyState(icon: Icons.lock_outline, title: 'No modules are switched on for this company.')
            else if (rows.isEmpty)
              const EmptyState(icon: Icons.group_outlined, title: 'No users yet.')
            else
              RowGroup(children: [
                for (final u in rows)
                  RowTile(
                    chevron: true,
                    title: (u['name'] ?? '').toString(),
                    subtitleWidget: Align(alignment: Alignment.centerLeft, child: RoleBadge(u['role']?.toString())),
                    trailing: Text(
                      u['role'] == 'Admin'
                          ? 'All ${tenantAllowed.length}'
                          : '${_has(u, tenantAllowed).where(tenantAllowed.contains).length}/${tenantAllowed.length}',
                      style: tabular(tt.titleSmall),
                    ),
                    onTap: () async {
                      await showAppSheet<void>(
                        context,
                        title: (u['name'] ?? '').toString(),
                        subtitle: u['role'] == 'Admin' ? 'Admins always see everything.' : 'Changes save straight away.',
                        builder: (_) => _UserMatrix(user: u, tenantAllowed: tenantAllowed),
                      );
                      reload();
                    },
                  ),
              ]),
          ],
        );
      },
    );
  }
}

class _UserMatrix extends StatefulWidget {
  final Map<String, dynamic> user;
  final List<String> tenantAllowed;
  const _UserMatrix({required this.user, required this.tenantAllowed});

  @override
  State<_UserMatrix> createState() => _UserMatrixState();
}

class _UserMatrixState extends State<_UserMatrix> {
  late Map<String, dynamic> _u = widget.user;
  String? _saving;
  String? _error;

  Future<void> _toggle(String mod) async {
    final current = {..._has(_u, widget.tenantAllowed)};
    current.contains(mod) ? current.remove(mod) : current.add(mod);
    if (current.isEmpty) {
      final msg = '${_u['name']} needs at least one module';
      setState(() => _error = msg);
      showToast(context, msg, error: true);
      return;
    }
    final full = widget.tenantAllowed.every(current.contains);
    setState(() {
      _saving = mod;
      _error = null;
    });
    try {
      final r = await context.read<ApiClient>().patch('/users/${_u['id']}', data: {
        'allowed_modules': full ? <String>[] : [for (final m in widget.tenantAllowed) if (current.contains(m)) m],
      });
      if (!mounted) return;
      setState(() => _u = Map<String, dynamic>.from(r as Map));
      final auth = context.read<AuthProvider>();
      if (auth.user?.id == _u['id']) auth.refreshUser();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorText(e));
      showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _u['role'] == 'Admin';
    final set = _has(_u, widget.tenantAllowed).toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(alignment: Alignment.centerLeft, child: RoleBadge(_u['role']?.toString())),
      const SizedBox(height: 8),
      SheetError(_error),
      for (final m in widget.tenantAllowed)
        SwitchRow(
          label: moduleLabel(m),
          value: locked || set.contains(m),
          onChanged: locked || _saving != null ? null : (_) => _toggle(m),
        ),
    ]);
  }
}
