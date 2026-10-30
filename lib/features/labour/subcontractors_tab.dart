import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import 'contractor_work.dart';
import 'labour_shared.dart';

/// Project → Subcontractors tab (web SubcontractorsTab.jsx + SubcontractorPaymentModal.jsx + ContractorWork.jsx).
/// Each subcontractor has a contract value, what has been paid, and what is due (contract − paid). "Make payment"
/// records an Advance / Partial payment or the one that clears it (Full when nothing was paid before, Final after).
/// That money lives only in commitment payments (the project's procurement cost), never as an expense.
/// Embedded in the project's TabBarView: no Scaffold, scrolls itself, pull-to-refresh.
class SubcontractorsTab extends StatefulWidget {
  final int projectId;
  const SubcontractorsTab({super.key, required this.projectId});

  @override
  State<SubcontractorsTab> createState() => _SubcontractorsTabState();
}

const _payers = ['Admin', 'Accountant']; // mirrors the API (same as employee wage payments)

class _SubcontractorsTabState extends State<SubcontractorsTab> {
  int? _history; // subcontract whose payments are shown
  int? _crew; // subcontract whose crew log is shown
  final Map<int, int?> _pick = {}; // allocation id → contract chosen to link
  int _tick = 0;
  final _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  int get _pid => widget.projectId;

  Future<Map<String, dynamic>> _load() async =>
      Map<String, dynamic>.from(await context.read<ApiClient>().get('/projects/$_pid/subcontractors/overview') as Map);

  Future<void> _refresh() async {
    setState(() => _tick++);
    await _view.currentState?.reload();
  }

