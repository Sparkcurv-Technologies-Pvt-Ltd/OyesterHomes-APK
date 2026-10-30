import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../procurement/vendor_forms.dart';
import '../shell/routes.dart';
import '_shared.dart';
import 'purchase_order_screen.dart';

/// Material requirements (web MaterialRequestsSection.jsx): Site Engineer raises → PM approves →
/// vendor quotes compared → PO (routers/material_flow.py). A non-scrolling Column placed in the
/// procurement screen's list.
class MaterialRequestsSection extends StatefulWidget {
  final int projectId;
  const MaterialRequestsSection({super.key, required this.projectId});

  @override
  State<MaterialRequestsSection> createState() => _MaterialRequestsSectionState();
}

const _nextStep = {
  'Pending': 'Waiting for the project manager to approve',
  'Approved': 'Approved — collect vendor quotes, compare and make the PO',
  'Ordered': 'PO placed — record deliveries on the PO as material arrives',
  'Received': 'All material received',
  'Rejected': 'Rejected',
  'Closed': 'PO closed early by the Admin — the rest is not coming',
};

Tone _statusTone(String? s) => switch (s) {
      'Pending' => Tone.warning,
      'Approved' => Tone.info,
      'Ordered' => Tone.accent,
      'Received' => Tone.success,
      'Rejected' => Tone.danger,
      _ => Tone.neutral,
    };

class _MaterialRequestsSectionState extends State<MaterialRequestsSection> {
  final _loader = GlobalKey<InlineAsyncState<Map<String, dynamic>>>();
  String _filter = 'open';

  Future<void> _reload() async => _loader.currentState?.reload();

  Future<void> _openPO(int quotationId) async {
    await push(context, PurchaseOrderScreen(projectId: widget.projectId, quotationId: quotationId));
    _reload();
  }

  Future<void> _decide(Map<String, dynamic> r, String verb) async {
    String? note;
    if (verb == 'reject') {
      note = await promptText(context, title: 'Reason for rejecting (optional)', label: 'Reason', confirmLabel: 'Reject');
      if (note == null) return;
    }
    if (!mounted) return;
    final api = context.read<ApiClient>();
    final ok = await runAction(context, () => api.post('/material-requests/${r['id']}/$verb', data: {'note': note}),
        success: verb == 'approve' ? 'Approved' : 'Rejected');
    if (ok) _reload();
  }

  Future<void> _raise() async {
    final saved = await showAppSheet<bool>(context,
        title: 'Raise a material requirement',
        subtitle: 'What the site needs. The project manager approves it, then quotes are collected.',
        builder: (ctx) => _RaiseForm(projectId: widget.projectId));
    if (saved == true) _reload();
  }

  Future<void> _quote(Map<String, dynamic> r) async {
    final saved = await showAppSheet<bool>(context,
        title: 'Add a vendor quote · ${r['request_number']}',
        subtitle: "Enter the vendor's price per unit for each item. Add one quote per vendor, then compare.",
        builder: (ctx) => _QuoteForm(request: r));
    if (saved == true) _reload();
  }

