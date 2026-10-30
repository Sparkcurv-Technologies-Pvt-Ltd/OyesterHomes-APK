import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../org/org_provider.dart';
import 'setup_kit.dart';

// Bottom-sheet ports of UserFormModal.jsx, UsersPage's UserModulesModal / BulkModulesModal,
// and ProjectAssignmentPicker.jsx.

/// Oyster Homes uses only these three (web ROLES).
const userRoles = ['Admin', 'ProjectManager', 'SiteEngineer'];
const _staffRoles = ['Admin', 'ProjectManager', 'SiteEngineer', 'Accountant', 'ProcurementOfficer'];
const bulkRoles = ['ProjectManager', 'SiteEngineer'];

// ───────────────────────────────────────────────────────── user form

/// New / edit user. Returns true when saved.
Future<bool> showUserForm(BuildContext context, {Map<String, dynamic>? user}) async {
  final ok = await showAppSheet<bool>(
    context,
    title: user != null ? 'Edit User' : 'New User',
    subtitle: user != null ? 'Update user details and role.' : 'Create an account — extra fields appear based on the selected role.',
    builder: (_) => _UserForm(user: user),
  );
  return ok == true;
}

class _UserForm extends StatefulWidget {
  final Map<String, dynamic>? user;
  const _UserForm({this.user});

  @override
  State<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<_UserForm> {
  late final Map<String, dynamic>? u = widget.user;
  late final _name = TextEditingController(text: (u?['name'] ?? '').toString());
  late final _phone = TextEditingController(text: (u?['phone'] ?? '').toString().replaceAll(RegExp(r'[^\d+]'), ''));
  late final _email = TextEditingController(text: (u?['email'] ?? '').toString());
  final _password = TextEditingController();
  late final _salary = TextEditingController(text: u?['base_salary'] == null ? '' : _plain(u!['base_salary']));
  final _newClient = TextEditingController();
  final _newVendor = TextEditingController();
  late String _role = (u?['role'] ?? 'SiteEngineer').toString();
  late int? _clientId = u?['client_id'] as int?;
  late int? _vendorId = u?['linked_vendor_id'] as int?;
  List<Map<String, dynamic>>? _clients;
  List<Map<String, dynamic>>? _vendors;
  bool _saving = false;
  String? _error;

  static String _plain(dynamic v) {
    final n = num.tryParse(v.toString());
    if (n == null) return v.toString();
    return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  }

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _password, _salary, _newClient, _newVendor]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Clients / vendors load only when the role needs them (web `enabled: form.role === ...`).
  Future<void> _loadLinks() async {
    final api = context.read<ApiClient>();
    try {
      if (_role == 'Client' && _clients == null) {
        final l = asMaps(await api.get('/clients'));
        if (mounted) setState(() => _clients = l);
      }
      if (_role == 'Vendor' && _vendors == null) {
        final l = asMaps(await api.get('/vendors'));
        if (mounted) setState(() => _vendors = l);
      }
    } catch (_) {
      // The dropdown just stays empty.
    }
  }

  void _fail(String msg) {
    setState(() => _error = msg);
    showToast(context, msg, error: true);
  }

