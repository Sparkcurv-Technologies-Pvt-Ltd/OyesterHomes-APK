part of 'inventory_screen.dart';

// Approvals (pending carts) and the material catalog / warehouse list. Supervisor tabs only
// (Admin, ProjectManager, ProcurementOfficer), as on the web.

// ───────────────────────────────────────────────────────── approvals

/// Pending movements grouped by batch_id (a cart submitted in one go), so the approver sees, and approves
/// or rejects, the whole cart as one decision (web ApprovalsList).
class _ApprovalsList extends StatefulWidget {
  final _InvData data;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onDone;
  const _ApprovalsList({required this.data, required this.onRefresh, required this.onDone});

  @override
  State<_ApprovalsList> createState() => _ApprovalsListState();
}

class _ApprovalsListState extends State<_ApprovalsList> {
  String? _busy;

  Future<void> _act(_Batch b, String action) async {
    if (action == 'reject') {
      final ok = await confirmDialog(context,
          title: 'Reject this request?',
          message: b.lines.length > 1 ? 'All ${b.lines.length} lines in this request are rejected.' : null,
          confirmLabel: 'Reject',
          destructive: true);
      if (!ok || !mounted) return;
    }
    setState(() => _busy = b.key);
    final ok = await runAction(
      context,
      () => context.read<ApiClient>().post('/inventory/movements/${b.id}/$action'),
      success: action == 'approve' ? 'Approved' : 'Rejected',
    );
    if (!mounted) return;
    setState(() => _busy = null);
    if (ok) await widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final batches = _groupBatches(d.movements.where((m) => m['status'] == 'Pending'));

    return RefreshList(onRefresh: widget.onRefresh, children: [
      if (batches.isEmpty)
        const EmptyState(icon: Icons.task_alt, title: 'No pending requests.'),
      for (final b in batches)
        Builder(builder: (context) {
          final first = b.first;
          final isIssue = first['movement_type'] == 'Issue';
          final to = isIssue ? d.projectName(first['project_id']) : d.locationName(first['to_location_id']);
          return Surface(
            margin: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 4),
            padding: EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                color: p.muted,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    StatusChip(first['movement_type'] as String?, dense: true),
                    const Spacer(),
                    Text(fmtDateTime(first['requested_at']), style: tabular(tt.bodySmall)),
                  ]),
                  const SizedBox(height: 6),
                  Text('${d.locationName(first['from_location_id'])} → $to', style: tt.bodyMedium),
                  if (first['requested_by_name'] != null)
                    Text('Requested by ${first['requested_by_name']}', style: tt.bodySmall),
                ]),
              ),
              for (var i = 0; i < b.lines.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 14, endIndent: 14, color: p.border),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    Expanded(child: Text(d.materialName(b.lines[i]['material_id']), style: tt.bodyMedium)),
                    Text('${qty(b.lines[i]['quantity'])} ${d.unitOf(b.lines[i]['material_id'])}',
                        style: tabular(tt.bodyMedium).copyWith(fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
              if ((first['notes'] ?? '').toString().isNotEmpty) ...[
                Divider(height: 1, color: p.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  child: Text('${first['notes']}', style: tt.bodySmall),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                child: _DecisionButtons(
                  okLabel: 'Approve${b.lines.length > 1 ? ' all (${b.lines.length})' : ''}',
                  noLabel: 'Reject',
                  busy: _busy == b.key,
                  onOk: () => _act(b, 'approve'),
                  onNo: () => _act(b, 'reject'),
                ),
              ),
            ]),
          );
        }),
    ]);
  }
}

// ───────────────────────────────────────────────────────── materials & locations

class _ManageMaterialsLocations extends StatelessWidget {
  final _InvData data;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onDone;
  const _ManageMaterialsLocations({required this.data, required this.onRefresh, required this.onDone});

  Future<void> _materialSheet(BuildContext context, [_Json? m]) async {
    final saved = await showAppSheet<bool>(
      context,
      title: m == null ? 'Add material' : 'Edit material',
      builder: (ctx) => _MaterialForm(material: m),
    );
    if (saved == true) await onDone();
  }

