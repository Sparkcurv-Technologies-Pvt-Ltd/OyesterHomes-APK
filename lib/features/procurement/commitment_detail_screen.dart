import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import 'proc_common.dart';

/// Web: pages/CommitmentDetailPage.jsx (route /admin/projects/:id/procurement/:type/:commitmentId)
/// with LineItemTable, LienWaiverRow, ChangeOrderCard, ProcurementDocumentsPanel and CommitmentStatusBadge.
/// [type] is the URL segment: `po` or `subcontract`.
class CommitmentDetailScreen extends StatefulWidget {
  final int projectId;
  final String type;
  final int commitmentId;
  const CommitmentDetailScreen({super.key, required this.projectId, required this.type, required this.commitmentId});

  @override
  State<CommitmentDetailScreen> createState() => _CommitmentDetailScreenState();
}

const _methods = ['BankTransfer', 'Cash', 'Cheque', 'UPI'];

class _CommitmentDetailScreenState extends State<CommitmentDetailScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  Map<String, dynamic>? _c;
  List<Map<String, dynamic>> _cos = [];
  List<Map<String, dynamic>> _payApps = [];
  List<Map<String, dynamic>> _payments = [];
  Object? _error;

  final _coReason = TextEditingController();
  final _coAmount = TextEditingController();
  final _paAmount = TextEditingController();

  bool get _isPo => widget.type == 'po';
  String get _type => widget.type;
  int get _id => widget.commitmentId;
  String get _base => _isPo ? '/purchase-orders/$_id' : '/subcontracts/$_id';
  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _coReason.dispose();
    _coAmount.dispose();
    _paAmount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = _api;
      final res = await Future.wait([
        api.get(_base),
        api.get('/commitments/$_type/$_id/change-orders'),
        api.get('/commitments/$_type/$_id/pay-applications'),
        // The payment history is an extra; a 404/403 on it must not hide the page.
        api.get('/commitments/$_type/$_id/payments').catchError((_) => <dynamic>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _c = Map<String, dynamic>.from(res[0] as Map);
        _cos = asMaps(res[1]);
        _payApps = asMaps(res[2]);
        _payments = asMaps(res[3]);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Runs a write, toasts [ok] or the server error, reloads on success (web `act`).
  Future<bool> _act(Future<dynamic> Function() call, String ok) async {
    final done = await runAction(context, () => call(), success: ok);
    if (done) await _load();
    return done;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final isAdmin = user?.isAdmin ?? false;
    final canWrite = user?.canWrite ?? false;
    final c = _c;
    final kind = _isPo ? 'Purchase Order' : 'Subcontract';

    Widget body;
    if (c == null) {
      body = _error != null
          ? Center(child: SingleChildScrollView(child: ErrorRetry(message: errorText(_error), onRetry: _load)))
          : const LoadingView();
    } else {
      body = TabBarView(controller: _tabs, children: [
        _overview(c, isAdmin, canWrite),
        _changeOrders(isAdmin, canWrite),
        _payAppsTab(c, isAdmin, canWrite),
        _DocumentsTab(type: _type, id: _id, canWrite: canWrite, isAdmin: isAdmin),
      ]);
    }

    return AppScaffold(
      title: c == null ? kind : (c['number'] ?? kind).toString(),
      subtitle: c == null ? null : '${c['vendor_name'] ?? '—'} · $kind · Cost code ${dash(c['cost_code'])}',
      bottom: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: const [Tab(text: 'Overview'), Tab(text: 'Change Orders'), Tab(text: 'Pay Apps'), Tab(text: 'Documents')],
      ),
      body: body,
    );
  }

  // ───────────────────────────────────────────────────────── overview

  Widget _overview(Map<String, dynamic> c, bool isAdmin, bool canWrite) {
    final status = c['status'] as String?;
    final vendor = c['vendor'] as Map?;
    final lines = asMaps(c['line_items']);
    final p = context.pal;
    return RefreshList(onRefresh: _load, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 12),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          ProcStatus(status),
          if (c['pending_approval'] == true) const StatusChip('pending', label: 'Pending Items', tone: Tone.warning),
        ]),
      ),
      KpiGrid(children: [
        _Cell('Vendor', dash(c['vendor_name'])),
        _Cell('Original Amount', inr(c['original_amount'])),
        _Cell('Committed (Revised)', inr(c['committed_amount'])),
        _Cell('Change Orders', inr(c['change_orders_total'])),
        if (!_isPo) _Cell('Retainage %', '${inputNum(c['retainage_pct'])}%'),
        _Cell(_isPo ? 'Issue Date' : 'Start Date', fmtDate(_isPo ? c['issue_date'] : c['start_date'])),
        _Cell(_isPo ? 'Expected Delivery' : 'End Date', fmtDate(_isPo ? c['expected_delivery_date'] : c['end_date'])),
        if (vendor != null)
          _Cell(
            'Vendor Insurance',
            vendor['insurance_current'] == true ? 'Valid to ${fmtDate(vendor['insurance_expiry'])}' : 'EXPIRED',
            color: vendor['insurance_current'] == true ? null : p.danger,
          ),
      ]),
      const SectionHeader('Payments'),
      KpiGrid(children: [
        _Cell('Certified (approved bills)', inr(c['certified'])),
        _Cell('Paid', inr(c['paid'])),
        _Cell('Balance Due', inr(c['balance_due'])),
        if (!_isPo) _Cell('Retainage Held', inr(c['retainage_balance'])),
        if (!_isPo) _Cell('Retainage Released', inr(c['retainage_released'])),
      ]),
      if (isAdmin) ...[
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kGutter),
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            if (_isPo && status != 'Approved' && status != 'Cancelled')
              SmallAction(
                  label: 'Approve PO',
                  filled: true,
                  tone: Tone.success,
                  onPressed: () => _act(() => _api.post('$_base/approve'), 'PO approved')),
            if (!_isPo && status != 'Executed') ...[
              SmallAction(
                  label: 'Approve',
                  filled: true,
                  tone: Tone.success,
                  onPressed: () => _act(() => _api.post('$_base/approve'), 'Subcontract approved')),
              SmallAction(
                  label: 'Execute',
                  filled: true,
                  onPressed: () => _act(() => _api.post('$_base/execute'), 'Subcontract executed')),
            ],
            if (_isPo && status != 'Cancelled')
              SmallAction(
                label: 'Cancel',
                tone: Tone.danger,
                onPressed: () async {
                  final ok = await confirmDialog(context,
                      title: 'Cancel ${c['number']}?', confirmLabel: 'Cancel PO', destructive: true);
                  if (ok) await _act(() => _api.post('$_base/cancel'), 'PO cancelled');
                },
              ),
          ]),
        ),
      ],
      if (_isPo) ...[
        const SectionHeader('PO Line Items'),
        RowGroup(
          footer: canWrite
              ? _AddRowButton(
                  label: 'Add Line Item',
                  onTap: () => _addLine(
                    title: 'Add Line Item',
                    fields: const [
                      ('item_description', 'Description', _F.text),
                      ('unit', 'Unit', _F.text),
                      ('quantity', 'Qty', _F.number),
                      ('unit_price', 'Unit Price', _F.money),
                    ],
                    send: (d) => _api.post('$_base/line-items', data: {
                      'item_description': d['item_description'] ?? '',
                      'unit': (d['unit'] ?? '').isEmpty ? null : d['unit'],
                      'quantity': toNum(d['quantity']),
                      'unit_price': toNum(d['unit_price']),
                    }),
                    ok: 'Line item added',
                  ),
                )
              : null,
          children: [
            if (lines.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No line items yet.', textAlign: TextAlign.center),
              ),
            for (final li in lines)
              RowTile(
                padding: EdgeInsets.fromLTRB(14, 10, canWrite ? 4 : 14, 10),
                title: dash(li['item_description']),
                subtitle: '${qty(li['quantity'])} ${li['unit'] ?? ''} × ${inr(li['unit_price'])} · '
                    'Received ${qty(li['received_quantity'])}',
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(inr(li['line_total']),
                      style: tabular(Theme.of(context).textTheme.titleSmall).copyWith(fontWeight: FontWeight.w700)),
                  if (canWrite)
                    IconButton(
                      tooltip: 'Remove line item',
                      icon: Icon(Icons.delete_outline, size: 20, color: p.fgSubtle),
                      onPressed: () async {
                        final ok = await confirmDialog(context,
                            title: 'Remove line item?', message: dash(li['item_description']),
                            confirmLabel: 'Remove', destructive: true);
                        if (ok) await _act(() => _api.delete('/po-line-items/${li['id']}'), 'Line item removed');
                      },
                    ),
                ]),
              ),
          ],
        ),
      ],
    ]);
  }

  // ───────────────────────────────────────────────────────── change orders

  Widget _changeOrders(bool isAdmin, bool canWrite) {
    return RefreshList(onRefresh: _load, children: [
      if (canWrite)
        Surface(
          margin: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 12),
          child: StatefulBuilder(builder: (context, setLocal) {
            final ready = _coReason.text.trim().isNotEmpty && _coAmount.text.isNotEmpty;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppTextField(controller: _coReason, label: 'Reason', onChanged: (_) => setLocal(() {})),
              kFieldGap,
              AppTextField(
                controller: _coAmount,
                label: 'Amount (₹, +/−)',
                number: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                onChanged: (_) => setLocal(() {}),
              ),
              const SizedBox(height: 14),
              _BusyButton(
                label: 'New CO',
                icon: Icons.add,
                onPressed: !ready
                    ? null
                    : () async {
                        await _act(
                            () => _api.post('/commitments/$_type/$_id/change-orders',
                                data: {'reason': _coReason.text.trim(), 'amount': toNum(_coAmount.text)}),
                            'Change order created');
                        _coReason.clear();
                        _coAmount.clear();
                        setLocal(() {});
                      },
              ),
            ]);
          }),
        ),
      if (_cos.isEmpty)
        const EmptyState(icon: Icons.edit_note_outlined, title: 'No change orders.')
      else
        for (final co in _cos)
          _ChangeOrderCard(
            co: co,
            isAdmin: isAdmin,
            onDecide: (status) => _act(() => _api.patch('/change-orders/${co['id']}', data: {'status': status}),
                'Change order ${status.toLowerCase()}'),
          ),
    ]);
  }

  // ───────────────────────────────────────────────────────── pay applications

  Widget _payAppsTab(Map<String, dynamic> c, bool isAdmin, bool canWrite) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final retainageBal = toNum(c['retainage_balance']);
    return RefreshList(onRefresh: _load, children: [
      if (canWrite)
        Surface(
          margin: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 12),
          child: StatefulBuilder(builder: (context, setLocal) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppTextField(
                  controller: _paAmount,
                  label: 'Amount this period (₹)',
                  money: true,
                  onChanged: (_) => setLocal(() {})),
              if (!_isPo) ...[
                const SizedBox(height: 6),
                Text('Retainage ${inputNum(c['retainage_pct'])}% is withheld automatically', style: tt.bodySmall),
              ],
              const SizedBox(height: 14),
              _BusyButton(
                label: 'New Pay App',
                icon: Icons.add,
                onPressed: _paAmount.text.isEmpty
                    ? null
                    : () async {
                        await _act(
                            () => _api.post('/commitments/$_type/$_id/pay-applications',
                                data: {'amount_this_period': toNum(_paAmount.text)}),
                            'Pay application created');
                        _paAmount.clear();
                        setLocal(() {});
                      },
              ),
            ]);
          }),
        ),
      if (_payApps.isEmpty)
        const EmptyState(icon: Icons.request_quote_outlined, title: 'No pay applications.')
      else
        for (final pa in _payApps) _payAppCard(pa, isAdmin, canWrite),

      if (!_isPo && isAdmin && retainageBal > 0)
        Surface(
          margin: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: 'Retainage held: ${inr(retainageBal)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(
                  text: ' — withheld from approved bills, payable to the subcontractor when you release it.',
                  style: TextStyle(color: p.fgMuted)),
            ])),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: SmallAction(
                label: 'Release retainage',
                onPressed: () => _paymentSheet(
                  title: 'Release retainage',
                  amountHint: 'Up to ${inr(retainageBal)}',
                  amountRequired: true,
                  submitLabel: 'Release',
                  url: '/commitments/$_type/$_id/release-retainage',
                  ok: 'Retainage released',
                ),
              ),
            ),
          ]),
        ),

      if (_payments.isNotEmpty) ...[
        const SectionHeader('Payment history'),
        RowGroup(children: [
          for (final pay in _payments)
            RowTile(
              title: inr(pay['amount']),
              subtitleWidget: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    '${pay['kind'] == 'retainage' ? 'Retainage release' : 'Pay application'} · ${pay['payment_method'] ?? ''}',
                    style: tt.bodySmall),
                if ((pay['reference_no'] ?? '').toString().isNotEmpty) Text('Ref ${pay['reference_no']}', style: tt.bodySmall),
                if ((pay['notes'] ?? '').toString().isNotEmpty) Text(pay['notes'].toString(), style: tt.bodySmall),
              ]),
              trailing: Text(fmtDate(pay['payment_date']),
                  style: TextStyle(fontFamily: monoFamily, fontSize: 12, color: p.fgMuted)),
            ),
        ]),
      ],
    ]);
  }

  Widget _payAppCard(Map<String, dynamic> pa, bool isAdmin, bool canWrite) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final status = pa['status'] as String?;
    final lines = asMaps(pa['line_items']);
    final waivers = asMaps(pa['lien_waivers']);
    final paId = pa['id'];
    final draft = status == 'Draft';
    return Surface(
      margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('App #${pa['application_number']}',
              style: tt.titleLarge?.copyWith(color: p.accentText, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          ProcStatus(status),
        ]),
        if ((canWrite && draft) ||
            (isAdmin && (status == 'Submitted' || status == 'UnderReview')) ||
            (isAdmin && status == 'Approved')) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (canWrite && draft)
              SmallAction(
                  label: 'Submit',
                  tone: Tone.info,
                  onPressed: () => _act(() => _api.post('/pay-applications/$paId/submit'), 'Pay app submitted')),
            if (isAdmin && (status == 'Submitted' || status == 'UnderReview'))
              SmallAction(
                  label: 'Approve',
                  filled: true,
                  tone: Tone.success,
                  onPressed: () => _act(() => _api.post('/pay-applications/$paId/approve'), 'Pay app approved')),
            if (isAdmin && status == 'Approved')
              SmallAction(
                label: 'Record Payment',
                filled: true,
                tone: Tone.success,
                onPressed: () => _paymentSheet(
                  title: 'Record Payment',
                  subtitle: 'App #${pa['application_number']}',
                  amountHint: 'Leave blank to pay full ${inr(pa['balance'])}',
                  amountRequired: false,
                  submitLabel: 'Save payment',
                  url: '/pay-applications/$paId/mark-paid',
                  ok: 'Payment recorded',
                ),
              ),
          ]),
        ],
        const SizedBox(height: 12),
        KeyValueRow('This Period', inr(pa['amount_this_period'])),
        KeyValueRow('Retainage Held', inr(pa['retainage_held']), valueColor: p.warning),
        KeyValueRow('Amount Due', inr(pa['amount_due']), valueColor: p.success),
        KeyValueRow('Paid', inr(pa['paid'])),
        KeyValueRow('Balance', inr(pa['balance']), valueColor: p.danger),
        const SizedBox(height: 10),
        const Eyebrow('Line Items'),
        const SizedBox(height: 6),
        RowGroup(
          margin: EdgeInsets.zero,
          footer: canWrite && draft
              ? _AddRowButton(
                  label: 'Add Line Item',
                  onTap: () => _addLine(
                    title: 'Add Line Item',
                    subtitle: 'App #${pa['application_number']}',
                    fields: const [
                      ('description', 'Description', _F.text),
                      ('scheduled_value', 'Scheduled', _F.money),
                      ('previous_completed', 'Previous', _F.money),
                      ('this_period', 'This Period', _F.money),
                      ('materials_stored', 'Stored', _F.money),
                    ],
                    send: (d) => _api.post('/pay-applications/$paId/line-items', data: {
                      'description': d['description'] ?? '',
                      'scheduled_value': toNum(d['scheduled_value']),
                      'previous_completed': toNum(d['previous_completed']),
                      'this_period': toNum(d['this_period']),
                      'materials_stored': toNum(d['materials_stored']),
                    }),
                    ok: 'Line added',
                  ),
                )
              : null,
          children: [
            if (lines.isEmpty)
              const Padding(padding: EdgeInsets.all(14), child: Text('No line items yet.', textAlign: TextAlign.center)),
            for (final li in lines)
              RowTile(
                title: dash(li['description']),
                subtitle: 'Scheduled ${inr(li['scheduled_value'])} · Previous ${inr(li['previous_completed'])} · '
                    'This Period ${inr(li['this_period'])} · Stored ${inr(li['materials_stored'])}',
                trailing: Text('${inputNum(li['pct_complete'])}%',
                    style: tabular(tt.titleSmall).copyWith(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Eyebrow('Lien Waivers')),
          if (canWrite)
            TextButton(
              onPressed: () => _act(
                  () => _api.post('/pay-applications/$paId/lien-waivers',
                      data: {'waiver_type': 'ConditionalProgress', 'amount': pa['amount_due']}),
                  'Lien waiver added'),
              child: const Text('+ Add Waiver'),
            ),
        ]),
        for (final w in waivers) _LienWaiverRow(waiver: w, canWrite: canWrite, onUploaded: _load),
      ]),
    );
  }

  /// "Record payment" / "Release retainage" (web PaymentFields) as a sheet.
  Future<void> _paymentSheet({
    required String title,
    String? subtitle,
    required String amountHint,
    required bool amountRequired,
    required String submitLabel,
    required String url,
    required String ok,
  }) async {
    final api = _api;
    final done = await showAppSheet<bool>(
      context,
      title: title,
      subtitle: subtitle,
      builder: (ctx) => _PaymentForm(
        amountHint: amountHint,
        amountRequired: amountRequired,
        submitLabel: submitLabel,
        send: (body) => api.post(url, data: body),
      ),
    );
    if (done == true && mounted) {
      showToast(context, ok);
      await _load();
    }
  }

  /// Add-row form for the web's LineItemTable (PO lines and pay-application lines).
  Future<void> _addLine({
    required String title,
    String? subtitle,
    required List<(String, String, _F)> fields,
    required Future<dynamic> Function(Map<String, String> d) send,
    required String ok,
  }) async {
    final done = await showAppSheet<bool>(
      context,
      title: title,
      subtitle: subtitle,
      builder: (ctx) => _LineForm(fields: fields, send: send),
    );
    if (done == true && mounted) {
      showToast(context, ok);
      await _load();
    }
  }
}