  Future<void> _act(Future<void> Function() fn, String ok) async {
    if (await runAction(context, fn, success: ok)) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final isAdmin = user?.role == 'Admin';
    final canPay = user?.roleIn(_payers) ?? false;
    return AsyncView<Map<String, dynamic>>(
      key: _view,
      load: _load,
      builder: (ctx, data, reload) => _body(context, data, isAdmin, canPay),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> data, bool isAdmin, bool canPay) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final t = asMap(data['totals']) ?? const {};
    final rows = asMaps(data['subcontracts']);
    final unlinked = asMaps(data['unlinked_allocations']);
    final withoutBudget = rows.where((r) => r['allocation_id'] == null).toList();

    return RefreshList(onRefresh: _refresh, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 8),
        child: Text(
          'Add each subcontractor with their contract value, then pay them from here (Advance, Partial or Full). '
          'Due is the contract value less what you have paid.',
          style: tt.bodySmall,
        ),
      ),
      if (isAdmin)
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
          child: SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: () async {
                if (await _showAddSubcontractor(context, _pid, unlinked)) _refresh();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add subcontractor'),
            ),
          ),
        ),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kGutter),
          child: Surface(
            child: EmptyState(
              icon: Icons.handshake_outlined,
              title: 'No subcontractors on this project yet.',
              message: isAdmin ? 'Use “Add subcontractor” above to add the first one.' : null,
            ),
          ),
        ),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
          child: _row(context, r, isAdmin, canPay),
        ),
      if (rows.isNotEmpty)
        RowGroup(children: [
          Container(
            color: p.muted,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Eyebrow('Total${toNum(t['budget']) != 0 ? ' · budget planned ${inr(t['budget'])}' : ''}'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Fig('Contract value', inr(t['contract_value']), large: true)),
                Expanded(child: Fig('NMR', toNum(t['nmr']) != 0 ? inr(t['nmr']) : '—', large: true)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Fig('Paid', inr(t['paid']), color: p.success, large: true)),
                Expanded(child: Fig('Due', inr(t['due']), color: p.danger, large: true)),
              ]),
            ]),
          ),
        ]),
      const Note(
        'Only what you pay counts as money out in the balance sheet. Draft contracts are listed but not counted until executed. '
        "NMR is your own daily labour put on a contractor's work: on a rate-basis contract it is deducted from what they are owed; "
        'on a labour-basis contract it is shown only.',
        padding: EdgeInsets.fromLTRB(kGutter, 10, kGutter, 4),
      ),
      PaymentRequestsPanel(projectId: _pid, reloadKey: _tick, onChanged: () => _view.currentState?.reload()),
      if (unlinked.isNotEmpty) ...[
        const SectionHeader('Planned budgets without a contract'),
        RowGroup(children: [
          for (final a in unlinked) _allocRow(context, a, isAdmin, withoutBudget),
        ]),
      ],
    ]);
  }

  Widget _row(BuildContext context, Map<String, dynamic> r, bool isAdmin, bool canPay) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final id = r['subcontract_id'] as int;
    final counted = r['counted'] == true;
    final due = toNum(r['due']);
    final paid = toNum(r['paid']);
    final nmr = toNum(r['nmr']);
    final rates = asMap(r['labour_rates']) ?? const {};
    final sub = [
      (r['number'] ?? '').toString(),
      if ((r['trade'] ?? '').toString().isNotEmpty) r['trade'],
      if ((r['scope_of_work'] ?? '').toString().isNotEmpty) r['scope_of_work'],
    ].join(' · ');
    final basis = r['basis'] == 'labour'
        ? 'Labour basis · ${qty(r['man_days'] ?? 0)} man-days · ${rates.entries.map((e) => '${e.key} ${inr(e.value)}').join(', ')}'
        : 'Rate basis';

    Widget action;
    if (!counted) {
      action = isAdmin && r['status'] != 'Terminated'
          ? SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () => _act(() => context.read<ApiClient>().post('/subcontracts/$id/execute'), 'Subcontract executed'),
                child: const Text('Execute'),
              ),
            )
          : const SizedBox.shrink();
    } else if (due > 0) {
      action = SizedBox(
        height: 48,
        child: canPay
            ? FilledButton.icon(
                onPressed: () async {
                  if (await _showSubcontractorPayment(context, r)) _refresh();
                },
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Make payment'),
              )
            : OutlinedButton.icon(
                onPressed: () async {
                  if (await showRequestPayment(context, r)) _refresh();
                },
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Ask to pay'),
              ),
      );
    } else {
      // How the contract was cleared (Full or Final payment); "Paid in full" only for older records without a type.
      action = Align(
        alignment: Alignment.centerLeft,
        child: StatusChip('paid', label: (r['closing_payment_type'] ?? 'Paid in full').toString()),
      );
    }

    return Surface(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text((r['vendor_name'] ?? r['number'] ?? '').toString(), style: tt.titleSmall),
            const SizedBox(height: 2),
            Text(sub, style: tt.bodySmall),
            Text(basis, style: tt.bodySmall),
            if (!counted)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${r['status']}: not counted until executed',
                    style: tt.bodySmall?.copyWith(color: p.warning, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Fig('Contract value', inr(r['contract_value']), color: r['over_budget'] == true ? p.danger : null),
                  if (r['budget'] != null)
                    Text('${r['over_budget'] == true ? 'over ' : ''}budget ${inr(r['budget'])}', style: tt.bodySmall),
                  if (r['basis'] == 'labour') Text('earned so far', style: tt.bodySmall),
                ]),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Fig('NMR', nmr != 0 ? inr(nmr) : '—'),
                  if (nmr > 0) Text(toNum(r['nmr_deducted']) != 0 ? 'deducted' : 'shown only', style: tt.bodySmall),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Fig('Paid', inr(paid), color: p.success)),
              Expanded(child: Fig('Due', counted ? inr(due) : '—', color: due > 0 ? p.danger : p.fgSubtle)),
            ]),
            const SizedBox(height: 12),
            action,
          ]),
        ),
        if (paid > 0 || counted) ...[
          Divider(height: 1, color: p.border),
          Row(children: [
            if (paid > 0)
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() {
                    _crew = null;
                    _history = _history == id ? null : id;
                  }),
                  child: Text(_history == id ? 'Hide payments' : 'View payments'),
                ),
              ),
            if (counted)
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() {
                    _history = null;
                    _crew = _crew == id ? null : id;
                  }),
                  child: Text(_crew == id ? 'Hide crew' : 'Crew & photos'),
                ),
              ),
          ]),
        ],
        if (_history == id)
          Container(
            color: p.muted,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: _PaymentHistory(key: ValueKey('h$id$_tick'), subId: id),
          ),
        if (_crew == id)
          Container(
            color: p.muted,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: CrewLog(key: ValueKey('c$id$_tick'), subId: id),
          ),
      ]),
    );
  }

  Widget _allocRow(BuildContext context, Map<String, dynamic> a, bool isAdmin, List<Map<String, dynamic>> withoutBudget) {
    final tt = Theme.of(context).textTheme;
    final id = a['id'] as int;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: (a['type'] ?? '').toString(), style: tt.titleSmall),
              if ((a['name'] ?? '').toString().isNotEmpty) TextSpan(text: ' · ${a['name']}', style: tt.bodyMedium),
            ])),
          ),
          Text(inr(a['allocated_amount']), style: tabular(tt.titleSmall)),
        ]),
        if (isAdmin && withoutBudget.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: AppDropdown<int>(
                label: 'Link to subcontractor…',
                value: _pick[id],
                items: [
                  for (final c in withoutBudget) (c['subcontract_id'] as int, '${c['vendor_name'] ?? c['number']} · ${c['number']}'),
                ],
                onChanged: (v) => setState(() => _pick[id] = v),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _pick[id] == null
                    ? null
                    : () => _act(() => context.read<ApiClient>().patch('/subcontractors/$id', data: {'subcontract_id': _pick[id]}),
                        'Planned budget linked'),
                child: const Text('Link'),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────── payment history

/// Every payment made to one subcontractor, newest first.
class _PaymentHistory extends StatelessWidget {
  final int subId;
  const _PaymentHistory({super.key, required this.subId});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    return InlineAsync<List<Map<String, dynamic>>>(
      load: () async => asMaps(await context.read<ApiClient>().get('/commitments/subcontract/$subId/payments')),
      builder: (ctx, rows, _) {
        if (rows.isEmpty) return Text('No payments made yet.', style: tt.bodyMedium?.copyWith(color: p.fgMuted));
        // Payments from before 2026-10-15 were made against bills and have no payment type.
        String kind(Map<String, dynamic> x) =>
            (x['payment_type'] ?? (x['kind'] == 'retainage' ? 'Retainage release' : 'Bill payment')).toString();
        final total = rows.fold<double>(0, (s, x) => s + toNum(x['amount']));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Eyebrow('Payments made · ${rows.length} · ${inr(total)} in all'),
          const SizedBox(height: 8),
          RowGroup(
            margin: EdgeInsets.zero,
            children: [
              for (final x in rows)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(kind(x).toUpperCase(), style: tt.labelSmall),
                        const SizedBox(height: 2),
                        Text(fmtDate(x['payment_date']), style: tabular(tt.bodySmall)),
                        if ((x['notes'] ?? '').toString().isNotEmpty) Text(x['notes'].toString(), style: tt.bodySmall),
                      ]),
                    ),
                    Text(inr(x['amount']), style: tabular(tt.titleSmall)),
                  ]),
                ),
            ],
          ),
        ]);
      },
    );
  }
}

