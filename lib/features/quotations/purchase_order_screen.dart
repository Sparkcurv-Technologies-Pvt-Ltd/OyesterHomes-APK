import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../auth/user.dart';
import '_po_deliveries.dart';
import '_shared.dart';

/// The purchase order made from a quotation (web PurchaseOrderPage.jsx + PODeliveries.jsx): opens the
/// active PO or drafts one, edits lines / discount / tax / notes, issues it, PDF, email / WhatsApp,
/// cancel, vendor payments and deliveries into stock.
class PurchaseOrderScreen extends StatefulWidget {
  final int projectId;
  final int quotationId;
  const PurchaseOrderScreen({super.key, required this.projectId, required this.quotationId});

  @override
  State<PurchaseOrderScreen> createState() => _PurchaseOrderScreenState();
}

/// Money on this page always shows paise (web `fmt` with 2 fraction digits).
String _fmt(dynamic v) => inr(v, forceDecimals: true);

class _PurchaseOrderScreenState extends State<PurchaseOrderScreen> {
  Map<String, dynamic>? _po;
  Map<String, dynamic>? _quotation;
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _receipts = [];
  bool _loading = true;
  bool _missing = false;
  Object? _error;

  // Editable copy of the PO (web `items`, `discount`, `tax`, `notes`).
  List<Map<String, dynamic>> _items = [];
  final _discount = TextEditingController();
  final _tax = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;