// ───────────────────────────────────────────────────────── pieces

class _Cell extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Cell(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Surface(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Eyebrow(label),
        const SizedBox(height: 6),
        Text(value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tabular(tt.titleMedium).copyWith(fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

class _AddRowButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddRowButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add, size: 16, color: p.fgMuted),
          const SizedBox(width: 6),
          Eyebrow(label, color: p.fgMuted),
        ]),
      ),
    );
  }
}

/// Inline submit button with its own busy state (CO / pay-app create rows).
class _BusyButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Future<void> Function()? onPressed;
  const _BusyButton({required this.label, this.icon, this.onPressed});

  @override
  State<_BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<_BusyButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => SubmitButton(
        label: widget.label,
        icon: widget.icon,
        busy: _busy,
        onPressed: widget.onPressed == null
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  await widget.onPressed!();
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
      );
}

/// Web ChangeOrderCard.
class _ChangeOrderCard extends StatelessWidget {
  final Map<String, dynamic> co;
  final bool isAdmin;
  final Future<bool> Function(String status) onDecide;
  const _ChangeOrderCard({required this.co, required this.isAdmin, required this.onDecide});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final amount = toNum(co['amount']);
    return Surface(
      margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text((co['co_number'] ?? '').toString(),
              style: tt.titleMedium?.copyWith(color: p.accentText, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          ProcStatus(co['status'] as String?, dense: true),
          const Spacer(),
          Text('${amount < 0 ? '−' : '+'}${inr(amount.abs())}',
              style: tabular(tt.titleLarge).copyWith(fontWeight: FontWeight.w700, color: amount < 0 ? p.danger : p.fg)),
        ]),
        const SizedBox(height: 6),
        Text((co['reason'] ?? '').toString(), style: tt.bodyMedium),
        const SizedBox(height: 2),
        Text('Requested ${fmtDate(co['requested_at'])}', style: tt.bodySmall),
        if (isAdmin && co['status'] == 'Pending') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: SmallAction(
                    label: 'Approve', filled: true, tone: Tone.success, onPressed: () => onDecide('Approved'))),
            const SizedBox(width: 8),
            Expanded(child: SmallAction(label: 'Reject', tone: Tone.danger, onPressed: () => onDecide('Rejected'))),
          ]),
        ],
      ]),
    );
  }
}