  Future<void> _submit() async {
    final editing = u != null;
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty) {
      _fail('Name and email are required');
      return;
    }
    if (!editing && _password.text.length < 6) {
      _fail('Password must be at least 6 characters');
      return;
    }
    if (_phone.text.isNotEmpty && !RegExp(r'^\+?\d{10,15}$').hasMatch(_phone.text)) {
      _fail('Phone must be 10–15 digits');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    // Non-negative only (web nonNegative / cleanAmount).
    final cleaned = _salary.text.replaceAll('-', '');
    final salary = cleaned.isNotEmpty ? num.tryParse(cleaned) : null;
    try {
      if (editing) {
        await api.patch('/users/${u!['id']}', data: {
          'name': _name.text.trim(),
          'phone': orNull(_phone.text),
          'role': _role,
          'base_salary': salary,
          'linked_client_id': _role == 'Client' ? _clientId : null,
          'linked_vendor_id': _role == 'Vendor' ? _vendorId : null,
        });
      } else {
        await api.post('/users', data: {
          'name': _name.text.trim(),
          'email': _email.text.trim(),
          'phone': orNull(_phone.text),
          'password': _password.text,
          'role': _role,
          'base_salary': _staffRoles.contains(_role) ? salary : null,
          'linked_client_id': _role == 'Client' ? _clientId : null,
          'new_client_name': _role == 'Client' && _clientId == null ? orNull(_newClient.text) : null,
          'linked_vendor_id': _role == 'Vendor' ? _vendorId : null,
          'new_vendor_name': _role == 'Vendor' && _vendorId == null ? orNull(_newVendor.text) : null,
        });
      }
      if (!mounted) return;
      showToast(context, editing ? 'User updated' : 'User created');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _fail(errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = u != null;
    // An existing user outside the three Oyster roles keeps their role listed so it is not lost.
    final roles = [...userRoles, if (!userRoles.contains(_role)) _role];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTextField(controller: _name, label: 'Name', requiredField: true, capitalization: TextCapitalization.words),
      kFieldGap,
      TextFormField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        inputFormatters: [
          LengthLimitingTextInputFormatter(16),
          TextInputFormatter.withFunction((o, n) {
            final t = n.text.replaceAll(RegExp(r'[^\d+]'), '').replaceAllMapped(RegExp(r'(?!^)\+'), (_) => '');
            return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
          }),
        ],
        decoration: const InputDecoration(labelText: 'Phone'),
      ),
      kFieldGap,
      AppTextField(
          controller: _email,
          label: 'Email',
          requiredField: true,
          enabled: !editing,
          keyboardType: TextInputType.emailAddress,
          capitalization: TextCapitalization.none),
      if (!editing) ...[
        kFieldGap,
        AppTextField(controller: _password, label: 'Password', requiredField: true, obscure: true, capitalization: TextCapitalization.none),
      ],
      kFieldGap,
      AppDropdown<String>(
        label: 'Role',
        requiredField: true,
        value: _role,
        items: [for (final r in roles) (r, roleWords(r))],
        onChanged: (v) {
          if (v == null) return;
          setState(() => _role = v);
          _loadLinks();
        },
      ),
      if (_staffRoles.contains(_role)) ...[
        kFieldGap,
        AppTextField(
          controller: _salary,
          label: 'Base Salary (₹/mo)',
          number: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
      if (_role == 'Client') ...[
        kFieldGap,
        AppDropdown<int>(
          label: 'Link Existing Client',
          hint: 'Select client',
          value: _clientId,
          items: [for (final c in _clients ?? const <Map<String, dynamic>>[]) (c['id'] as int, (c['name'] ?? '').toString())],
          onChanged: (v) => setState(() => _clientId = v),
        ),
        if (!editing && _clientId == null) ...[
          kFieldGap,
          AppTextField(controller: _newClient, label: '…or Create New Client', hint: 'New client name'),
        ],
      ],
      if (_role == 'Vendor') ...[
        kFieldGap,
        AppDropdown<int>(
          label: 'Link Existing Vendor',
          hint: 'Select vendor',
          value: _vendorId,
          items: [for (final v in _vendors ?? const <Map<String, dynamic>>[]) (v['id'] as int, (v['name'] ?? '').toString())],
          onChanged: (v) => setState(() => _vendorId = v),
        ),
        if (!editing && _vendorId == null) ...[
          kFieldGap,
          AppTextField(controller: _newVendor, label: '…or Create New Vendor', hint: 'New vendor name'),
        ],
      ],
      const SizedBox(height: 18),
      SheetError(_error),
      SubmitButton(label: editing ? 'Save Changes' : 'Create User', busy: _saving, onPressed: _submit),
    ]);
  }
}

// ───────────────────────────────────────────────────────── module pickers

/// The inherit checkbox + module toggles shared by the per-user and per-role sheets.
class _ModulePicker extends StatelessWidget {
  final List<String> tenantAllowed;
  final bool inherit;
  final String inheritTitle;
  final String inheritSubtitle;
  final String listTitle;
  final Set<String> selected;
  final ValueChanged<bool> onInherit;
  final ValueChanged<String> onToggle;
  final String? emptyText;
  const _ModulePicker({
    required this.tenantAllowed,
    required this.inherit,
    required this.inheritTitle,
    required this.inheritSubtitle,
    required this.listTitle,
    required this.selected,
    required this.onInherit,
    required this.onToggle,
    this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Surface(
        color: p.muted,
        padding: EdgeInsets.zero,
        child: CheckboxListTile(
          value: inherit,
          onChanged: (v) => onInherit(v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(inheritTitle, style: tt.titleSmall),
          subtitle: Text(inheritSubtitle, style: tt.bodySmall),
        ),
      ),
      const SizedBox(height: 16),
      Eyebrow('$listTitle · ${selected.length} selected'),
      const SizedBox(height: 6),
      Opacity(
        opacity: inherit ? 0.5 : 1,
        child: IgnorePointer(
          ignoring: inherit,
          child: Column(children: [
            for (final m in tenantAllowed)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: selected.contains(m),
                onChanged: (_) => onToggle(m),
                title: Text(moduleLabel(m), style: tt.bodyMedium),
              ),
            if (tenantAllowed.isEmpty && emptyText != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(emptyText!, textAlign: TextAlign.center, style: tt.bodySmall)),
          ]),
        ),
      ),
    ]);
  }
}

