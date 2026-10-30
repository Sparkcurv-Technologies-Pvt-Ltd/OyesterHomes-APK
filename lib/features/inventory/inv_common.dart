part of 'inventory_screen.dart';

// Shared pieces of the inventory screen: the loaded data, batch grouping, grouped pickers,
// the cart list with its quantity steppers, and CSV export.

typedef _Json = Map<String, dynamic>;

List<_Json> _list(dynamic v) => (v as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

_Json? _find(List<_Json> xs, dynamic id) {
  if (id == null) return null;
  for (final x in xs) {
    if (x['id'] == id) return x;
  }
  return null;
}

String _locLabel(_Json l) => (l['label'] ?? l['name'] ?? '').toString();

/// Everything the page loads up front (web: the inv-materials / inv-locations / inv-projects /
/// projectOptions / inv-stock / inv-movements queries).
class _InvData {
  final List<_Json> materials, locations, stock, movements;

  /// Every project, to name rows (stock from any company).
  final List<_Json> projects;

  /// Projects in the header's company / branch, for the pickers.
  final List<_Json> pickable;

  const _InvData({
    required this.materials,
    required this.locations,
    required this.projects,
    required this.pickable,
    required this.stock,
    required this.movements,
  });

  _Json? material(dynamic id) => _find(materials, id);
  String materialName(dynamic id) => material(id)?['name']?.toString() ?? '#$id';
  String unitOf(dynamic id) => (material(id)?['unit'] ?? '').toString();

  String locationName(dynamic id) {
    final l = _find(locations, id);
    if (l != null) return _locLabel(l);
    return id != null ? '#$id' : '—';
  }

  String projectName(dynamic id) => _find(projects, id)?['name']?.toString() ?? (id != null ? '#$id' : '—');

  List<_Json> get warehouses => locations.where((l) => l['location_type'] == 'Warehouse').toList();
  List<_Json> get sites => locations.where((l) => l['location_type'] != 'Warehouse').toList();

  int countBatches(bool Function(_Json) pick) => movements.where(pick).map(_batchKey).toSet().length;
}

// Rows submitted together as one cart share a batch_id and are decided as one.
String _batchKey(_Json m) => (m['batch_id'] as String?)?.isNotEmpty == true ? m['batch_id'] as String : 'single-${m['id']}';

class _Batch {
  final String key;
  final int id;
  final List<_Json> lines = [];
  _Batch(this.key, this.id);
  _Json get first => lines.first;
}

List<_Batch> _groupBatches(Iterable<_Json> rows) {
  final groups = <String, _Batch>{};
  for (final m in rows) {
    groups.putIfAbsent(_batchKey(m), () => _Batch(_batchKey(m), m['id'] as int)).lines.add(m);
  }
  return groups.values.toList();
}

/// Warehouses first, then project site stores (web LocationOptions). Values are location ids as strings.
List<(String, List<(String, String)>)> _locationGroups(_InvData d) => [
      ('Warehouses', [for (final l in d.warehouses) ('${l['id']}', _locLabel(l))]),
      ('Project sites', [for (final l in d.sites) ('${l['id']}', _locLabel(l))]),
    ];

/// A select with group headings (the web's <optgroup>). String values; [noneLabel] is the "" option.
class _GroupedDropdown extends StatelessWidget {
  final String label;
  final String value;
  final String? noneLabel;
  final List<(String, List<(String, String)>)> groups;
  final ValueChanged<String>? onChanged;
  final bool requiredField;
  const _GroupedDropdown({
    required this.label,
    required this.value,
    required this.groups,
    required this.onChanged,
    this.noneLabel,
    this.requiredField = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final items = <DropdownMenuItem<String>>[];
    final labels = <String, String>{};
    if (noneLabel != null) {
      labels[''] = noneLabel!;
      items.add(DropdownMenuItem(value: '', child: Text(noneLabel!, style: TextStyle(color: p.fgMuted))));
    }
    for (var i = 0; i < groups.length; i++) {
      final (heading, options) = groups[i];
      if (options.isEmpty) continue;
      labels['#h$i'] = heading;
      items.add(DropdownMenuItem(value: '#h$i', enabled: false, child: Eyebrow(heading, color: p.accentText)));
      for (final (v, l) in options) {
        labels[v] = l;
        items.add(DropdownMenuItem(
          value: v,
          child: Padding(padding: const EdgeInsets.only(left: 10), child: Text(l, overflow: TextOverflow.ellipsis)),
        ));
      }
    }
    final has = items.any((e) => e.value == value);
    return DropdownButtonFormField<String>(
      value: has ? value : (noneLabel != null ? '' : null),
      isExpanded: true,
      menuMaxHeight: 420,
      borderRadius: BorderRadius.circular(Radii.card),
      dropdownColor: p.card,
      decoration: InputDecoration(labelText: requiredField ? '$label *' : label),
      selectedItemBuilder: (_) => [
        for (final it in items)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(labels[it.value] ?? '', overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
      ],
      items: items,
      onChanged: onChanged == null
          ? null
          : (v) {
              if (v != null && !v.startsWith('#h')) onChanged!(v);
            },
    );
  }
}

/// Quantity stepper: −, a numeric field, +. Never below 0; rounded to 2 decimals (web QtyStepper).
class _QtyStepper extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _QtyStepper({required this.value, required this.onChanged});

  @override
  State<_QtyStepper> createState() => _QtyStepperState();
}

class _QtyStepperState extends State<_QtyStepper> {
  late final TextEditingController _c = TextEditingController(text: _fmt(widget.value));

  static String _fmt(double v) => v == 0 ? '' : inputNum(v);

  @override
  void didUpdateWidget(covariant _QtyStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((toNumOrNull(_c.text) ?? 0) != widget.value) {
      final t = _fmt(widget.value);
      _c.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final btn = IconButton.styleFrom(minimumSize: const Size(48, 48), padding: EdgeInsets.zero);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton.outlined(
        tooltip: 'Decrease',
        style: btn,
        onPressed: v <= 0 ? null : () => widget.onChanged((v - 1) < 0 ? 0 : (((v - 1) * 100).round() / 100)),
        icon: const Icon(Icons.remove, size: 20),
      ),
      const SizedBox(width: 6),
      SizedBox(
        width: 68,
        child: TextField(
          controller: _c,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
          style: tabular(Theme.of(context).textTheme.bodyLarge).copyWith(fontWeight: FontWeight.w600),
          decoration: const InputDecoration(hintText: '0', isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 13, horizontal: 4)),
          onChanged: (s) {
            final n = ((toNumOrNull(s) ?? 0) * 100).round() / 100;
            widget.onChanged(n < 0 ? 0 : n);
          },
        ),
      ),
      const SizedBox(width: 6),
      IconButton.outlined(
        tooltip: 'Increase',
        style: btn,
        onPressed: () => widget.onChanged(v + 1),
        icon: const Icon(Icons.add, size: 20),
      ),
    ]);
  }
}