  Future<void> _warehouseSheet(BuildContext context) async {
    final saved = await showAppSheet<bool>(
      context,
      title: 'Add warehouse',
      builder: (ctx) => const _WarehouseForm(),
    );
    if (saved == true) await onDone();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    Widget add(String label, VoidCallback onTap) => TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: onTap,
          icon: const Icon(Icons.add, size: 18),
          label: Text(label),
        );

    return RefreshList(onRefresh: onRefresh, children: [
      SectionHeader('Material Catalog', trailing: add('Add material', () => _materialSheet(context))),
      if (data.materials.isEmpty)
        const EmptyState(icon: Icons.category_outlined, title: 'No materials in the catalog yet.')
      else
        RowGroup(children: [
          for (final m in data.materials)
            RowTile(
              title: '${m['name']}',
              subtitle: '${dash(m['category'])} · ${m['unit'] ?? ''}',
              trailing: Icon(Icons.edit_outlined, size: 18, color: context.pal.fgSubtle),
              onTap: () => _materialSheet(context, m),
            ),
        ]),
      SectionHeader('Warehouses', trailing: add('Add warehouse', () => _warehouseSheet(context))),
      if (data.locations.isEmpty)
        const EmptyState(icon: Icons.warehouse_outlined, title: 'No warehouses yet.')
      else
        RowGroup(children: [
          for (final l in data.locations)
            RowTile(
              title: '${l['name']}',
              trailing: Text('${l['location_type'] ?? ''}', style: tt.bodySmall),
            ),
        ]),
    ]);
  }
}

/// Add (POST /inventory/materials) or edit (PATCH /inventory/materials/{id}) a catalog material.
class _MaterialForm extends StatefulWidget {
  final _Json? material;
  const _MaterialForm({this.material});

  @override
  State<_MaterialForm> createState() => _MaterialFormState();
}

class _MaterialFormState extends State<_MaterialForm> {
  late final _name = TextEditingController(text: widget.material?['name']?.toString() ?? '');
  late final _category = TextEditingController(text: widget.material?['category']?.toString() ?? '');
  late final _unit = TextEditingController(text: widget.material?['unit']?.toString() ?? 'bag');
  bool _saving = false;
  String? _err;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _err = 'Material name is required');
      showToast(context, 'Material name is required', error: true);
      return;
    }
    setState(() {
      _saving = true;
      _err = null;
    });
    final body = {
      'name': _name.text.trim(),
      'category': _category.text.isEmpty ? null : _category.text,
      'unit': _unit.text,
    };
    try {
      final api = context.read<ApiClient>();
      final m = widget.material;
      if (m == null) {
        await api.post('/inventory/materials', data: body);
      } else {
        await api.patch('/inventory/materials/${m['id']}', data: body);
      }
      if (!mounted) return;
      showToast(context, m == null ? 'Material added' : 'Material updated');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = errorText(e);
        _saving = false;
      });
      showToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppTextField(controller: _name, label: 'Name', requiredField: true, autofocus: widget.material == null),
      kFieldGap,
      AppTextField(controller: _category, label: 'Category'),
      kFieldGap,
      AppTextField(controller: _unit, label: 'Unit', capitalization: TextCapitalization.none),
      const SizedBox(height: 18),
      _InlineError(_err),
      SubmitButton(label: widget.material == null ? 'Add material' : 'Save', busy: _saving, onPressed: _save),
    ]);
  }
}

/// Add a warehouse (POST /inventory/locations). Project site stores are created by the backend.
class _WarehouseForm extends StatefulWidget {
  const _WarehouseForm();

  @override
  State<_WarehouseForm> createState() => _WarehouseFormState();
}

class _WarehouseFormState extends State<_WarehouseForm> {
  final _name = TextEditingController();
  bool _saving = false;
  String? _err;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _err = 'Warehouse name is required');
      showToast(context, 'Warehouse name is required', error: true);
      return;
    }
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      await context.read<ApiClient>().post('/inventory/locations', data: {'name': _name.text.trim()});
      if (!mounted) return;
      showToast(context, 'Warehouse added');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = errorText(e);
        _saving = false;
      });
      showToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppTextField(controller: _name, label: 'Warehouse name', requiredField: true, autofocus: true),
      const SizedBox(height: 18),
      _InlineError(_err),
      SubmitButton(label: 'Add warehouse', busy: _saving, onPressed: _save),
    ]);
  }
}
