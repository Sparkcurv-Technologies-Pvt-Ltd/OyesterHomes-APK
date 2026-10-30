import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '_shared.dart';

/// What arrived against a PO, how much and when (web PODeliveries.jsx). The PO only closes once every
/// line is fully received, or when the Admin closes it early with a reason.
class PODeliveries extends StatelessWidget {
  final Map<String, dynamic> po;
  final List<Map<String, dynamic>> log;
  final ValueChanged<Map<String, dynamic>> onChanged;
  const PODeliveries({super.key, required this.po, required this.log, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final status = po['status'];
    if (status == 'DRAFT' || status == 'CANCELLED') return const SizedBox.shrink();
    final user = context.watch<AuthProvider>().user;
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final d = asMap(po['delivery']) ?? {};
    final items = asMaps(po['items']);
    final issued = status == 'ISSUED' || status == 'SENT';
    final canReceive = issued && d['closed'] != true;
    final pct = toNum(d['received_pct']);

    final String explain;
    if (d['short_closed'] == true) {
      explain = 'Closed early by the Admin${d['short_closed_at'] != null ? ' on ${fmtDate(d['short_closed_at'])}' : ''}: '
          '${d['short_close_reason'] ?? ''}';
    } else if (d['closed'] == true) {
      explain = 'Everything ordered has arrived — this PO is closed.';
    } else {
      explain = "The PO stays open until every item has fully arrived. Deliveries go into the site store's stock.";
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('Deliveries',
          trailing: StatusChip(null,
              label: '${d['status'] ?? ''} · ${qty(pct)}%',
              tone: d['closed'] == true ? Tone.success : (pct > 0 ? Tone.warning : Tone.neutral),
              dense: true)),
      Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.local_shipping_outlined, size: 18, color: p.accentText),
          const SizedBox(width: 10),
          Expanded(child: Text(explain, style: tt.bodySmall)),
        ]),
      ),
      RowGroup(children: [
        for (final i in items)
          RowTile(
            title: dash(i['item_name']),
            subtitle: 'Ordered ${qty(i['quantity'])} · Received ${qty(i['received_qty'])}',
            trailing: toNum(i['pending_qty']) > 0
                ? Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    Text(qty(i['pending_qty']), style: tabular(tt.titleSmall).copyWith(color: p.warning)),
                    Text('still to come', style: tt.bodySmall),
                  ])
                : Icon(Icons.check, color: p.success),
          ),
      ]),
      if (canReceive)
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 0),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            SmallAction(
                label: 'Record a delivery', icon: Icons.inventory_2_outlined, filled: true, onPressed: () => _receive(context)),
            if (user?.role == 'Admin')
              SmallAction(label: 'Close PO early', icon: Icons.block, onPressed: () => _shortClose(context, pct)),
          ]),
        ),
      if (log.isNotEmpty) ...[
        const SectionHeader('Delivery log'),
        RowGroup(children: [
          for (final x in log)
            RowTile(
              title: '${dash(x['item_name'])} × ${qty(x['quantity'])}',
              subtitle: [
                fmtDate(x['received_on']),
                if ((x['notes'] ?? '').toString().isNotEmpty) x['notes'].toString(),
                if (x['received_by'] != null) x['received_by'].toString(),
              ].join(' · '),
            ),
        ]),
      ],
    ]);
  }

  Future<void> _receive(BuildContext context) async {
    final res = await showAppSheet<Map<String, dynamic>>(context,
        title: 'Record a delivery',
        subtitle: 'Enter how much of each item arrived. Leave an item at 0 if it did not come.',
        builder: (ctx) => _ReceiveForm(po: po));
    if (res != null) onChanged(res);
  }

  Future<void> _shortClose(BuildContext context, double pct) async {
    final res = await showAppSheet<Map<String, dynamic>>(context,
        title: 'Close this PO early?',
        subtitle:
            '${qty(pct)}% has arrived. Closing means the rest will not be received against this PO. This needs a reason.',
        builder: (ctx) => _ShortCloseForm(poId: po['id'] as int));
    if (res != null) onChanged(res);
  }
}

class _ReceiveForm extends StatefulWidget {
  final Map<String, dynamic> po;
  const _ReceiveForm({required this.po});

