import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../org/org_provider.dart';
import 'project_common.dart';

/// Create / edit a project (web ProjectFormModal.jsx with SubcontractorsSection.jsx).
/// Returns the saved project, or null if cancelled.
Future<Map<String, dynamic>?> showProjectForm(BuildContext context, {Map<String, dynamic>? project, int? clientId}) {
  return showAppSheet<Map<String, dynamic>>(
    context,
    title: project != null ? 'Edit Project' : 'New Project',
    builder: (ctx) => _ProjectForm(project: project, clientId: clientId),
  );
}

const _commonSubTypes = [
  'Electrical', 'Plumbing', 'Construction', 'Civil Works', //
  'Painting', 'Interior', 'Carpentry', 'HVAC', 'Roofing', //
  'Tiling', 'Waterproofing', 'Landscaping',
];

/// One sub-contractor draft row (web SubcontractorsSection item).
class _SubDraft {
  final int? id;
  final TextEditingController type;
  final TextEditingController name;
  final TextEditingController amount;
  final TextEditingController notes;
  final TextEditingController matDraft = TextEditingController();
  final List<String> materials;
  String? typeError;
  String? amountError;

  _SubDraft({this.id, String type = '', String name = '', String amount = '', String notes = '', List<String>? materials})
      : type = TextEditingController(text: type),
        name = TextEditingController(text: name),
        amount = TextEditingController(text: amount),
        notes = TextEditingController(text: notes),
        materials = materials ?? [];

  void dispose() {
    type.dispose();
    name.dispose();
    amount.dispose();
    notes.dispose();
    matDraft.dispose();
  }
}

class _ProjectForm extends StatefulWidget {
  final Map<String, dynamic>? project;
  final int? clientId;
  const _ProjectForm({this.project, this.clientId});