/// Web LienWaiverRow.
class _LienWaiverRow extends StatelessWidget {
  final Map<String, dynamic> waiver;
  final bool canWrite;
  final Future<void> Function() onUploaded;
  const _LienWaiverRow({required this.waiver, required this.canWrite, required this.onUploaded});

  Future<void> _upload(BuildContext context) async {
    final api = context.read<ApiClient>();
    final up = await pickAndUpload(context, api);
    if (up == null || !context.mounted) return;
    final ok = await runAction(
      context,
      () => api.patch('/lien-waivers/${waiver['id']}', data: {'file_url': up['url'], 'status': 'Received'}),
      success: 'Waiver updated',
    );
    if (ok) await onUploaded();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final url = (waiver['file_url'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(Radii.control)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Eyebrow(humanize(waiver['waiver_type'] as String?)),
            const SizedBox(height: 4),
            Text('${inr(waiver['amount'])} · ${fmtDate(waiver['signed_date'], empty: 'unsigned')}',
                style: tabular(tt.bodySmall)),
            const SizedBox(height: 4),
            ProcStatus(waiver['status'] as String?, dense: true),
          ]),
        ),
        if (url.isNotEmpty)
          TextButton(
            onPressed: () => openServerFile(context, context.read<ApiClient>(), url),
            child: const Text('View'),
          ),
        if (canWrite)
          TextButton.icon(
            onPressed: () => _upload(context),
            icon: const Icon(Icons.upload_file, size: 16),
            label: const Text('Upload'),
          ),
      ]),
    );
  }
}