// ───────────────────────────────────────────────────────── make payment (SubcontractorPaymentModal.jsx)

Future<bool> _showSubcontractorPayment(BuildContext context, Map<String, dynamic> row) async {
  final r = await showAppSheet<bool>(
    context,
    title: 'Pay ${row['vendor_name'] ?? row['number']}',
    subtitle: "Counts as money out (Procurement) in this project's balance sheet and shows in the subcontractor's payment history.",
    builder: (ctx) => _SubPaymentForm(row: row),
  );
  return r == true;
}

class _SubPaymentForm extends StatefulWidget {
  final Map<String, dynamic> row;
  const _SubPaymentForm({required this.row});

  @override
  State<_SubPaymentForm> createState() => _SubPaymentFormState();
}

class _SubPaymentFormState extends State<_SubPaymentForm> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late String _ptype;
  bool _saving = false;
  bool _guard = false; // one tap = one payment
  String? _error;

  Map<String, dynamic> get _row => widget.row;
  double get _due => toNum(_row['due']);
  double get _paid => toNum(_row['paid']);
  String get _closing => _paid > 0 ? 'Final Payment' : 'Full Payment';
  double get _amt => toNum(_amount.text);
  bool get _tooMuch => _amt > _due + 0.005;

  @override
  void initState() {
    super.initState();
    _ptype = _paid > 0 ? 'Partial Payment' : 'Advance Payment';
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _pickType(String t) {
    setState(() {
      if (t == _closing) {
        _amount.text = inputNum(_due);
      } else if (_ptype == _closing) {
        _amount.text = '';
      }
      _ptype = t;
    });
  }

  void _typeAmount(String v) {
    setState(() {
      // Clearing the balance is the closing payment.
      if (v.isNotEmpty && (toNum(v) - _due).abs() <= 0.005) _ptype = _closing;
    });
  }

  Future<void> _submit() async {
    if (!(_amt > 0) || _tooMuch || _guard) return;
    _guard = true;
    setState(() {
      _saving = true;
      _error = null;
    });
    final name = (_row['vendor_name'] ?? _row['number']).toString();
    try {
      final data = await context.read<ApiClient>().post('/subcontracts/${_row['subcontract_id']}/payments', data: {
        'amount': _amt,
        'payment_type': _ptype,
        'notes': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      if (!mounted) return;
      final left = toNum((data as Map)['due']);
      showToast(context, 'Paid ${inr(_amt)} to $name · ${left > 0 ? '${inr(left)} still due' : 'paid in full'}');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorText(e);
      });
      showToast(context, errorText(e), error: true);
      Future.delayed(const Duration(milliseconds: 800), () => _guard = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final types = ['Advance Payment', 'Partial Payment', _closing];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FigBand(children: [
        Fig('Contract value', inr(_row['contract_value']), align: CrossAxisAlignment.center, large: true),
        Fig('Paid', inr(_paid), align: CrossAxisAlignment.center, large: true),
        Fig('Due', inr(_due), align: CrossAxisAlignment.center, large: true, color: _due > 0 ? p.danger : p.success),
      ]),
      const SizedBox(height: 16),
      AppTextField(
        controller: _amount,
        label: 'Amount (₹)',
        requiredField: true,
        money: true,
        enabled: _ptype != _closing,
        hint: 'Up to ${inr(_due)}',
        onChanged: _typeAmount,
      ),
      if (_tooMuch)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Only ${inr(_due)} is due on this contract.', style: tt.bodySmall?.copyWith(color: p.danger)),
        ),
      kFieldGap,
      ChoiceRow<String>(
        label: 'Payment Type *',
        value: _ptype,
        options: [for (final t in types) (t, t)],
        onChanged: _pickType,
      ),
      const SizedBox(height: 6),
      Text(
        _closing == 'Full Payment' ? 'Full Payment pays the whole contract at once.' : 'Final Payment clears the remaining ${inr(_due)}.',
        style: tt.bodySmall,
      ),
      kFieldGap,
      AppTextField(controller: _note, label: 'Note (optional)', hint: 'e.g. Wiring done on floor 1'),
      const SizedBox(height: 20),
      SheetError(_error),
      SubmitButton(label: 'Make Payment', busy: _saving, onPressed: _amt > 0 && !_tooMuch ? _submit : null),
    ]);
  }
}