/// Pick a quantity (and, with [showCost], a unit cost) for any number of materials in one go, like a cart:
/// every material listed, a stepper per row, only rows with qty > 0 are submitted (web MaterialCartList).
/// [available] (material id → quantity at the chosen source) limits the list to what is in stock there,
/// shows how much, and stops the quantity going above it.
class _MaterialCartList extends StatefulWidget {
  final List<_Json> materials;
  final Map<int, double> qtyMap;
  final void Function(int id, double qty) onQtyChange;
  final bool showCost;
  final Map<int, String>? costMap;
  final void Function(int id, String cost)? onCostChange;
  final Map<int, double>? available;
  final String? emptyHint;
  const _MaterialCartList({
    required this.materials,
    required this.qtyMap,
    required this.onQtyChange,
    this.showCost = false,
    this.costMap,
    this.onCostChange,
    this.available,
    this.emptyHint,
  });

  @override
  State<_MaterialCartList> createState() => _MaterialCartListState();
}

class _MaterialCartListState extends State<_MaterialCartList> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final avail = widget.available;
    final list = avail != null
        ? widget.materials.where((m) => (avail[m['id']] ?? 0) > 0).toList()
        : widget.materials;
    final q = _q.trim().toLowerCase();
    final shown = q.isEmpty
        ? list
        : list
            .where((m) =>
                '${m['name'] ?? ''}'.toLowerCase().contains(q) || '${m['category'] ?? ''}'.toLowerCase().contains(q))
            .toList();

    Widget message(String text) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
          child: Text(text, textAlign: TextAlign.center, style: tt.bodySmall),
        );

    final rows = <Widget>[
      for (final m in shown)
        Builder(builder: (context) {
          final id = m['id'] as int;
          final qv = widget.qtyMap[id] ?? 0;
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${m['name']}', style: tt.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('${dash(m['category'])} · ${m['unit'] ?? ''}', style: tt.bodySmall),
                    if (avail != null)
                      Text('In stock here: ${qty(avail[id])} ${m['unit'] ?? ''}',
                          style: tabular(tt.bodySmall).copyWith(color: p.success, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(width: 8),
                _QtyStepper(
                  value: qv,
                  onChanged: (v) {
                    final cap = avail?[id];
                    widget.onQtyChange(id, cap != null && v > cap ? cap : v);
                  },
                ),
              ]),
              if (widget.showCost && qv > 0) ...[
                const SizedBox(height: 10),
                AppTextField(
                  key: ValueKey('cart-cost-$id'),
                  label: 'Unit cost',
                  money: true,
                  initialValue: widget.costMap?[id],
                  onChanged: (v) => widget.onCostChange?.call(id, v),
                ),
              ],
            ]),
          );
        }),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (list.length > 6) ...[
        SearchField(hint: 'Search materials', onChanged: (v) => setState(() => _q = v)),
        const SizedBox(height: 10),
      ],
      RowGroup(
        margin: EdgeInsets.zero,
        children: [
          ...rows,
          if (avail != null && list.isEmpty) message(widget.emptyHint ?? 'Nothing in stock here.'),
          if (avail == null && widget.materials.isEmpty) message('No materials in the catalog yet.'),
          if (list.isNotEmpty && shown.isEmpty) message('No materials match "$_q".'),
        ],
      ),
    ]);
  }
}

