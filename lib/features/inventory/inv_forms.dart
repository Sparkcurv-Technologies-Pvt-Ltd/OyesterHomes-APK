part of 'inventory_screen.dart';

// Receive (GRN) and Issue / Transfer cart forms. Each renders as a Column, so it works both in its tab
// and inside a bottom sheet ([inSheet] hides the heading the sheet already shows).

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionTitle(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(children: [
        Icon(icon, size: 18, color: p.fgMuted),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleSmall)),
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────── receive

class _ReceiveForm extends StatefulWidget {
  final _InvData data;
  final VoidCallback onDone;
  final bool inSheet;
  const _ReceiveForm({required this.data, required this.onDone, this.inSheet = false});

  @override
  State<_ReceiveForm> createState() => _ReceiveFormState();
}

class _ReceiveFormState extends State<_ReceiveForm> {
  int? _locationId;
  final _notes = TextEditingController();
  Map<int, double> _qty = {};
  Map<int, String> _cost = {};
  bool _saving = false;
  String? _err;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  List<_Json> get _items => [
        for (final it in _cartItems(_qty))
          {
            ...it,
            'unit_cost': (_cost[it['material_id']] ?? '').trim().isNotEmpty ? toNum(_cost[it['material_id']]) : null,
          },
      ];

  void _fail(String msg) {
    setState(() => _err = msg);
    showToast(context, msg, error: true);
  }

  Future<void> _submit() async {
    final items = _items;
    if (_locationId == null) return _fail('Pick a warehouse');
    if (items.isEmpty) return _fail('Set a quantity for at least one material');
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      await context.read<ApiClient>().post('/inventory/receipts', data: {
        'location_id': _locationId,
        'items': items,
        'notes': _notes.text.isEmpty ? null : _notes.text,
      });
      if (!mounted) return;
      showToast(context, '${items.length} material${items.length > 1 ? 's' : ''} received');
      setState(() {
        _qty = {};
        _cost = {};
        _notes.clear();
      });
      widget.onDone();
    } catch (e) {
      if (mounted) _fail(errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final n = _cartItems(_qty).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (!widget.inSheet) const _SectionTitle(Icons.add_box_outlined, 'Goods Receipt (GRN)'),
      AppDropdown<int>(
        label: 'Into Warehouse',
        requiredField: true,
        hint: 'Select warehouse…',
        value: _locationId,
        items: [for (final l in d.warehouses) (l['id'] as int, _locLabel(l))],
        onChanged: (v) => setState(() => _locationId = v),
      ),
      kFieldGap,
      const Eyebrow('Materials *'),
      const SizedBox(height: 8),
      _MaterialCartList(
        materials: d.materials,
        qtyMap: _qty,
        onQtyChange: (id, v) => setState(() => _qty = {..._qty, id: v}),
        showCost: true,
        costMap: _cost,
        onCostChange: (id, v) => _cost = {..._cost, id: v},
      ),
      kFieldGap,
      AppTextField(controller: _notes, label: 'Notes'),
      const SizedBox(height: 18),
      _InlineError(_err),
      SubmitButton(
        label: 'Record Receipt${n > 1 ? ' ($n items)' : ''}',
        icon: Icons.add_box_outlined,
        busy: _saving,
        onPressed: _submit,
      ),
    ]);
  }
}

// ───────────────────────────────────────────────────────── issue / transfer

class _IssueTransferForm extends StatefulWidget {
  final _InvData data;
  final VoidCallback onDone;
  final bool inSheet;
  final String initialMode;
  const _IssueTransferForm({required this.data, required this.onDone, this.inSheet = false, this.initialMode = 'Issue'});

  @override
  State<_IssueTransferForm> createState() => _IssueTransferFormState();
}

class _IssueTransferFormState extends State<_IssueTransferForm> {
  late String _mode = widget.initialMode;
  int? _fromId;
  String _toDest = ''; // "p:<projectId>" or "w:<warehouseId>"
  int? _projectId;
  final _notes = TextEditingController();
  Map<int, double> _qty = {};
  bool _saving = false;
  bool _reviewing = false;
  String? _err;