// ───────────────────────────────────────────────────────── add subcontractor

const _newVendor = -1;

/// "Painter 900, Helper 600" → {Painter: 900, Helper: 600}: the labour-basis rate per man-day for each worker type.
Map<String, double> _parseRates(String text) {
  final out = <String, double>{};
  final re = RegExp(r'^(.+?)\s*[:=-]?\s*₹?\s*([\d.]+)$');
  for (final part in text.split(RegExp(r'[,\n]'))) {
    final m = re.firstMatch(part.trim());
    if (m == null) continue;
    final v = double.tryParse(m.group(2)!);
    if (v != null) out[m.group(1)!.trim()] = v;
  }
  return out;
}

Future<bool> _showAddSubcontractor(BuildContext context, int projectId, List<Map<String, dynamic>> unlinked) async {
  final r = await showAppSheet<bool>(
    context,
    title: 'Add subcontractor',
    subtitle: 'Add a subcontractor to this project',
    builder: (ctx) => _AddSubForm(projectId: projectId, unlinked: unlinked),
  );
  return r == true;
}

class _AddSubForm extends StatefulWidget {
  final int projectId;
  final List<Map<String, dynamic>> unlinked;
  const _AddSubForm({required this.projectId, required this.unlinked});

  @override
  State<_AddSubForm> createState() => _AddSubFormState();
}

class _AddSubFormState extends State<_AddSubForm> {
  List<Map<String, dynamic>>? _vendors;
  int? _vendorId;
  final _vendorName = TextEditingController();
  final _vendorPhone = TextEditingController();
  String? _insurance;
  final _scope = TextEditingController();
  String _basis = 'rate';
  final _value = TextEditingController();
  final _rates = TextEditingController();
  String? _start;
  String? _end;
  int? _allocationId;
  bool _execute = true;
  bool _busy = false;
  String? _error;

  bool get _creatingVendor => _vendorId == _newVendor;

  @override
  void initState() {
    super.initState();
    _loadVendors();
  }