/// UserModulesModal: one person's module set. Returns true when saved.
Future<bool> showUserModules(BuildContext context, Map<String, dynamic> user, List<String> tenantAllowed) async {
  final ok = await showAppSheet<bool>(
    context,
    title: (user['name'] ?? '').toString(),
    subtitle: 'Module permissions · ${user['email']} · ${user['role']}',
    builder: (_) => _UserModules(user: user, tenantAllowed: tenantAllowed),
  );
  return ok == true;
}

class _UserModules extends StatefulWidget {
  final Map<String, dynamic> user;
  final List<String> tenantAllowed;
  const _UserModules({required this.user, required this.tenantAllowed});

  @override
  State<_UserModules> createState() => _UserModulesState();
}

class _UserModulesState extends State<_UserModules> {
  late final List<String> _has = (widget.user['allowed_modules'] as List? ?? const []).map((e) => e.toString()).toList();
  late bool _inherit = _has.isEmpty;
  late final Set<String> _selected = {..._has};
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().patch('/users/${widget.user['id']}', data: {
        'allowed_modules': _inherit ? <String>[] : [for (final m in widget.tenantAllowed) if (_selected.contains(m)) m],
      });
      if (!mounted) return;
      showToast(context, 'Permissions updated');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : 'Update failed';
      setState(() {
        _saving = false;
        _error = msg;
      });
      showToast(context, msg, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _ModulePicker(
          tenantAllowed: widget.tenantAllowed,
          inherit: _inherit,
          inheritTitle: 'Inherit all tenant modules',
          inheritSubtitle: 'User sees every module the company is entitled to (${widget.tenantAllowed.length} total).',
          listTitle: 'Custom module set',
          selected: _selected,
          onInherit: (v) => setState(() => _inherit = v),
          onToggle: (m) => setState(() {
            _selected.contains(m) ? _selected.remove(m) : _selected.add(m);
            _inherit = false;
          }),
          emptyText: 'No modules are enabled for your company. Restart the backend to switch them all on.',
        ),
        const SizedBox(height: 18),
        SheetError(_error),
        SubmitButton(label: _saving ? 'Saving…' : 'Save', busy: _saving, onPressed: _save),
      ]);
}

/// BulkModulesModal: restrict or release modules for every user of one role. Returns true when saved.
Future<bool> showBulkModules(BuildContext context, List<String> tenantAllowed) async {
  final ok = await showAppSheet<bool>(
    context,
    title: 'Restrict or release modules for a whole role',
    subtitle: 'You can still change one person afterwards from the Modules button in their row.',
    builder: (_) => _BulkModules(tenantAllowed: tenantAllowed),
  );
  return ok == true;
}

class _BulkModules extends StatefulWidget {
  final List<String> tenantAllowed;
  const _BulkModules({required this.tenantAllowed});

  @override
  State<_BulkModules> createState() => _BulkModulesState();
}