  /// Set from `context.watch` in build; read outside build (bootstrap) falls back to the provider.
  AppUser? _user;
  AppUser? get _me => _user ?? context.read<AuthProvider>().user;
  bool get _canWrite => _me?.roleIn(['Admin', 'ProjectManager', 'ProcurementOfficer', 'Accountant']) ?? false;
  bool get _canPay => _me?.roleIn(['Admin', 'Accountant']) ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _discount.dispose();
    _tax.dispose();
    _notes.dispose();
    super.dispose();
  }

  ApiClient get _api => context.read<ApiClient>();

  /// Load the active PO for this quotation, or draft one (only buyers may draft).
  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final quotation = _api.get('/quotations/${widget.quotationId}').then(asMap).catchError((_) => null);
      var data = asMap(await _api.get('/quotations/${widget.quotationId}/purchase-order'));
      if (data == null && !_canWrite) {
        if (mounted) setState(() => _missing = true);
        return;
      }
      if (data == null) {
        data = asMap(await _api.post('/quotations/${widget.quotationId}/purchase-order'))!;
        if (mounted) showToast(context, 'Purchase Order ${data['po_number']} drafted from quotation');
      }
      _quotation = await quotation;
      if (!mounted) return;
      _applyPO(data);
      await _loadSide();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Payments and the delivery log; each is optional (role-gated on the server), as on the web.
  Future<void> _loadSide() async {
    final id = _po?['id'];
    if (id == null) return;
    final res = await Future.wait([
      _api.get('/quotation-purchase-orders/$id/payments').then((r) => asMaps(asMap(r)?['payments'])).catchError((_) => _payments),
      _api.get('/quotation-purchase-orders/$id/receipts').then(asMaps).catchError((_) => _receipts),
    ]);
    if (!mounted) return;
    setState(() {
      _payments = res[0];
      _receipts = res[1];
    });
  }

  void _applyPO(Map<String, dynamic> data) {
    setState(() {
      _po = data;
      _items = asMaps(data['items'])
          .map((it) => {
                'id': it['id'],
                'quotation_item_id': it['quotation_item_id'],
                'item_name': (it['item_name'] ?? '').toString(),
                'description': (it['description'] ?? '').toString(),
                'quantity': inputNum(it['quantity']),
                'unit_price': inputNum(it['unit_price']),
              })
          .toList();
      _discount.text = inputNum(toNum(data['discount']));
      _tax.text = inputNum(toNum(data['tax']));
      _notes.text = (data['notes'] ?? '').toString();
    });
  }

  Future<void> _applyAndRefresh(Map<String, dynamic> data) async {
    _applyPO(data);
    await _loadSide();
  }

  double get _subtotal => _items.fold(0.0, (s, it) => s + toNum(it['quantity']) * toNum(it['unit_price']));
  double get _grand {
    final g = _subtotal - toNum(_discount.text) + toNum(_tax.text);
    return g < 0 ? 0 : g;
  }

  bool _validate() {
    String? err;
    if (_items.isEmpty) {
      err = 'Add at least one item';
    } else {
      for (final it in _items) {
        if ((it['item_name'] as String).trim().isEmpty) {
          err = 'Every item needs a name';
        } else if (toNum(it['quantity']) <= 0) {
          err = 'Quantity must be greater than 0';
        } else if (toNum(it['unit_price']) < 0) {
          err = 'Unit price cannot be negative';
        }
        if (err != null) break;
      }
    }
    if (err == null && toNum(_discount.text) < 0) err = 'Discount cannot be negative';
    if (err == null && toNum(_tax.text) < 0) err = 'Tax cannot be negative';
    if (err != null) showToast(context, err, error: true);
    return err == null;
  }

  Future<Map<String, dynamic>?> _save({bool issue = false}) async {
    if (!_validate()) return null;
    setState(() => _saving = true);
    try {
      final payload = {
        'discount': toNum(_discount.text),
        'tax': toNum(_tax.text),
        'notes': _notes.text,
        'items': [
          for (final it in _items)
            {
              'quotation_item_id': it['quotation_item_id'],
              'item_name': (it['item_name'] as String).trim(),
              'description': (it['description'] as String).isEmpty ? null : it['description'],
              'quantity': toNum(it['quantity']),
              'unit_price': toNum(it['unit_price']),
            }
        ],
        if (issue) 'status': 'ISSUED',
      };
      final data = asMap(await _api.put('/quotation-purchase-orders/${_po!['id']}', data: payload))!;
      if (!mounted) return null;
      _applyPO(data);
      showToast(context, issue ? 'Purchase Order issued' : 'Draft saved');
      _loadSide();
      return data;
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _issueAndPreview() async {
    final saved = await _save(issue: true);
    if (saved != null && mounted) await _openPdf(saved);
  }

  Future<void> _openPdf(Map<String, dynamic> po) =>
      downloadAndOpen(context, _api, '/quotation-purchase-orders/${po['id']}/pdf', fallbackName: '${po['po_number']}.pdf');

  Future<void> _sharePdf(Map<String, dynamic> po) => downloadAndShare(context, _api, '/quotation-purchase-orders/${po['id']}/pdf',
      params: {'download': 1}, fallbackName: '${po['po_number']}.pdf');

  Future<void> _cancel() async {
    final ok = await confirmWithLabels(context,
        title: 'Cancel Purchase Order?',
        message:
            'Are you sure you want to cancel this purchase order? This cannot be undone — but the record will remain visible with a Cancelled badge.',
        confirmLabel: 'Yes, Cancel',
        cancelLabel: 'Keep PO',
        destructive: true);
    if (!ok || !mounted) return;
    try {
      final data = asMap(await _api.post('/quotation-purchase-orders/${_po!['id']}/cancel'))!;
      if (!mounted) return;
      _applyPO(data);
      showToast(context, 'Purchase Order cancelled');
      // The web goes back to the quotation; re-opening this screen would draft a fresh PO.
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    }
  }

  Future<void> _send(String channel) async {
    final vendor = asMap(_po!['vendor']) ?? {};
    final res = await showAppSheet<Map<String, dynamic>>(context,
        title: channel == 'email' ? 'Send via Email' : 'Send via WhatsApp',
        subtitle: 'Contact is read live from the vendor record.',
        builder: (ctx) => _POSendForm(poId: _po!['id'] as int, channel: channel, vendor: vendor));
    if (res != null && mounted) _applyAndRefresh(res);
  }

  Future<void> _pay() async {
    final res = await showAppSheet<Map<String, dynamic>>(context,
        title: 'Record Vendor Payment',
        subtitle:
            'Against ${_po!['po_number']} — ${asMap(_po!['vendor'])?['name'] ?? ''}. Balance due ${_fmt(_po!['balance_due'])}. Appears on the project balance sheet.',
        builder: (ctx) => _POPaymentForm(po: _po!));
    if (res != null && mounted) _applyAndRefresh(res);
  }

  Future<void> _editItem([int? index]) async {
    final res = await showAppSheet<Map<String, dynamic>>(context,
        title: index == null ? 'Add Item' : 'Edit Item',
        builder: (ctx) => _POItemForm(item: index == null ? null : _items[index], canRemove: index != null && _items.length > 1));
    if (res == null || !mounted) return;
    setState(() {
      if (res['remove'] == true) {
        _items.removeAt(index!);
      } else if (index == null) {
        _items.add(res);
      } else {
        _items[index] = {..._items[index], ...res};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _user = context.watch<AuthProvider>().user;
    final po = _po;
    final issuedOrSent = po != null && (po['status'] == 'ISSUED' || po['status'] == 'SENT');
    final readOnly = po == null || _isReadOnly(po);

    Widget body;
    if (_missing) {
      body = EmptyState(
        icon: Icons.description_outlined,
        title: 'No purchase order has been made from this quotation yet.',
        action: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to procurement')),
      );
    } else if (_error != null && po == null) {
      body = ErrorRetry(message: errorText(_error), onRetry: _bootstrap);
    } else if (_loading && po == null) {
      body = const LoadingView(label: 'Loading purchase order…');
    } else {
      body = RefreshList(
        onRefresh: () async {
          final data = asMap(await _api.get('/quotation-purchase-orders/${po['id']}'));
          if (data != null && mounted) await _applyAndRefresh(data);
        },
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: _content(context, po!, readOnly),
      );
    }

    return AppScaffold(
      title: po?['po_number']?.toString() ?? 'Purchase Order',
      subtitle: 'Purchase Order',
      actions: [
        if (po != null && po['status'] != 'CANCELLED' && issuedOrSent) ...[
          IconButton(tooltip: 'Print', icon: const Icon(Icons.print_outlined), onPressed: () => _openPdf(po)),
          IconButton(tooltip: 'Download', icon: const Icon(Icons.download_outlined), onPressed: () => _sharePdf(po)),
        ],
      ],
      body: body,
      bottomBar: po == null || readOnly
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 8),
                child: Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton(
                          onPressed: _saving ? null : () => _save(), child: const Text('Save Draft')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SubmitButton(
                        label: 'Purchase Order', icon: Icons.verified_user_outlined, busy: _saving, onPressed: _issueAndPreview),
                  ),
                ]),
              ),
            ),
    );
  }

  /// Once material has arrived the PO's lines are fixed (the server refuses edits and cancelling).
  bool _isReadOnly(Map<String, dynamic> po) {
    final delivered = toNum(asMap(po['delivery'])?['received_pct']) > 0;
    return po['status'] == 'CANCELLED' || !_canWrite || delivered;
  }

  List<Widget> _content(BuildContext context, Map<String, dynamic> po, bool readOnly) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final vendor = asMap(po['vendor']) ?? {};
    final status = po['status'];
    final canEmail = (vendor['email'] ?? '').toString().trim().isNotEmpty;
    final canWhatsapp = (vendor['phone'] ?? '').toString().trim().isNotEmpty;
    final paid = toNum(po['amount_paid']);
    final balance = toNum(po['balance_due']);
    final issuedOrSent = status == 'ISSUED' || status == 'SENT';

    return [
      // Header
      Surface(
        margin: const EdgeInsets.symmetric(horizontal: kGutter),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Eyebrow('Purchase Order', color: p.accentText),
          const SizedBox(height: 4),
          Text(dash(po['po_number']), style: tt.headlineMedium),
          const SizedBox(height: 6),
          Text('Ref: ${dash(po['quotation_number'])} · ${fmtDate(po['order_date'])}',
              style: tt.bodyMedium?.copyWith(color: p.fgMuted)),
          const SizedBox(height: 8),
          POStatusChip(status as String?),
          if (status == 'CANCELLED') ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: p.toneFill(Tone.danger),
                border: Border.all(color: p.toneBorder(Tone.danger)),
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Row(children: [
                Icon(Icons.block, size: 15, color: p.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Cancelled on ${fmtDateTime(po['cancelled_at'], empty: '')}',
                      style: tt.labelMedium?.copyWith(color: p.danger)),
                ),
              ]),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 10),
      // Vendor + project
      Surface(
        margin: const EdgeInsets.symmetric(horizontal: kGutter),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Eyebrow('Vendor'),
          const SizedBox(height: 4),
          Text(dash(vendor['name']), style: tt.titleMedium),
          if ((vendor['email'] ?? '').toString().isNotEmpty) Text('Email: ${vendor['email']}', style: tt.bodySmall),
          if ((vendor['phone'] ?? '').toString().isNotEmpty) Text('Phone: ${vendor['phone']}', style: tt.bodySmall),
          if ((vendor['address'] ?? '').toString().isNotEmpty) Text(vendor['address'].toString(), style: tt.bodySmall),
          const Divider(height: 24),
          const Eyebrow('Project'),
          const SizedBox(height: 4),
          Text(dash(po['project_name']), style: tt.titleMedium),
          if (_quotation?['status'] != null) Text('Quotation status: ${_quotation!['status']}', style: tt.bodySmall),
        ]),
      ),

      // Items
      SectionHeader('Items',
          trailing: readOnly
              ? null
              : TextButton.icon(onPressed: () => _editItem(), icon: const Icon(Icons.add, size: 18), label: const Text('Add Item'))),
      if (_items.isEmpty)
        const InlineNote('No items.')
      else
        RowGroup(children: [
          for (var i = 0; i < _items.length; i++)
            RowTile(
              onTap: readOnly ? null : () => _editItem(i),
              chevron: !readOnly,
              title: (_items[i]['item_name'] as String).isEmpty ? '—' : _items[i]['item_name'] as String,
              subtitle: [
                if ((_items[i]['description'] as String).isNotEmpty) _items[i]['description'] as String,
                '${qty(_items[i]['quantity'])} × ${_fmt(_items[i]['unit_price'])}',
              ].join('\n'),
              trailing: Text(_fmt(toNum(_items[i]['quantity']) * toNum(_items[i]['unit_price'])),
                  style: tabular(tt.titleSmall).copyWith(fontWeight: FontWeight.w700)),
            ),
        ]),

      // Summary
      const SectionHeader('Summary'),
      Surface(
        margin: const EdgeInsets.symmetric(horizontal: kGutter),
        color: p.muted,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KeyValueRow('Subtotal', _fmt(_subtotal)),
          if (readOnly) ...[
            KeyValueRow('Discount (₹)', _fmt(_discount.text)),
            KeyValueRow('Tax (₹)', _fmt(_tax.text)),
          ] else ...[
            const SizedBox(height: 8),
            AppTextField(controller: _discount, label: 'Discount (₹)', money: true, onChanged: (_) => setState(() {})),
            kFieldGap,
            AppTextField(controller: _tax, label: 'Tax (₹)', money: true, onChanged: (_) => setState(() {})),
            const SizedBox(height: 8),
          ],
          const Divider(height: 20),
          KeyValueRow('Grand Total', _fmt(_grand), strong: true, valueColor: p.accentText),
        ]),
      ),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGutter),
        child: readOnly
            ? InfoTile(label: 'Notes / Terms', value: _notes.text)
            : AppTextField(controller: _notes, label: 'Notes / Terms', maxLines: 5, minLines: 3),
      ),

      // Deliveries
      PODeliveries(po: po, log: _receipts, onChanged: _applyAndRefresh),

      // Payments
      if (issuedOrSent || paid > 0) ...[
        const SectionHeader('Payments'),
        KpiGrid(children: [
          KpiTile(label: 'Paid to vendor', value: _fmt(paid), tone: Tone.success),
          KpiTile(label: 'Balance due', value: _fmt(balance), tone: balance > 0 ? Tone.danger : Tone.neutral),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 10, kGutter, 0),
          child: Row(children: [
            StatusChip(po['payment_status'] as String?,
                label: po['payment_status'] as String?,
                tone: po['payment_status'] == 'Paid'
                    ? Tone.success
                    : po['payment_status'] == 'Partially Paid'
                        ? Tone.warning
                        : Tone.neutral),
            const Spacer(),
            if (_canPay && status != 'CANCELLED' && balance > 0)
              SmallAction(label: 'Record Payment', icon: Icons.currency_rupee, filled: true, color: p.success, onPressed: _pay),
          ]),
        ),
        if (_payments.isNotEmpty) ...[
          const SizedBox(height: 10),
          RowGroup(children: [
            for (final pay in _payments)
              RowTile(
                title: '${fmtDate(pay['payment_date'])} · ${dash(pay['payment_method'])}',
                subtitle: [
                  'Ref ${dash(pay['reference_no'])}',
                  if ((pay['notes'] ?? '').toString().isNotEmpty) pay['notes'].toString(),
                  'By ${dash(pay['recorded_by'])}',
                ].join(' · '),
                trailing: Text(_fmt(pay['amount']), style: tabular(tt.titleSmall).copyWith(fontWeight: FontWeight.w700)),
              ),
          ]),
        ],
      ],

      // Actions
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGutter),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          if (!readOnly && !(paid > 0))
            SmallAction(label: 'Cancel', icon: Icons.block, color: p.danger, onPressed: _cancel),
          if (status != 'CANCELLED' && issuedOrSent) ...[
            SmallAction(label: 'Print', icon: Icons.print_outlined, onPressed: () => _openPdf(po)),
            SmallAction(label: 'Download', icon: Icons.download_outlined, onPressed: () => _sharePdf(po)),
            if (_canWrite) ...[
              SmallAction(
                  label: 'Email', icon: Icons.mail_outline, color: p.info, onPressed: canEmail ? () => _send('email') : null),
              SmallAction(
                  label: 'WhatsApp',
                  icon: Icons.chat_outlined,
                  color: p.success,
                  onPressed: canWhatsapp ? () => _send('whatsapp') : null),
            ],
          ],
        ]),
      ),
      if (_canWrite && issuedOrSent && status != 'CANCELLED' && (!canEmail || !canWhatsapp))
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 0),
          child: Text(
            [if (!canEmail) 'Vendor has no email on file', if (!canWhatsapp) 'Vendor has no phone on file'].join(' · '),
            style: tt.bodySmall,
          ),
        ),
    ];
  }
}