/// Fields of the web's PaymentFields (amount, paid on, method, reference, notes).
class _PaymentForm extends StatefulWidget {
  final String amountHint;
  final bool amountRequired;
  final String submitLabel;
  final Future<dynamic> Function(Map<String, dynamic> body) send;
  const _PaymentForm({required this.amountHint, required this.amountRequired, required this.submitLabel, required this.send});

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  final _amount = TextEditingController();
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  String? _date = todayIso();
  String _method = 'BankTransfer';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    // Web payBody: amount only when given; blank reference / notes are null.
    final body = <String, dynamic>{
      if (_amount.text.isNotEmpty) 'amount': toNum(_amount.text),
      'payment_date': _date,
      'payment_method': _method,
      'reference_no': _ref.text.isEmpty ? null : _ref.text,
      'notes': _notes.text.isEmpty ? null : _notes.text,
    };
    try {
      await widget.send(body);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorText(e));
        showToast(context, errorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTextField(
        controller: _amount,
        label: 'Amount (₹)',
        money: true,
        helper: widget.amountHint,
        onChanged: (_) => setState(() {}),
      ),
      kFieldGap,
      DateField(
        label: 'Paid on',
        value: _date,
        clearable: false,
        lastDate: DateTime(now.year, now.month, now.day),
        onChanged: (v) => setState(() => _date = v),
      ),
      kFieldGap,
      AppDropdown<String>(
        label: 'Method',
        value: _method,
        items: [for (final m in _methods) (m, m)],
        onChanged: (v) => setState(() => _method = v ?? _method),
      ),
      kFieldGap,
      AppTextField(controller: _ref, label: 'Reference', hint: 'e.g. UTR 402188301156 or cheque no. 000123'),
      kFieldGap,
      AppTextField(controller: _notes, label: 'Notes', hint: 'e.g. 2nd running bill, work measured by site engineer'),
      const SizedBox(height: 20),
      SheetError(_error),
      SubmitButton(
        label: widget.submitLabel,
        busy: _saving,
        onPressed: widget.amountRequired && _amount.text.isEmpty ? null : _submit,
      ),
    ]);
  }
}