class _BulkModulesState extends State<_BulkModules> {
  String _role = bulkRoles.first;
  bool _inherit = true;
  final Set<String> _selected = {};
  List<Map<String, dynamic>>? _roleUsers;
  bool _saving = false;
  String? _error;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final gen = ++_gen;
    setState(() => _roleUsers = null);
    try {
      final l = asMaps(await context.read<ApiClient>().get('/users/all', params: {'role': _role}));
      if (mounted && gen == _gen) setState(() => _roleUsers = l);
    } catch (e) {
      if (mounted && gen == _gen) setState(() => _error = errorText(e));
    }
  }

  List<Map<String, dynamic>> get _targets => (_roleUsers ?? const []).where((u) => u['status'] != 'Disabled').toList();

  void _fail(String msg) {
    setState(() => _error = msg);
    showToast(context, msg, error: true);
  }

  Future<void> _save() async {
    if (!_inherit && _selected.isEmpty) {
      _fail('Pick at least one module, or tick “Full access”');
      return;
    }
    final n = _targets.length;
    final label = roleWords(_role);
    if (!await confirmDialog(context,
        title: 'Apply this to all $n $label user(s)?',
        message: 'Their individual module settings will be replaced.',
        confirmLabel: 'Apply')) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await context.read<ApiClient>().post('/users/bulk-modules', data: {
        'role': _role,
        'allowed_modules': _inherit ? <String>[] : [for (final m in widget.tenantAllowed) if (_selected.contains(m)) m],
      });
      if (!mounted) return;
      showToast(context, 'Updated ${(r as Map)['updated']} $label user(s)');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _fail(e is ApiException ? e.message : 'Update failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final targets = _targets;
    final custom = targets.where((u) => (u['allowed_modules'] as List? ?? const []).isNotEmpty).length;
    final label = roleWords(_role);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Eyebrow('Role access'),
      const SizedBox(height: 8),
      ChoiceRow<String>(
        value: _role,
        options: [for (final r in bulkRoles) (r, roleWords(r))],
        onChanged: (r) {
          if (r == _role) return;
          setState(() => _role = r);
          _loadRole();
        },
      ),
      const SizedBox(height: 10),
      if (_roleUsers == null)
        Text('Counting users…', style: tt.bodySmall)
      else
        Text.rich(
          TextSpan(style: tt.bodySmall, children: [
            TextSpan(text: '${targets.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' active $label user${targets.length == 1 ? '' : 's'}'),
            if (custom > 0)
              TextSpan(
                  text: ' · $custom with individual settings that will be replaced',
                  style: TextStyle(color: p.tone(Tone.warning))),
          ]),
        ),
      const SizedBox(height: 16),
      _ModulePicker(
        tenantAllowed: widget.tenantAllowed,
        inherit: _inherit,
        inheritTitle: 'Full access (release all)',
        inheritSubtitle:
            'Every module the company is entitled to (${widget.tenantAllowed.length} total), within what the role can normally open.',
        listTitle: 'Allowed modules',
        selected: _selected,
        onInherit: (v) => setState(() => _inherit = v),
        onToggle: (m) => setState(() {
          _selected.contains(m) ? _selected.remove(m) : _selected.add(m);
          _inherit = false;
        }),
      ),
      const SizedBox(height: 18),
      SheetError(_error),
      SubmitButton(
        label: _saving ? 'Saving…' : 'Apply to ${targets.length}',
        busy: _saving,
        onPressed: targets.isEmpty ? null : _save,
      ),
    ]);
  }
}

// ───────────────────────────────────────────────────────── project assignment

/// ProjectAssignmentPicker: put a PM / SE / PO on a project.
Future<void> showAssignProject(BuildContext context, Map<String, dynamic> user) => showAppSheet<bool>(
      context,
      title: 'Assign to Project',
      builder: (_) => _AssignProject(user: user),
    );

class _AssignProject extends StatefulWidget {
  final Map<String, dynamic> user;
  const _AssignProject({required this.user});

  @override
  State<_AssignProject> createState() => _AssignProjectState();
}

class _AssignProjectState extends State<_AssignProject> {
  List<Map<String, dynamic>>? _projects;
  int? _projectId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final org = context.read<OrgProvider>();
    try {
      final r = await context.read<ApiClient>().get('/projects', params: {'limit': 200, ...org.orgParams});
      if (mounted) setState(() => _projects = asMaps((r as Map)['items']));
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _assign() async {
    if (_projectId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post('/projects/$_projectId/assignments',
          data: {'user_id': widget.user['id'], 'assigned_role': widget.user['role']});
      if (!mounted) return;
      showToast(context, '${widget.user['name']} assigned to project');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorText(e);
      });
      showToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text.rich(TextSpan(style: tt.bodyMedium, children: [
        const TextSpan(text: 'Assign '),
        TextSpan(text: '${widget.user['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: ' (${widget.user['role']}) to a project.'),
      ])),
      const SizedBox(height: 16),
      AppDropdown<int>(
        label: 'Project',
        hint: _projects == null ? 'Loading…' : 'Select project',
        value: _projectId,
        items: [for (final p in _projects ?? const <Map<String, dynamic>>[]) (p['id'] as int, (p['name'] ?? '').toString())],
        onChanged: (v) => setState(() => _projectId = v),
      ),
      const SizedBox(height: 18),
      SheetError(_error),
      SubmitButton(label: 'Assign', busy: _saving, onPressed: _projectId == null ? null : _assign),
    ]);
  }
}