  @override
  State<_ReceiveForm> createState() => _ReceiveFormState();
}

class _ReceiveFormState extends State<_ReceiveForm> {
  late final List<Map<String, dynamic>> _pending =
      asMaps(widget.po['items']).where((i) => toNum(i['pending_qty']) > 0).toList();
  late final Map<int, TextEditingController> _lines = {
    for (final i in _pending) i['id'] as int: TextEditingController(text: inputNum(i['pending_qty'])),
  };
  final _notes = TextEditingController();
  String? _on = todayIso();
  bool _toStock = true;
  int? _locationId;
  List<Map<String, dynamic>> _locations = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    try {
      final l = asMaps(await context.read<ApiClient>().get('/inventory/locations'));
      if (mounted) setState(() => _locations = l);
    } catch (_) {
      // The web falls back to an empty list: only the project's site store is offered.
    }
  }

  @override
  void dispose() {
    for (final c in _lines.values) {
      c.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final items = _lines.entries
        .where((e) => toNum(e.value.text) > 0)
        .map((e) => {'po_item_id': e.key, 'quantity': toNum(e.value.text)})
        .toList();
    if (items.isEmpty) {
      showToast(context, 'Enter what arrived', error: true);
      return;
    }
    setState(() => _busy = true);
    final api = context.read<ApiClient>();
    try {
      final data = asMap(await api.post('/quotation-purchase-orders/${widget.po['id']}/receipts', data: {
            'received_on': _on,
            'notes': _notes.text.isEmpty ? null : _notes.text,
            'items': items,
            'to_stock': _toStock,
            'location_id': _toStock ? _locationId : null,
          })) ??
          {};
      if (!mounted) return;
      final closed = asMap(data['delivery'])?['closed'] == true;
      showToast(context, closed ? 'All material received — PO closed' : 'Delivery recorded');
      Navigator.pop(context, data);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final projectId = widget.po['project_id'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final i in _pending) ...[
        AppTextField(
          controller: _lines[i['id'] as int],
          label: dash(i['item_name']),
          helper: '${qty(i['pending_qty'])} still to come',
          number: true,
        ),
        kFieldGap,
      ],
      DateField(
        label: 'Received on',
        value: _on,
        lastDate: DateTime.now(),
        onChanged: (v) => setState(() => _on = v),
      ),
      kFieldGap,
      AppTextField(controller: _notes, label: 'Note', hint: 'e.g. DC no. 4512'),
      const SizedBox(height: 8),
      SwitchRow(label: 'Add to stock', value: _toStock, onChanged: (v) => setState(() => _toStock = v)),
      if (_toStock)
        AppDropdown<int?>(
          label: 'Store',
          value: _locationId,
          items: [
            (null, "This project's site store"),
            for (final l in _locations.where((l) => l['project_id'] != projectId))
              (l['id'] as int, (l['label'] ?? l['name'] ?? '').toString()),
          ],
          onChanged: (v) => setState(() => _locationId = v),
        ),
      const SizedBox(height: 8),
      Text(
          'It goes into stock at the PO price, marked as paid through this PO — so issuing it to the work later does not count its cost a second time.',
          style: tt.bodySmall),
      const SizedBox(height: 18),
      SubmitButton(label: 'Save delivery', busy: _busy, onPressed: _save),
    ]);
  }
}

class _ShortCloseForm extends StatefulWidget {
  final int poId;
  const _ShortCloseForm({required this.poId});

  @override
  State<_ShortCloseForm> createState() => _ShortCloseFormState();
}

class _ShortCloseFormState extends State<_ShortCloseForm> {
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final api = context.read<ApiClient>();
    try {
      final data = asMap(await api.post('/quotation-purchase-orders/${widget.poId}/short-close', data: {'reason': _reason.text})) ?? {};
      if (!mounted) return;
      showToast(context, 'PO closed — nothing more will be received against it');
      Navigator.pop(context, data);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(
          controller: _reason,
          label: 'Reason',
          hint: 'e.g. Vendor out of stock, balance not needed',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        SubmitButton(
          label: 'Close PO',
          icon: Icons.block,
          busy: _busy,
          onPressed: _reason.text.trim().length < 3 ? null : _submit,
        ),
      ]);
}