/// Field kinds of the add-row sheet.
enum _F { text, number, money }

/// Add-row sheet for LineItemTable. [fields] are (key, label, kind).
class _LineForm extends StatefulWidget {
  final List<(String, String, _F)> fields;
  final Future<dynamic> Function(Map<String, String> d) send;
  const _LineForm({required this.fields, required this.send});

  @override
  State<_LineForm> createState() => _LineFormState();
}

class _LineFormState extends State<_LineForm> {
  late final Map<String, TextEditingController> _c = {
    for (final f in widget.fields) f.$1: TextEditingController(),
  };
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.send({for (final e in _c.entries) e.key: e.value.text});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorText(e));
        showToast(context, errorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.fields.first.$1;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (key, label, kind) in widget.fields) ...[
        AppTextField(
          controller: _c[key],
          label: label,
          requiredField: key == first,
          autofocus: key == first,
          number: kind == _F.number,
          money: kind == _F.money,
          onChanged: key == first ? (_) => setState(() {}) : null,
        ),
        kFieldGap,
      ],
      const SizedBox(height: 6),
      SheetError(_error),
      SubmitButton(label: 'Save', busy: _saving, onPressed: _c[first]!.text.trim().isEmpty ? null : _submit),
    ]);
  }
}

// ───────────────────────────────────────────────────────── documents