  @override
  State<_ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<_ProjectForm> {
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _budget = TextEditingController();
  int? _clientId;
  int? _engineerId;
  int? _managerId;
  int? _branchId;
  String? _start;
  String? _end;
  String _status = 'Planning';
  Map<String, String> _errors = {};
  bool _busy = false;
  bool _detecting = false;

  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _engineers = [];
  List<Map<String, dynamic>>? _managers;
  final List<_SubDraft> _subs = [];
  List<_SubDraft> _existing = []; // for edit-mode diffing (ids only matter)
  final List<_SubDraft> _removed = [];

  bool get _edit => widget.project != null;
  late final ApiClient _api = context.read<ApiClient>();
  late final bool _isAdmin = context.read<AuthProvider>().user?.role == 'Admin';

  @override
  void initState() {
    super.initState();
    final pr = widget.project;
    final org = context.read<OrgProvider>();
    if (pr != null) {
      _name.text = (pr['name'] ?? '').toString();
      _clientId = pr['client_id'] as int?;
      _engineerId = pr['site_engineer_id'] as int?;
      _managerId = pr['project_manager_id'] as int?;
      _branchId = pr['branch_id'] as int?;
      _location.text = (pr['location'] ?? '').toString();
      _budget.text = inputNum(pr['budget']);
      _start = pr['start_date_planned'] as String?;
      _end = pr['end_date_planned'] as String?;
      _status = (pr['status'] ?? 'Planning') as String;
    } else {
      final c = org.company;
      final firstBranch = c == null ? null : org.branchesOf(c).firstOrNull;
      _branchId = (org.branch?['id'] ?? firstBranch?['id']) as int?;
      _clientId = widget.clientId;
    }
    _loadLists();
  }

  Future<void> _loadLists() async {
    Future<List<Map<String, dynamic>>> safe(Future<dynamic> f) async {
      try {
        return asMapList(await f);
      } catch (_) {
        return [];
      }
    }

    final res = await Future.wait([
      safe(_api.get('/clients')),
      safe(_api.get('/users', params: {'role': 'SiteEngineer'})),
      if (_isAdmin) safe(_api.get('/users', params: {'role': 'ProjectManager'})),
      if (_edit) safe(_api.get('/projects/${widget.project!['id']}/subcontractors')),
    ]);
    if (!mounted) return;
    setState(() {
      _clients = res[0];
      _engineers = res[1];
      var i = 2;
      if (_isAdmin) _managers = res[i++];
      if (_edit) {
        for (final s in res[i]) {
          _subs.add(_SubDraft(
            id: s['id'] as int?,
            type: (s['type'] ?? '').toString(),
            name: (s['name'] ?? '').toString(),
            amount: inputNum(s['allocated_amount']),
            notes: (s['notes'] ?? '').toString(),
            materials: ((s['materials'] as List?) ?? []).map((e) => e.toString()).toList(),
          ));
        }
        _existing = List.of(_subs);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _budget.dispose();
    for (final s in {..._subs, ..._existing, ..._removed}) {
      s.dispose();
    }
    super.dispose();
  }

  /// New projects follow their dates: past end → Completed, started → Ongoing, else Planning.
  void _autoStatus() {
    if (_edit) return;
    if ((_start ?? '').isEmpty && (_end ?? '').isEmpty) return;
    final t = todayIso();
    var s = 'Planning';
    if ((_end ?? '').isNotEmpty && _end!.compareTo(t) < 0) {
      s = 'Completed';
    } else if ((_start ?? '').isNotEmpty && _start!.compareTo(t) <= 0) {
      s = 'Ongoing';
    }
    _status = s;
  }

  bool _validate() {
    final e = <String, String>{};
    if (_name.text.trim().isEmpty) e['name'] = 'Project name is required';
    if (_clientId == null) e['client_id'] = 'Client is required';
    if ((_start ?? '').isNotEmpty && (_end ?? '').isNotEmpty && _end!.compareTo(_start!) < 0) {
      e['end_date_planned'] = 'End date must be after start date';
    }
    if (_budget.text.isNotEmpty && toNum(_budget.text) < 0) e['budget'] = 'Budget must be positive';
    setState(() => _errors = e);
    return e.isEmpty;
  }

  /// web validateSubcontractors: returns the cleaned list, or null when a row is invalid.
  List<Map<String, dynamic>>? _validateSubs() {
    var valid = true;
    final cleaned = <Map<String, dynamic>>[];
    for (final s in _subs) {
      final type = s.type.text.trim();
      s.typeError = type.isEmpty ? 'Type is required' : null;
      final amt = s.amount.text.trim().isEmpty ? null : double.tryParse(s.amount.text.trim());
      s.amountError = (amt == null || amt < 0) ? 'Enter a positive number' : null;
      if (s.typeError != null || s.amountError != null) valid = false;
      final name = s.name.text.trim();
      final notes = s.notes.text.trim();
      cleaned.add({
        'type': type,
        'name': name.isEmpty ? null : name,
        'allocated_amount': amt ?? 0,
        'materials': s.materials.map((m) => m.trim()).where((m) => m.isNotEmpty).toList(),
        'notes': notes.isEmpty ? null : notes,
      });
    }
    setState(() {});
    return valid ? cleaned : null;
  }

  Future<void> _syncSubs(int projectId, List<Map<String, dynamic>> cleaned) async {
    final currentIds = _subs.where((s) => s.id != null).map((s) => s.id).toSet();
    final removed = _existing.where((s) => s.id != null && !currentIds.contains(s.id));
    await Future.wait(removed.map((s) => _api.delete('/subcontractors/${s.id}')));
    for (var i = 0; i < _subs.length; i++) {
      final item = _subs[i];
      if (item.id != null) {
        await _api.patch('/subcontractors/${item.id}', data: cleaned[i]);
      } else {
        await _api.post('/projects/$projectId/subcontractors', data: cleaned[i]);
      }
    }
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    final cleanedSubs = _validateSubs();
    if (cleanedSubs == null) {
      showToast(context, 'Fix sub-contractor errors before saving', error: true);
      return;
    }
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'client_id': _clientId,
      'site_engineer_id': _engineerId,
      if (_isAdmin) 'project_manager_id': _managerId,
      if (_isAdmin && _branchId != null) 'branch_id': _branchId,
      'location': _location.text.isEmpty ? null : _location.text,
      'budget': _budget.text.isNotEmpty ? toNum(_budget.text) : null,
      'start_date_planned': (_start ?? '').isEmpty ? null : _start,
      'end_date_planned': (_end ?? '').isEmpty ? null : _end,
      'status': _status,
    };
    setState(() => _busy = true);
    Map<String, dynamic>? saved;
    final ok = await runAction(context, () async {
      if (_edit) {
        final id = widget.project!['id'] as int;
        saved = Map<String, dynamic>.from(await _api.put('/projects/$id', data: payload) as Map);
        await _syncSubs(id, cleanedSubs);
      } else {
        saved = Map<String, dynamic>.from(await _api.post('/projects', data: {...payload, 'subcontractors': cleanedSubs}) as Map);
      }
    }, success: _edit ? 'Project updated' : 'Project created');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop(saved);
  }

  /// No location plugin on the phone: paste a Google / OpenStreetMap link or "lat, lng" and the server
  /// names the place (GET /geo/reverse), like the web's "Detect my location" does with the browser's GPS.
  Future<void> _detectLocation() async {
    final text = await promptText(context,
        title: 'Detect location', label: 'Paste a map link or "lat, lng"', confirmLabel: 'Detect', required: true, maxLines: 2);
    if (text == null || !mounted) return;
    final ll = parseMapLink(text);
    if (ll == null) {
      showToast(context, 'Could not read a location from that — please type the address manually', error: true);
      return;
    }
    setState(() => _detecting = true);
    try {
      final d = await _api.get('/geo/reverse', params: {'lat': ll.$1, 'lon': ll.$2});
      _location.text = (d['location'] ?? '').toString();
      if (mounted) showToast(context, 'Location detected');
    } catch (_) {
      _location.text = '${ll.$1.toStringAsFixed(4)}, ${ll.$2.toStringAsFixed(4)}';
      if (mounted) showToast(context, 'Location detected (coordinates)');
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final org = context.watch<OrgProvider>();
    final budget = toNumOrNull(_budget.text);

    Widget err(String key) => _errors[key] == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(_errors[key]!, style: tt.bodySmall?.copyWith(color: p.danger)),
          );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTextField(controller: _name, label: 'Project Name', requiredField: true),
      err('name'),
      if (_isAdmin) ...[
        kFieldGap,
        AppDropdown<int>(
          label: 'Company / Branch',
          requiredField: true,
          value: _branchId,
          hint: 'Default branch',
          items: [
            for (final c in org.companies)
              for (final b in org.branchesOf(c)) (b['id'] as int, '${c['name']} / ${b['name']}'),
          ],
          onChanged: (v) => setState(() => _branchId = v),
        ),
        kFieldGap,
        AppDropdown<int?>(
          label: 'Project Manager',
          value: _managerId,
          hint: 'Not assigned',
          items: [
            (null, 'Not assigned'),
            for (final m in _managers ?? const <Map<String, dynamic>>[]) (m['id'] as int, (m['name'] ?? '').toString()),
          ],
          helper: _managers != null && _managers!.isEmpty ? 'Add a user with the Project Manager role first.' : null,
          onChanged: (v) => setState(() => _managerId = v),
        ),
      ],
      kFieldGap,
      AppDropdown<int>(
        label: 'Client',
        requiredField: true,
        value: _clientId,
        hint: 'Select client',
        items: [
          for (final c in _clients) (c['id'] as int, (c['name'] ?? '').toString()),
          // The client list is role-gated (a Project Manager cannot read it): keep the current client visible.
          if (_clientId != null && _edit && !_clients.any((c) => c['id'] == _clientId))
            (_clientId!, (widget.project!['client_name'] ?? 'Client #$_clientId').toString()),
        ],
        onChanged: (v) => setState(() => _clientId = v),
      ),
      err('client_id'),
      kFieldGap,
      AppDropdown<int>(
        label: 'Site Engineer',
        value: _engineerId,
        hint: 'Assign engineer',
        items: [
          for (final e in _engineers) (e['id'] as int, (e['name'] ?? '').toString()),
          if (_engineerId != null && _edit && !_engineers.any((e) => e['id'] == _engineerId))
            (_engineerId!, (widget.project!['site_engineer_name'] ?? 'Engineer #$_engineerId').toString()),
        ],
        onChanged: (v) => setState(() => _engineerId = v),
      ),
      kFieldGap,
      AppTextField(
        controller: _location,
        label: 'Location',
        hint: 'Auto-detect or type address',
        suffix: IconButton(
          tooltip: 'Detect my location',
          onPressed: _detecting ? null : _detectLocation,
          icon: _detecting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.location_on_outlined, size: 20),
        ),
      ),
      kFieldGap,
      AppTextField(
        controller: _budget,
        label: 'Budget (₹)',
        hint: 'e.g. 250000000 = ₹25 Cr',
        money: true,
        onChanged: (_) => setState(() {}),
      ),
      if (budget != null && budget > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text('= ${inr(budget)}', style: tt.bodySmall?.copyWith(color: p.accentText, fontWeight: FontWeight.w600)),
        ),
      err('budget'),
      kFieldGap,
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: DateField(
              label: 'Planned Start',
              value: _start,
              onChanged: (v) => setState(() {
                    _start = v;
                    _autoStatus();
                  })),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DateField(
              label: 'Planned End',
              value: _end,
              onChanged: (v) => setState(() {
                    _end = v;
                    _autoStatus();
                  })),
        ),
      ]),
      err('end_date_planned'),
      kFieldGap,
      AppDropdown<String>(
        label: 'Status',
        value: _status,
        items: [for (final s in projectStatuses) (s, s)],
        onChanged: (v) => setState(() => _status = v ?? _status),
      ),
      const SizedBox(height: 20),
      Divider(height: 1, color: p.border),
      const SizedBox(height: 12),
      _subsSection(context),
      const SizedBox(height: 20),
      SubmitButton(
        label: _edit ? 'Save Changes' : 'Create Project',
        busy: _busy,
        onPressed: _submit,
      ),
    ]);
  }

  Widget _subsSection(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Eyebrow('Sub-Contractors'),
            const SizedBox(height: 2),
            Text('Allocate scope, budget & materials', style: tt.bodySmall),
          ]),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _subs.add(_SubDraft())),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Sub-Contractor'),
        ),
      ]),
      const SizedBox(height: 8),
      if (_subs.isEmpty)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(8)),
          child: Text('No sub-contractors added yet. Tap "Add Sub-Contractor" to allocate scope, budget and materials.',
              textAlign: TextAlign.center, style: tt.bodySmall),
        ),
      for (var i = 0; i < _subs.length; i++) _subRow(context, i),
    ]);
  }

  Widget _subRow(BuildContext context, int i) {
    final s = _subs[i];
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    void addMaterial() {
      final v = s.matDraft.text.trim();
      if (v.isEmpty) return;
      setState(() {
        if (!s.materials.contains(v)) s.materials.add(v);
        s.matDraft.clear();
      });
    }

    return Surface(
      key: ObjectKey(s),
      margin: const EdgeInsets.only(bottom: 10),
      color: p.muted.withValues(alpha: 0.4),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Eyebrow('Sub-contractor ${i + 1}')),
          IconButton(
            tooltip: 'Remove sub-contractor',
            icon: Icon(Icons.delete_outline, size: 20, color: p.fgMuted),
            onPressed: () => setState(() => _removed.add(_subs.removeAt(i))),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Autocomplete<String>(
              initialValue: TextEditingValue(text: s.type.text),
              optionsBuilder: (v) => _commonSubTypes.where((t) => t.toLowerCase().contains(v.text.toLowerCase())),
              onSelected: (v) => s.type.text = v,
              fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
                controller: ctrl,
                focusNode: focus,
                textCapitalization: TextCapitalization.words,
                onChanged: (v) => s.type.text = v,
                decoration: InputDecoration(labelText: 'Type *', hintText: 'e.g. Electrical', errorText: s.typeError),
              ),
            ),
            kFieldGap,
            AppTextField(controller: s.name, label: 'Firm / Contact', hint: 'Optional'),
            kFieldGap,
            TextField(
              controller: s.amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Allocated (₹) *', hintText: '0', prefixText: '₹ ', errorText: s.amountError),
            ),
            kFieldGap,
            const Eyebrow('Materials Provided'),
            const SizedBox(height: 6),
            if (s.materials.isNotEmpty)
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in s.materials) TagChip(m, onRemove: () => setState(() => s.materials.remove(m))),
              ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: s.matDraft,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => addMaterial(),
                  decoration: const InputDecoration(hintText: 'Add material & press Enter', isDense: true),
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton(onPressed: addMaterial, child: const Text('Add')),
            ]),
            kFieldGap,
            AppTextField(controller: s.notes, label: 'Notes', maxLines: 2),
            if (s.typeError != null || s.amountError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text([s.typeError, s.amountError].whereType<String>().join(' · '),
                    style: tt.bodySmall?.copyWith(color: p.danger)),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// "11.0168, 76.9558" or a Google / OpenStreetMap link → (lat, lng), else null (web utils/geo.js parseMapLink).
(double, double)? parseMapLink(String text) {
  var s = text.trim();
  try {
    s = Uri.decodeComponent(s);
  } catch (_) {}
  final patterns = [
    RegExp(r'!3d(-?\d{1,2}\.\d+)!4d(-?\d{1,3}\.\d+)'),
    RegExp(r'@(-?\d{1,2}\.\d+),\s*(-?\d{1,3}\.\d+)'),
    RegExp(r'[?&](?:q|ll|query|destination)=(-?\d{1,2}\.\d+),\s*(-?\d{1,3}\.\d+)'),
    RegExp(r'[?&]mlat=(-?\d{1,2}\.\d+)&mlon=(-?\d{1,3}\.\d+)'),
    RegExp(r'^(-?\d{1,2}\.\d+)\s*[, ]\s*(-?\d{1,3}\.\d+)$'),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(s);
    if (m != null) {
      final lat = double.parse(m[1]!), lng = double.parse(m[2]!);
      if (lat.abs() <= 90 && lng.abs() <= 180) return (lat, lng);
    }
  }
  return null;
}