class _POItemForm extends StatefulWidget {
  final Map<String, dynamic>? item;
  final bool canRemove;
  const _POItemForm({this.item, required this.canRemove});

  @override
  State<_POItemForm> createState() => _POItemFormState();
}

class _POItemFormState extends State<_POItemForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?['item_name'] ?? '');
  late final _desc = TextEditingController(text: widget.item?['description'] ?? '');
  late final _qty = TextEditingController(text: widget.item?['quantity'] ?? '1');
  late final _price = TextEditingController(text: widget.item?['unit_price'] ?? '0');

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(
          controller: _name,
          label: 'Item',
          requiredField: true,
          validator: (v) => (v ?? '').trim().isEmpty ? 'Every item needs a name' : null,
        ),
        kFieldGap,
        AppTextField(controller: _desc, label: 'Description'),
        kFieldGap,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: AppTextField(
              controller: _qty,
              label: 'Qty',
              number: true,
              onChanged: (_) => setState(() {}),
              validator: (v) => toNum(v) > 0 ? null : 'Must be greater than 0',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppTextField(
              controller: _price,
              label: 'Unit Price',
              money: true,
              onChanged: (_) => setState(() {}),
              validator: (v) => toNum(v) < 0 ? 'Cannot be negative' : null,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        KeyValueRow('Total', _fmt(toNum(_qty.text) * toNum(_price.text))),
        const SizedBox(height: 16),
        SubmitButton(
          label: widget.item == null ? 'Add Item' : 'Update Item',
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, {
              if (widget.item == null) 'quotation_item_id': null,
              'item_name': _name.text,
              'description': _desc.text,
              'quantity': _qty.text,
              'unit_price': _price.text,
            });
          },
        ),
        if (widget.canRemove) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => Navigator.pop(context, {'remove': true}),
            icon: Icon(Icons.delete_outline, color: p.danger),
            label: Text('Remove item', style: TextStyle(color: p.danger)),
          ),
        ],
      ]),
    );
  }
}