  Future<void> _compare(Map<String, dynamic> r, bool canBuy) async {
    final madeFor = await showAppSheet<int>(context,
        title: 'Compare quotes · ${r['request_number']}',
        subtitle: 'Green is the lowest price for that item. The cheapest total is marked "Best price".',
        builder: (ctx) => _CompareView(request: r, canBuy: canBuy));
    if (!mounted) return;
    _reload();
    if (madeFor != null) _openPO(madeFor);
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SectionHeader('Material requirements',
          trailing: FilledButton.icon(
              onPressed: _raise, icon: const Icon(Icons.add, size: 18), label: const Text('Raise requirement'))),
      FilterBar<String>(
        value: _filter,
        options: const [('open', 'Open'), ('all', 'All')],
        onChanged: (v) => setState(() => _filter = v),
        padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
      ),
      InlineAsync<Map<String, dynamic>>(
        key: _loader,
        load: () async => asMap(await api.get('/projects/${widget.projectId}/material-requests')) ?? {},
        builder: (context, data, reload) {
          final rows = asMaps(data['requests'])
              .where((r) => _filter == 'all' || !['Received', 'Rejected', 'Closed'].contains(r['status']))
              .toList();
          final canApprove = data['can_approve'] == true;
          final canBuy = data['can_buy'] == true;
          if (rows.isEmpty) {
            return InlineNote(
                'No ${_filter == 'open' ? 'open ' : ''}requirements. The site engineer raises one when material is needed.');
          }
          return Column(children: [
            for (final r in rows)
              _RequestCard(
                r: r,
                canApprove: canApprove,
                canBuy: canBuy,
                onDecide: _decide,
                onQuote: _quote,
                onCompare: (r) => _compare(r, canBuy),
                onOpenPO: _openPO,
              ),
          ]);
        },
      ),
    ]);
  }
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> r;
  final bool canApprove;
  final bool canBuy;
  final void Function(Map<String, dynamic>, String) onDecide;
  final void Function(Map<String, dynamic>) onQuote;
  final void Function(Map<String, dynamic>) onCompare;
  final void Function(int) onOpenPO;
  const _RequestCard({
    required this.r,
    required this.canApprove,
    required this.canBuy,
    required this.onDecide,
    required this.onQuote,
    required this.onCompare,
    required this.onOpenPO,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final status = r['status'] as String?;
    final items = asMaps(r['items']);
    final po = asMap(r['purchase_order']);
    final quotes = toInt(r['quotes']);
    final meta = [
      _nextStep[status] ?? '',
      if (r['requested_by'] != null) 'raised by ${r['requested_by']}',
      if ((r['notes'] ?? '').toString().isNotEmpty) r['notes'].toString(),
      if ((r['decision_note'] ?? '').toString().isNotEmpty) '"${r['decision_note']}"',
    ].where((s) => s.isNotEmpty).join(' · ');

    return Surface(
      margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(dash(r['request_number']), style: tt.titleSmall),
          StatusChip(status, label: status, tone: _statusTone(status), dense: true),
          if (r['needed_by'] != null) Text('needed by ${fmtDate(r['needed_by'])}', style: tt.bodySmall),
        ]),
        const SizedBox(height: 6),
        Text(items.map((i) => '${i['product_name']} × ${qty(i['quantity'])} ${i['unit'] ?? ''}'.trim()).join(' · '),
            style: tt.bodyMedium),
        const SizedBox(height: 4),
        Text(meta, style: tt.bodySmall),
        if (po != null) ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: () => onOpenPO(po['quotation_id'] as int),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Text(dash(po['po_number']),
                    style: tt.labelLarge?.copyWith(color: p.accentText, decoration: TextDecoration.underline)),
                const SizedBox(width: 10),
                Expanded(
                  child: LevelBar(toNum(po['received_pct']) / 100,
                      tone: po['fully_received'] == true ? Tone.success : Tone.warning),
                ),
                const SizedBox(width: 10),
                Text('${qty(po['received_pct'])}% received', style: tabular(tt.bodySmall)),
              ]),
            ),
          ),
        ],
        if ((status == 'Pending' && canApprove) || (status == 'Approved' && canBuy) || quotes > 0) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (status == 'Pending' && canApprove) ...[
              SmallAction(
                  label: 'Approve', icon: Icons.check, filled: true, color: p.success, onPressed: () => onDecide(r, 'approve')),
              SmallAction(label: 'Reject', icon: Icons.close, onPressed: () => onDecide(r, 'reject')),
            ],
            if (status == 'Approved' && canBuy) SmallAction(label: 'Add quote', icon: Icons.add, onPressed: () => onQuote(r)),
            if (quotes > 0)
              SmallAction(
                  label: 'Compare $quotes',
                  icon: Icons.balance_outlined,
                  filled: status == 'Approved',
                  onPressed: () => onCompare(r)),
          ]),
        ],
      ]),
    );
  }
}

// ───────────────────────────────────────────── raise a requirement

class _RaiseForm extends StatefulWidget {
  final int projectId;
  const _RaiseForm({required this.projectId});

  @override
  State<_RaiseForm> createState() => _RaiseFormState();
}