  @override
  void dispose() {
    for (final c in [_vendorName, _vendorPhone, _scope, _value, _rates]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadVendors() async {
    try {
      final d = await context.read<ApiClient>().get('/vendors');
      if (mounted) setState(() => _vendors = asMaps(d));
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  bool get _valid =>
      _vendorId != null &&
      !(_creatingVendor && _vendorName.text.trim().isEmpty) &&
      (_basis == 'rate' ? _value.text.trim().isNotEmpty : _parseRates(_rates.text).isNotEmpty);

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      var vendorId = _vendorId!;
      if (_creatingVendor) {
        final v = await api.post('/vendors', data: {
          'name': _vendorName.text.trim(),
          'vendor_type': 'Subcontractor',
          'phone': _vendorPhone.text.isEmpty ? null : _vendorPhone.text,
          'insurance_expiry': _insurance,
        });
        vendorId = (v as Map)['id'] as int;
        // A retry after a later failure must not create the vendor twice.
        _vendorId = vendorId;
        await _loadVendors();
      }
      final sc = await api.post('/projects/${widget.projectId}/subcontracts', data: {
        'vendor_id': vendorId,
        'scope_of_work': _scope.text.trim().isEmpty ? null : _scope.text.trim(),
        'original_amount': _basis == 'labour' ? 0 : toNum(_value.text),
        'basis': _basis,
        'labour_rates': _basis == 'labour' ? _parseRates(_rates.text) : null,
        'start_date': _start,
        'end_date': _end,
        'status': _execute ? 'Executed' : 'Draft',
      });
      if (_allocationId != null) {
        await api.patch('/subcontractors/$_allocationId', data: {'subcontract_id': (sc as Map)['id']});
      }
      if (!mounted) return;
      showToast(context, _execute ? 'Subcontractor added' : 'Subcontractor saved as a draft (execute it to start paying)');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorText(e);
      });
      showToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final vendors = _vendors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (vendors == null && _error == null) const LinearProgressIndicator(minHeight: 2),
      AppDropdown<int>(
        label: 'Vendor',
        requiredField: true,
        hint: 'Select a vendor…',
        value: _vendorId,
        items: [
          for (final v in vendors ?? const <Map<String, dynamic>>[]) (v['id'] as int, (v['name'] ?? '').toString()),
          (_newVendor, '+ New vendor…'),
        ],
        onChanged: (v) => setState(() => _vendorId = v),
      ),
      if (_creatingVendor) ...[
        kFieldGap,
        AppTextField(
          controller: _vendorName,
          label: 'Vendor name',
          requiredField: true,
          hint: 'e.g. Sri Murugan Electricals',
          capitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
        ),
        kFieldGap,
        AppTextField(controller: _vendorPhone, label: 'Phone', hint: 'e.g. 98765 43210', keyboardType: TextInputType.phone),
        kFieldGap,
        DateField(
          label: 'Insurance valid until',
          value: _insurance,
          firstDate: toDate(todayIso()),
          onChanged: (v) => setState(() => _insurance = v),
        ),
      ],
      kFieldGap,
      AppTextField(
        controller: _scope,
        label: 'Scope of work',
        hint: 'e.g. Electrical wiring and fittings, floors 1 to 3',
        maxLines: 3,
        minLines: 1,
      ),
      kFieldGap,
      AppDropdown<String>(
        label: 'Works on',
        value: _basis,
        items: const [('rate', 'Rate basis (fixed value)'), ('labour', 'Labour basis (per man-day)')],
        onChanged: (v) => setState(() => _basis = v ?? 'rate'),
      ),
      kFieldGap,
      if (_basis == 'rate')
        AppTextField(
          controller: _value,
          label: 'Contract value (₹)',
          requiredField: true,
          money: true,
          hint: 'qty × rate, e.g. 500000',
          onChanged: (_) => setState(() {}),
        )
      else
        AppTextField(
          controller: _rates,
          label: 'Rate per man-day',
          requiredField: true,
          hint: 'e.g. Painter 900, Helper 600',
          capitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
        ),
      kFieldGap,
      Row(children: [
        Expanded(child: DateField(label: 'Start', value: _start, onChanged: (v) => setState(() => _start = v))),
        const SizedBox(width: 10),
        Expanded(child: DateField(label: 'End', value: _end, onChanged: (v) => setState(() => _end = v))),
      ]),
      if (widget.unlinked.isNotEmpty) ...[
        kFieldGap,
        AppDropdown<int?>(
          label: 'Planned budget (optional)',
          value: _allocationId,
          items: [
            (null, 'None'),
            for (final a in widget.unlinked)
              (
                a['id'] as int?,
                '${a['type']}${(a['name'] ?? '').toString().isNotEmpty ? ' · ${a['name']}' : ''} · ${inr(a['allocated_amount'])}'
              ),
          ],
          onChanged: (v) => setState(() => _allocationId = v),
        ),
      ],
      const SizedBox(height: 6),
      SwitchRow(label: 'Execute now', value: _execute, onChanged: (v) => setState(() => _execute = v)),
      Text(
        "A subcontractor can be paid once the contract is executed. Executing needs the vendor's insurance to be current; "
        'enter the insurance end date for a new vendor.',
        style: tt.bodySmall,
      ),
      const SizedBox(height: 20),
      SheetError(_error),
      SubmitButton(label: 'Add subcontractor', busy: _busy, onPressed: _valid ? _create : null),
    ]);
  }
}