class _POSendForm extends StatefulWidget {
  final int poId;
  final String channel;
  final Map<String, dynamic> vendor;
  const _POSendForm({required this.poId, required this.channel, required this.vendor});

  @override
  State<_POSendForm> createState() => _POSendFormState();
}

class _POSendFormState extends State<_POSendForm> {
  bool _busy = false;

  Future<void> _send() async {
    setState(() => _busy = true);
    final api = context.read<ApiClient>();
    try {
      if (widget.channel == 'email') {
        final r = asMap(await api.post('/quotation-purchase-orders/${widget.poId}/send-email')) ?? {};
        if (!mounted) return;
        showToast(context, 'Emailed to ${r['sent_to']}');
        Navigator.pop(context, asMap(r['po']));
      } else {
        final r = asMap(await api.post('/quotation-purchase-orders/${widget.poId}/send-whatsapp')) ?? {};
        if (!mounted) return;
        final wa = r['wa_link'] as String?;
        if (wa != null && wa.isNotEmpty) await openExternal(context, wa);
        if (!mounted) return;
        showToast(context, 'WhatsApp opened for ${r['sent_to']}');
        Navigator.pop(context, asMap(r['po']));
      }
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.channel == 'email';
    final target = (email ? widget.vendor['email'] : widget.vendor['phone'])?.toString() ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Surface(child: InfoTile(label: email ? 'Vendor Email' : 'Vendor Phone', value: target.isEmpty ? 'Not on file' : target)),
      const SizedBox(height: 18),
      SubmitButton(label: 'Send', icon: Icons.send_outlined, busy: _busy, onPressed: _send),
    ]);
  }
}