/// The web's cartItems: only rows with qty > 0.
List<_Json> _cartItems(Map<int, double> qtyMap) => [
      for (final e in qtyMap.entries)
        if (e.value > 0) {'material_id': e.key, 'quantity': e.value},
    ];

/// Builds a CSV like the web's exportCsv and opens the share sheet for it.
Future<void> _shareCsv(BuildContext context, String name, List<String> cols, List<List<dynamic>> rows) async {
  String esc(dynamic v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
  final text = [cols.map(esc).join(','), ...rows.map((r) => r.map(esc).join(','))].join('\n');
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(text, flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')]);
  } catch (e) {
    if (context.mounted) showToast(context, errorText(e), error: true);
  }
}

/// Green confirm / approve button and red outlined decline / reject button (web emerald / red buttons).
class _DecisionButtons extends StatelessWidget {
  final String okLabel;
  final String noLabel;
  final bool busy;
  final VoidCallback onOk;
  final VoidCallback onNo;
  const _DecisionButtons({
    required this.okLabel,
    required this.noLabel,
    required this.busy,
    required this.onOk,
    required this.onNo,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final onGreen = p.dark ? Slate.s950 : Colors.white;
    return Row(children: [
      Expanded(
        flex: 3,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: p.success, foregroundColor: onGreen, minimumSize: const Size.fromHeight(48)),
          onPressed: busy ? null : onOk,
          icon: busy
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.fgMuted))
              : const Icon(Icons.check_circle_outline, size: 18),
          label: Text(okLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: p.danger,
            side: BorderSide(color: p.toneBorder(Tone.danger)),
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: busy ? null : onNo,
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: Text(noLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    ]);
  }
}

/// Small "label: value / sub" line used in register cards.
class _Meta extends StatelessWidget {
  final String label;
  final String? value;
  final String? sub;
  const _Meta(this.label, this.value, {this.sub});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(label, style: tt.bodySmall)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dash(value), style: tt.bodyMedium?.copyWith(color: value == null ? p.fgSubtle : null)),
            if (sub != null && sub!.isNotEmpty) Text(sub!, style: tabular(tt.bodySmall)),
          ]),
        ),
      ]),
    );
  }
}

/// Inline error under a sheet form (toasts sit behind an open bottom sheet).
class _InlineError extends StatelessWidget {
  final String? text;
  const _InlineError(this.text);

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.danger, fontWeight: FontWeight.w600)),
    );
  }
}