  // what is actually in stock at the chosen source (empty until a source is picked)
  Map<int, double> _available = {};
  bool _stockLoading = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  _Json? get _fromLoc => _find(widget.data.locations, _fromId);

  // Stock held at a project site is that project's own material, so an issue from it is charged to that
  // project. A warehouse belongs to no project, so the person issuing picks which project the cost goes to.
  int? get _siteProjectId => _fromLoc?['project_id'] as int?;
  int? get _chargeProjectId => _siteProjectId ?? _projectId;

  Future<void> _pickFrom(String v) async {
    final id = int.tryParse(v);
    setState(() {
      _fromId = id;
      _qty = {};
      _available = {};
      _stockLoading = id != null;
    });
    if (id == null) return;
    try {
      final r = await context.read<ApiClient>().get('/inventory/stock', params: {'location_id': id});
      if (!mounted || _fromId != id) return;
      setState(() {
        _available = {for (final s in _list(r)) s['material_id'] as int: toNum(s['quantity'])};
      });
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted && _fromId == id) setState(() => _stockLoading = false);
    }
  }

  void _fail(String msg) {
    setState(() => _err = msg);
    showToast(context, msg, error: true);
  }

  void _goToReview() {
    final items = _cartItems(_qty);
    if (_fromId == null) return _fail('Pick a source location');
    if (items.isEmpty) return _fail('Set a quantity for at least one material');
    if (_mode == 'Issue' && _chargeProjectId == null) return _fail('Pick the project this material is used on');
    if (_mode == 'Transfer' && _toDest.isEmpty) return _fail('Pick the project or warehouse the material is going to');
    setState(() {
      _err = null;
      _reviewing = true;
    });
  }

  Future<void> _confirmSubmit() async {
    final api = context.read<ApiClient>();
    final items = _cartItems(_qty);
    final notes = _notes.text.isEmpty ? null : _notes.text;
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      if (_mode == 'Issue') {
        await api.post('/inventory/issues', data: {
          'from_location_id': _fromId,
          'project_id': _chargeProjectId,
          'items': items,
          'notes': notes,
        });
      } else {
        final parts = _toDest.split(':');
        final id = int.parse(parts[1]);
        await api.post('/inventory/transfers', data: {
          'from_location_id': _fromId,
          'items': items,
          'notes': notes,
          if (parts[0] == 'p') 'to_project_id': id else 'to_location_id': id,
        });
      }
      if (!mounted) return;
      showToast(
          context,
          _mode == 'Issue'
              ? 'Issue request submitted'
              : 'Transfer submitted — it counts at the destination once they confirm receipt');
      setState(() {
        _fromId = null;
        _toDest = '';
        _projectId = null;
        _qty = {};
        _available = {};
        _notes.clear();
        _reviewing = false;
      });
      widget.onDone();
    } catch (e) {
      if (mounted) _fail(errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _reviewing ? _review(context) : _form(context);

  Widget _form(BuildContext context) {
    final d = widget.data;
    final tt = Theme.of(context).textTheme;
    final n = _cartItems(_qty).length;
    final site = _siteProjectId;
    final projectItems = [for (final p in d.pickable) (p['id'] as int, '${p['name']}')];
    if (site != null && !projectItems.any((e) => e.$1 == site)) {
      projectItems.insert(0, (site, (_fromLoc?['project_name'] ?? d.projectName(site)).toString()));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (!widget.inSheet) const _SectionTitle(Icons.swap_horiz, 'Issue material or transfer between locations'),
      ChoiceRow<String>(
        value: _mode,
        options: const [('Issue', 'Issue'), ('Transfer', 'Transfer')],
        onChanged: (m) => setState(() {
          _mode = m;
          _reviewing = false;
          _err = null;
        }),
      ),
      kFieldGap,
      _GroupedDropdown(
        label: 'From',
        requiredField: true,
        value: _fromId == null ? '' : '$_fromId',
        noneLabel: 'Select warehouse or project site…',
        groups: _locationGroups(d),
        onChanged: _pickFrom,
      ),
      kFieldGap,
      if (_mode == 'Issue')
        AppDropdown<int>(
          label: 'Charge cost to project',
          requiredField: true,
          hint: 'Select project…',
          value: _chargeProjectId,
          items: projectItems,
          onChanged: site != null ? null : (v) => setState(() => _projectId = v),
          helper: site != null
              ? "This stock sits at the project's own site, so the cost is charged to that project."
              : "The material is used up and its cost is charged to this project's expenses.",
        )
      else
        _GroupedDropdown(
          label: 'Transfer To Project',
          requiredField: true,
          value: _toDest,
          noneLabel: 'Select project…',
          groups: [
            ('Projects', [for (final p in d.pickable) ('p:${p['id']}', '${p['name']}')]),
            ('Warehouses (not a project)', [for (final l in d.warehouses) ('w:${l['id']}', _locLabel(l))]),
          ],
          onChanged: (v) => setState(() => _toDest = v),
        ),
      kFieldGap,
      const Eyebrow('Materials *'),
      const SizedBox(height: 8),
      if (_stockLoading)
        const LoadingView(label: 'Checking stock here…')
      else
        _MaterialCartList(
          materials: d.materials,
          qtyMap: _qty,
          onQtyChange: (id, v) => setState(() => _qty = {..._qty, id: v}),
          available: _available,
          emptyHint: _fromId != null
              ? 'Nothing in stock at this store. Stock reaches a project site only after the destination confirms a transfer into it.'
              : 'Choose where the material comes from first.',
        ),
      kFieldGap,
      AppTextField(controller: _notes, label: 'Notes'),
      const SizedBox(height: 18),
      _InlineError(_err),
      SubmitButton(
        label: 'Review $_mode${n > 1 ? ' ($n items)' : ''}',
        icon: Icons.fact_check_outlined,
        onPressed: _goToReview,
      ),
      const SizedBox(height: 10),
      Text(
        'Admin requests post immediately. Site Engineer and Project Manager requests wait for approval (Approvals tab).',
        style: tt.bodySmall,
      ),
    ]);
  }

  Widget _review(BuildContext context) {
    final d = widget.data;
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final items = _cartItems(_qty);
    final fromName = _fromLoc?['name']?.toString() ?? '—';
    final (destKind, destId) = _mode == 'Issue'
        ? ('p', _chargeProjectId)
        : (_toDest.split(':').first, int.tryParse(_toDest.split(':').last));
    final toIsProject = destKind == 'p';
    final toName = toIsProject
        ? (_find(d.pickable, destId)?['name'] ?? _find(d.projects, destId)?['name'] ?? '—').toString()
        : (_find(d.locations, destId)?['name'] ?? '—').toString();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _SectionTitle(Icons.swap_horiz, 'Confirm $_mode'),
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Eyebrow('From'),
                const SizedBox(height: 4),
                Text(fromName, style: tt.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.arrow_forward, size: 18, color: p.fgSubtle),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Eyebrow(toIsProject ? 'To Project' : 'To Warehouse'),
                const SizedBox(height: 4),
                Text(toName, style: tt.titleSmall, textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Divider(height: 1, color: p.border),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Expanded(child: Text(d.materialName(it['material_id']), style: tt.bodyMedium)),
                Text('${qty(it['quantity'])} ${d.unitOf(it['material_id'])}',
                    style: tabular(tt.bodyMedium).copyWith(fontWeight: FontWeight.w600)),
              ]),
            ),
          if (_notes.text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Note: ${_notes.text}', style: tt.bodySmall),
          ],
          if (_mode == 'Transfer') ...[
            const SizedBox(height: 8),
            Text(
              'Stock leaves the source once this is approved and stays In Transit until the destination confirms receipt.',
              style: tt.bodySmall,
            ),
          ],
        ]),
      ),
      const SizedBox(height: 18),
      _InlineError(_err),
      SubmitButton(label: 'Confirm & Submit', icon: Icons.check, busy: _saving, onPressed: _confirmSubmit),
      const SizedBox(height: 10),
      SizedBox(
        height: 48,
        child: OutlinedButton(
          onPressed: _saving ? null : () => setState(() => _reviewing = false),
          child: const Text('Back'),
        ),
      ),
    ]);
  }
}