const _docCats = ['Contract', 'Insurance', 'LienWaiver', 'Submittal', 'Other'];

/// Web ProcurementDocumentsPanel.
class _DocumentsTab extends StatefulWidget {
  final String type;
  final int id;
  final bool canWrite;
  final bool isAdmin;
  const _DocumentsTab({required this.type, required this.id, required this.canWrite, required this.isAdmin});

  @override
  State<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<_DocumentsTab> with AutomaticKeepAliveClientMixin {
  final _key = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();
  String _search = '';

  @override
  bool get wantKeepAlive => true;

  ApiClient get _api => context.read<ApiClient>();

  Future<void> _pick() async {
    final f = await pickFile(context);
    if (f == null || !mounted) return;
    final api = _api;
    final done = await showAppSheet<bool>(
      context,
      title: 'Upload document',
      subtitle: f.name,
      builder: (ctx) => _DocUploadForm(
        fileName: f.name,
        send: (name, category, visible) async => api.postMultipart('/procurement/${widget.type}/${widget.id}/documents', {
          'file': await MultipartFile.fromFile(f.path, filename: f.name),
          'document_name': name.trim(),
          'category': category,
          'is_client_visible': visible.toString(),
        }),
      ),
    );
    if (done == true && mounted) {
      showToast(context, 'Document uploaded');
      _key.currentState?.reload();
    }
  }

  Future<void> _rename(Map<String, dynamic> d) async {
    final name = await promptText(context, title: 'Document name', initial: d['document_name']?.toString(), maxLines: 1);
    if (name == null || name.trim().isEmpty || !mounted) return;
    final ok = await runAction(
        context, () => _api.patch('/procurement-documents/${d['id']}', data: {'document_name': name.trim()}),
        success: 'Renamed');
    if (ok) _key.currentState?.reload();
  }

  Future<void> _remove(Map<String, dynamic> d) async {
    final ok = await confirmDialog(context,
        title: 'Delete "${d['document_name']}"?', confirmLabel: 'Delete', destructive: true);
    if (!ok || !mounted) return;
    final done = await runAction(context, () => _api.delete('/procurement-documents/${d['id']}'), success: 'Deleted');
    if (done) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    return AsyncView<List<Map<String, dynamic>>>(
      key: _key,
      load: () async => asMaps(await _api.get('/procurement/${widget.type}/${widget.id}/documents')),
      builder: (context, docs, reload) {
        final q = _search.toLowerCase();
        final shown =
            q.isEmpty ? docs : docs.where((d) => (d['document_name'] ?? '').toString().toLowerCase().contains(q)).toList();
        return RefreshList(onRefresh: reload, children: [
          if (widget.canWrite)
            Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 4),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: _pick,
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: const Text('Choose file'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 8),
            child: SearchField(hint: 'Search documents…', onChanged: (v) => setState(() => _search = v)),
          ),
          if (shown.isEmpty)
            const EmptyState(icon: Icons.description_outlined, title: 'No documents.')
          else
            RowGroup(children: [
              for (final d in shown)
                RowTile(
                  onTap: () => openServerFile(context, _api, (d['file_url'] ?? '').toString(),
                      name: d['document_name']?.toString()),
                  padding: EdgeInsets.fromLTRB(14, 10, widget.isAdmin ? 0 : 14, 10),
                  leading: Icon(Icons.description_outlined, size: 20, color: p.accentText),
                  title: (d['document_name'] ?? '').toString(),
                  subtitleWidget: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${d['uploader_name'] ?? '—'} · ${fmtDate(d['uploaded_at'])} · ${d['category'] ?? ''}',
                        style: tt.bodySmall),
                    if (d['is_client_visible'] != true) const CodeTag('INTERNAL'),
                  ]),
                  trailing: widget.isAdmin
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              tooltip: 'Rename',
                              icon: Icon(Icons.edit_outlined, size: 19, color: p.fgMuted),
                              onPressed: () => _rename(d)),
                          IconButton(
                              tooltip: 'Delete',
                              icon: Icon(Icons.delete_outline, size: 19, color: p.danger),
                              onPressed: () => _remove(d)),
                        ])
                      : null,
                ),
            ]),
        ]);
      },
    );
  }
}

class _DocUploadForm extends StatefulWidget {
  final String fileName;
  final Future<dynamic> Function(String name, String category, bool visible) send;
  const _DocUploadForm({required this.fileName, required this.send});

  @override
  State<_DocUploadForm> createState() => _DocUploadFormState();
}

class _DocUploadFormState extends State<_DocUploadForm> {
  late final _name = TextEditingController(text: widget.fileName);
  String _category = 'Other';
  bool _visible = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.send(_name.text, _category, _visible);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorText(e));
        showToast(context, errorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTextField(controller: _name, label: 'Document Name'),
      kFieldGap,
      AppDropdown<String>(
        label: 'Category',
        value: _category,
        items: [for (final c in _docCats) (c, c)],
        onChanged: (v) => setState(() => _category = v ?? _category),
      ),
      const SizedBox(height: 4),
      SwitchRow(label: 'Client visible', value: _visible, onChanged: (v) => setState(() => _visible = v)),
      const SizedBox(height: 14),
      SheetError(_error),
      SubmitButton(label: 'Upload', icon: Icons.upload_outlined, busy: _saving, onPressed: _submit),
    ]);
  }
}