class _RaiseFormState extends State<_RaiseForm> {
  List<Map<String, dynamic>>? _products;
  Object? _error;
  final List<Map<String, dynamic>> _rows = [];
  String? _neededBy;
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = asMaps(await context.read<ApiClient>().get('/products'));
      if (mounted) {
        setState(() {
          _products = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Map<String, dynamic>? _product(int? id) => (_products ?? []).where((p) => p['id'] == id).firstOrNull;

  Future<void> _edit([int? index]) async {
    final res = await showProductLineSheet(context,
        title: index == null ? 'Add item' : 'Edit item',
        products: _products ?? [],
        line: index == null ? null : _rows[index],
        withPrice: false,
        canRemove: index != null,
        productLabel: 'Material');
    if (res == null || !mounted) return;
    setState(() {
      if (res['remove'] == true) {
        _rows.removeAt(index!);
      } else if (index == null) {
        _rows.add(res);
      } else {
        _rows[index] = res;
      }
    });
  }

  Future<void> _newMaterial() async {
    final p = await showProductForm(context);
    if (p != null && mounted) await _load();
  }

  Future<void> _submit() async {
    final items = _rows
        .where((r) => r['product_id'] != null && toNum(r['quantity']) > 0)
        .map((r) => {'product_id': r['product_id'], 'quantity': toNum(r['quantity'])})
        .toList();
    if (items.isEmpty) {
      showToast(context, 'Add at least one item with a quantity', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final data = asMap(await context.read<ApiClient>().post('/projects/${widget.projectId}/material-requests', data: {
            'items': items,
            'needed_by': _neededBy,
            'notes': _notes.text.isEmpty ? null : _notes.text,
          })) ??
          {};
      if (!mounted) return;
      showToast(context, '${data['request_number']} sent to the project manager');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(message: errorText(_error), onRetry: _load);
    if (_products == null) return const LoadingView();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_rows.isEmpty)
        const InlineNote('No items yet.', margin: EdgeInsets.zero)
      else
        RowGroup(margin: EdgeInsets.zero, children: [
          for (var i = 0; i < _rows.length; i++)
            RowTile(
              onTap: () => _edit(i),
              title: dash(_product(_rows[i]['product_id'] as int?)?['name']),
              trailing: Text('${qty(_rows[i]['quantity'])} ${_product(_rows[i]['product_id'] as int?)?['unit'] ?? ''}',
                  style: tabular(Theme.of(context).textTheme.titleSmall)),
            ),
        ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
            child: OutlinedButton.icon(
                onPressed: () => _edit(), icon: const Icon(Icons.add, size: 18), label: const Text('Add item'))),
        const SizedBox(width: 8),
        OutlinedButton.icon(onPressed: _newMaterial, icon: const Icon(Icons.add, size: 18), label: const Text('New material')),
      ]),
      const SizedBox(height: 16),
      DateField(label: 'Needed by', value: _neededBy, onChanged: (v) => setState(() => _neededBy = v)),
      kFieldGap,
      AppTextField(controller: _notes, label: 'Note', hint: 'e.g. for 2nd floor slab'),
      const SizedBox(height: 18),
      SubmitButton(label: 'Send for approval', busy: _busy, onPressed: _submit),
    ]);
  }
}

// ───────────────────────────────────────────── add a vendor quote

class _QuoteForm extends StatefulWidget {
  final Map<String, dynamic> request;
  const _QuoteForm({required this.request});