class _POPaymentForm extends StatefulWidget {
  final Map<String, dynamic> po;
  const _POPaymentForm({required this.po});

  @override
  State<_POPaymentForm> createState() => _POPaymentFormState();
}

class _POPaymentFormState extends State<_POPaymentForm> {
  late final _amount = TextEditingController(text: inputNum(widget.po['balance_due']));
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'BankTransfer';
  String? _date = todayIso();
  bool _paying = false;
  bool _guard = false; // one tap = one payment

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amt = toNum(_amount.text);
    final balance = toNum(widget.po['balance_due']);
    if (!(amt > 0)) {
      showToast(context, 'Enter a valid amount', error: true);
      return;
    }
    if (amt > balance + 0.005) {
      showToast(context, 'Amount is more than the balance due (${_fmt(balance)})', error: true);
      return;
    }
    if (_guard) return;
    _guard = true;
    setState(() => _paying = true);
    final api = context.read<ApiClient>();
    try {
      final data = asMap(await api.post('/quotation-purchase-orders/${widget.po['id']}/payments', data: {
            'amount': amt,
            'payment_method': _method,
            'payment_date': _date,
            'reference_no': _ref.text.isEmpty ? null : _ref.text,
            'notes': _notes.text.isEmpty ? null : _notes.text,
          })) ??
          {};
      if (!mounted) return;
      showToast(context, '${_fmt(amt)} paid to ${asMap(data['vendor'])?['name'] ?? 'vendor'} — added to the project balance sheet');
      Navigator.pop(context, data);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _paying = false);
      Future.delayed(const Duration(milliseconds: 800), () => _guard = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final balance = toNum(widget.po['balance_due']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTextField(controller: _amount, label: 'Amount (₹)', money: true, requiredField: true),
      Wrap(spacing: 4, children: [
        for (final (l, v) in [('Full balance', balance), ('50%', (balance * 50).round() / 100)])
          TextButton(
            onPressed: () => setState(() => _amount.text = inputNum(v)),
            child: Text(l, style: TextStyle(color: p.accentText)),
          ),
      ]),
      const SizedBox(height: 6),
      AppDropdown<String>(
        label: 'Method',
        value: _method,
        items: [for (final m in kPayMethods) (m, m)],
        onChanged: (v) {
          if (v != null) setState(() => _method = v);
        },
      ),
      kFieldGap,
      DateField(label: 'Date', value: _date, lastDate: DateTime.now(), onChanged: (v) => setState(() => _date = v)),
      kFieldGap,
      AppTextField(controller: _ref, label: 'Reference No. (UTR / cheque no.)', capitalization: TextCapitalization.characters),
      kFieldGap,
      AppTextField(controller: _notes, label: 'Notes', hint: 'e.g. Advance 50%'),
      const SizedBox(height: 18),
      SubmitButton(label: 'Record Payment', busy: _paying, onPressed: _submit),
    ]);
  }
}