  @override
  State<_QuoteForm> createState() => _QuoteFormState();
}

class _QuoteFormState extends State<_QuoteForm> {
  List<Map<String, dynamic>>? _vendors;
  Object? _error;
  int? _vendorId;
  String? _validUntil;
  late final List<Map<String, dynamic>> _items = asMaps(widget.request['items']);
  late final Map<int, TextEditingController> _prices = {
    for (final i in _items) i['product_id'] as int: TextEditingController(),
  };
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _prices.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool prefill = true}) async {
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait([api.get('/vendors'), api.get('/products')]);
      if (!mounted) return;
      final products = asMaps(res[1]);
      setState(() {
        _vendors = asMaps(res[0]);
        _error = null;
        if (prefill) {
          for (final i in _items) {
            final dp = products.where((p) => p['id'] == i['product_id']).firstOrNull?['default_price'];
            _prices[i['product_id'] as int]!.text = dp == null ? '' : inputNum(dp);
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _newVendor() async {
    final v = await showVendorForm(context);
    if (v == null || !mounted) return;
    await _load(prefill: false);
    if (mounted && v['id'] is int) setState(() => _vendorId = v['id'] as int);
  }

  double get _total =>
      _items.fold(0.0, (s, i) => s + toNum(i['quantity']) * toNum(_prices[i['product_id'] as int]!.text));

  Future<void> _submit() async {
    if (_vendorId == null) {
      showToast(context, 'Pick the vendor', error: true);
      return;
    }
    if (_items.any((i) => _prices[i['product_id'] as int]!.text.trim().isEmpty)) {
      showToast(context, 'Enter a price for every item', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post('/material-requests/${widget.request['id']}/quotations', data: {
        'vendor_id': _vendorId,
        'valid_until': _validUntil,
        'prices': [
          for (final i in _items) {'product_id': i['product_id'], 'unit_price': toNum(_prices[i['product_id'] as int]!.text)},
        ],
      });
      if (!mounted) return;
      showToast(context, 'Quote added');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(message: errorText(_error), onRetry: _load);
    if (_vendors == null) return const LoadingView();
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppDropdown<int>(
        label: 'Vendor',
        hint: 'Choose…',
        value: _vendorId,
        items: [
          for (final v in _vendors!)
            (v['id'] as int, '${v['name']}${(v['trade'] ?? '').toString().isNotEmpty ? ' — ${v['trade']}' : ''}'),
        ],
        onChanged: (v) => setState(() => _vendorId = v),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(onPressed: _newVendor, child: Text('+ New vendor', style: TextStyle(color: p.accentText))),
      ),
      DateField(label: 'Valid until', value: _validUntil, onChanged: (v) => setState(() => _validUntil = v)),
      const SizedBox(height: 18),
      const Eyebrow('Items'),
      const SizedBox(height: 8),
      for (final i in _items) ...[
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dash(i['product_name']), style: tt.titleSmall),
              Text('${qty(i['quantity'])} ${i['unit'] ?? ''}', style: tabular(tt.bodySmall)),
              Text(inr(toNum(i['quantity']) * toNum(_prices[i['product_id'] as int]!.text)), style: tabular(tt.bodySmall)),
            ]),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 140,
            child: AppTextField(
              controller: _prices[i['product_id'] as int],
              label: 'Rate ₹',
              money: true,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
        kFieldGap,
      ],
      Row(children: [
        Text('Total', style: tt.bodyMedium),
        const Spacer(),
        Text(inr(_total), style: tabular(tt.titleMedium).copyWith(fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 14),
      SubmitButton(label: 'Save quote', busy: _busy, onPressed: _submit),
    ]);
  }
}

// ───────────────────────────────────────────── compare quotes

/// Pops with the quotation id a PO was just made from, so the section can open that PO.
class _CompareView extends StatefulWidget {
  final Map<String, dynamic> request;
  final bool canBuy;
  const _CompareView({required this.request, required this.canBuy});

  @override
  State<_CompareView> createState() => _CompareViewState();
}

class _CompareViewState extends State<_CompareView> {
  Map<String, dynamic>? _data;
  Object? _error;
  int? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = asMap(await context.read<ApiClient>().get('/material-requests/${widget.request['id']}/comparison'));
      if (mounted) {
        setState(() {
          _data = d ?? {};
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _makePO(Map<String, dynamic> q) async {
    final ok = await confirmDialog(context,
        title: 'Make the purchase order from ${q['vendor']} for ${inr(q['total'])}?', confirmLabel: 'Make PO');
    if (!ok || !mounted) return;
    setState(() => _busy = q['quotation_id'] as int);
    try {
      await context.read<ApiClient>().post('/quotations/${q['quotation_id']}/purchase-order');
      if (!mounted) return;
      showToast(context, 'PO made for ${q['vendor']}');
      Navigator.pop(context, q['quotation_id'] as int);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(message: errorText(_error), onRetry: _load);
    if (_data == null) return const LoadingView();
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final d = _data!;
    final quotes = asMaps(d['quotes']);
    final items = asMaps(d['items']);
    final lowest = d['lowest_quotation_id'];
    final perItem = asMap(d['lowest_per_item']) ?? {};
    final reqStatus = asMap(d['request'])?['status'];

    if (quotes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: InlineNote('No quotes yet — add one per vendor first.', margin: EdgeInsets.zero),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final q in quotes) ...[
        Surface(
          borderColor: q['quotation_id'] == lowest ? p.toneBorder(Tone.success) : null,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(dash(q['vendor']), style: tt.titleSmall)),
              if (q['quotation_id'] == lowest) const StatusChip(null, label: 'Best price', tone: Tone.success, dense: true),
            ]),
            const SizedBox(height: 6),
            for (final i in items)
              Builder(builder: (context) {
                final best = perItem[i['product_id'].toString()] == q['quotation_id'];
                final price = asMap(q['prices'])?[i['product_id'].toString()];
                return KeyValueRow(
                  '${dash(i['name'])} · ${qty(i['quantity'])} ${i['unit'] ?? ''}',
                  inr(price, forceDecimals: true),
                  valueColor: best ? p.success : null,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                );
              }),
            const Divider(height: 16),
            KeyValueRow('Total', inr(q['total']),
                strong: true, valueColor: q['quotation_id'] == lowest ? p.success : null, padding: EdgeInsets.zero),
            if (asMap(q['po']) != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, q['quotation_id'] as int),
                  child: Text('${asMap(q['po'])!['po_number']} →', style: TextStyle(color: p.accentText)),
                ),
              ),
            ] else if (widget.canBuy && reqStatus == 'Approved') ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                child: q['quotation_id'] == lowest
                    ? FilledButton(
                        onPressed: _busy == q['quotation_id'] ? null : () => _makePO(q), child: const Text('Make PO'))
                    : OutlinedButton(
                        onPressed: _busy == q['quotation_id'] ? null : () => _makePO(q), child: const Text('Make PO')),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }
}
