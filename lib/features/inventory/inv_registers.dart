part of 'inventory_screen.dart';

// The issue log (GET /inventory/issues) and the transfer register (GET /inventory/transfers), with the
// web's filters (status as chips, the rest in a filter sheet), totals, CSV export and transfer receipt.

Map<String, String> _activeParams(Map<String, String> f) => {
      for (final e in f.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };

/// [(id, name)] of everyone who appears in [rows] under [idKey] / [nameKey] (web `people`).
List<(String, String)> _peopleOf(List<_Json> rows, String idKey, String nameKey) {
  final seen = <String, String>{};
  for (final r in rows) {
    if (r[idKey] != null) seen['${r[idKey]}'] = (r[nameKey] ?? '#${r[idKey]}').toString();
  }
  return [for (final e in seen.entries) (e.key, e.value)];
}

/// Status chips row plus a "Filters" button showing how many other filters are on.
class _FilterHeader extends StatelessWidget {
  final String status;
  final List<(String, String)> statusOptions;
  final ValueChanged<String> onStatus;
  final int activeCount;
  final VoidCallback onFilters;
  final VoidCallback? onClear;
  const _FilterHeader({
    required this.status,
    required this.statusOptions,
    required this.onStatus,
    required this.activeCount,
    required this.onFilters,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      decoration: BoxDecoration(color: p.bg, border: Border(bottom: BorderSide(color: p.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilterBar<String>(value: status, options: statusOptions, onChanged: onStatus, padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 0)),
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 4, 8, 6),
          child: Row(children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: onFilters,
              icon: const Icon(Icons.tune, size: 18),
              label: Text(activeCount > 0 ? 'Filters ($activeCount)' : 'Filters'),
            ),
            const Spacer(),
            if (onClear != null) TextButton(onPressed: onClear, child: const Text('Clear')),
          ]),
        ),
      ]),
    );
  }
}

/// Bold-number summary line items (web il-summary / tr-summary).
class _SummaryWrap extends StatelessWidget {
  final List<(String, String, Color?)> items;
  const _SummaryWrap(this.items);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 8),
      child: Wrap(spacing: 16, runSpacing: 4, children: [
        for (final (n, text, color) in items)
          Text.rich(
            TextSpan(children: [
              TextSpan(text: n, style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' $text'),
            ]),
            style: tabular(tt.bodySmall).copyWith(color: color ?? p.fgMuted),
          ),
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────── issue log

const _emptyIssueFilters = {
  'status': '',
  'project_id': '',
  'location_id': '',
  'material_id': '',
  'issued_by': '',
  'date_from': '',
  'date_to': '',
  'self_approved': '',
};

Tone _issueTone(String? s) => switch (s) {
      'Pending' => Tone.warning,
      'Posted' => Tone.success,
      'Rejected' => Tone.danger,
      _ => Tone.neutral,
    };

/// The register of every stock issue: what left the store, how much, for which project and phase, who issued it,
/// who approved it and when, at what cost. Nothing here can be edited or deleted (web IssueLog).
class _IssueLog extends StatefulWidget {
  final _InvData data;
  final int rev;
  const _IssueLog({required this.data, required this.rev});

  @override
  State<_IssueLog> createState() => _IssueLogState();
}

class _IssueLogState extends State<_IssueLog> {
  Map<String, String> _f = Map.of(_emptyIssueFilters);
  List<(String, String)> _people = [];
  int? _peopleRev;

  @override
  void didUpdateWidget(covariant _IssueLog oldWidget) {
    super.didUpdateWidget(oldWidget);
    // a project picked under another company drops out when the header's company / branch changes
    final pid = _f['project_id']!;
    if (pid.isNotEmpty && !widget.data.pickable.any((p) => '${p['id']}' == pid)) {
      _f = {..._f, 'project_id': ''};
    }
  }

  Future<_Json> _load() async {
    final api = context.read<ApiClient>();
    final params = _activeParams(_f);
    final res = Map<String, dynamic>.from(await api.get('/inventory/issues', params: params) as Map);
    if (params.isEmpty) {
      _people = _peopleOf(_list(res['issues']), 'issued_by_id', 'issued_by');
      _peopleRev = widget.rev;
    } else if (_peopleRev != widget.rev) {
      final all = Map<String, dynamic>.from(await api.get('/inventory/issues') as Map);
      _people = _peopleOf(_list(all['issues']), 'issued_by_id', 'issued_by');
      _peopleRev = widget.rev;
    }
    return res;
  }

  Future<void> _openFilters() async {
    final d = widget.data;
    final local = Map.of(_f);
    final res = await showAppSheet<Map<String, String>>(
      context,
      title: 'Filter issues',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: DateField(label: 'From', value: local['date_from'], onChanged: (v) => set(() => local['date_from'] = v ?? '')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DateField(label: 'To', value: local['date_to'], onChanged: (v) => set(() => local['date_to'] = v ?? '')),
            ),
          ]),
          kFieldGap,
          AppDropdown<String>(
            label: 'Project',
            value: local['project_id'],
            items: [('', 'All'), for (final p in d.pickable) ('${p['id']}', '${p['name']}')],
            onChanged: (v) => set(() => local['project_id'] = v ?? ''),
          ),
          kFieldGap,
          _GroupedDropdown(
            label: 'Warehouse',
            value: local['location_id']!,
            noneLabel: 'All',
            groups: _locationGroups(d),
            onChanged: (v) => set(() => local['location_id'] = v),
          ),
          kFieldGap,
          AppDropdown<String>(
            label: 'Material',
            value: local['material_id'],
            items: [('', 'All'), for (final m in d.materials) ('${m['id']}', '${m['name']}')],
            onChanged: (v) => set(() => local['material_id'] = v ?? ''),
          ),
          kFieldGap,
          AppDropdown<String>(
            label: 'Issued by',
            value: local['issued_by'],
            items: [('', 'Anyone'), ..._people],
            onChanged: (v) => set(() => local['issued_by'] = v ?? ''),
          ),
          kFieldGap,
          AppDropdown<String>(
            label: 'Approval',
            value: local['self_approved'],
            items: const [('', 'All'), ('true', 'Self-approved only'), ('false', 'Approved by someone else')],
            onChanged: (v) => set(() => local['self_approved'] = v ?? ''),
          ),
          const SizedBox(height: 20),
          SubmitButton(label: 'Apply filters', onPressed: () => Navigator.pop(ctx, local)),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx, Map.of(_emptyIssueFilters)),
              child: const Text('Clear'),
            ),
          ),
        ]),
      ),
    );
    if (res != null && mounted) setState(() => _f = res);
  }

  void _export(List<_Json> rows) {
    _shareCsv(
      context,
      'stock-issues-${todayIso()}.csv',
      ['Date', 'Material', 'Quantity', 'Unit', 'From', 'Project', 'Phase', 'Value', 'Issued by', 'Approved by', 'Self-approved', 'Status', 'Notes'],
      [
        for (final r in rows)
          [
            fmtDateTime(r['requested_at'], empty: ''),
            r['material_name'],
            inputNum(r['quantity']),
            r['unit'],
            r['from_location'],
            r['project_name'],
            r['phase_name'],
            inputNum(r['total_cost']),
            r['issued_by'],
            r['approved_by'],
            r['self_approved'] == true ? 'yes' : '',
            r['status'],
            r['notes'],
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final params = _activeParams(_f);
    final others = params.keys.where((k) => k != 'status').length;
    return Column(children: [
      _FilterHeader(
        status: _f['status']!,
        statusOptions: const [('', 'All'), ('Pending', 'Pending'), ('Posted', 'Posted'), ('Rejected', 'Rejected')],
        onStatus: (v) => setState(() => _f = {..._f, 'status': v}),
        activeCount: others,
        onFilters: _openFilters,
        onClear: params.isEmpty ? null : () => setState(() => _f = Map.of(_emptyIssueFilters)),
      ),
      Expanded(
        child: AsyncView<_Json>(
          depKey: '${widget.rev}|$params',
          load: _load,
          builder: (context, data, reload) {
            final rows = _list(data['issues']);
            final t = Map<String, dynamic>.from(data['totals'] as Map? ?? const {});
            final p = context.pal;
            return RefreshList(onRefresh: reload, children: [
              _SummaryWrap([
                ('${t['count'] ?? 0}', 'issues', null),
                ('${t['pending'] ?? 0}', 'pending approval', p.warning),
                ('${t['posted'] ?? 0}', 'posted, worth ${inr(t['posted_value'])}', null),
                ('${t['rejected'] ?? 0}', 'rejected', null),
                ('${t['self_approved'] ?? 0}', 'self-approved', toNum(t['self_approved']) > 0 ? p.danger : null),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: rows.isEmpty ? null : () => _export(rows),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Export CSV'),
                  ),
                ),
              ),
              if (rows.isEmpty)
                const EmptyState(icon: Icons.receipt_long_outlined, title: 'No stock issues match.')
              else
                RowGroup(children: [for (final r in rows) _IssueRow(r)]),
              Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 0),
                child: Text(
                  'Every issue is recorded with who raised it and who approved it, and cannot be edited or deleted. Showing the latest 1,000 matches.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ]);
          },
        ),
      ),
    ]);
  }
}

class _IssueRow extends StatelessWidget {
  final _Json r;
  const _IssueRow(this.r);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final posted = r['status'] == 'Posted';
    final role = r['issued_by_role'] as String?;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(dash(r['material_name']), style: tt.titleSmall)),
          const SizedBox(width: 10),
          Text('${qty(r['quantity'])} ${r['unit'] ?? ''}',
              style: tabular(tt.titleSmall).copyWith(fontWeight: FontWeight.w700)),
        ]),
        if ((r['notes'] ?? '').toString().isNotEmpty) Text('${r['notes']}', style: tt.bodySmall),
        const SizedBox(height: 4),
        Text(
          '${dash(r['project_name'])}${r['phase_name'] != null ? ' · ${r['phase_name']}' : ''}',
          style: tt.bodyMedium,
        ),
        Text('From ${dash(r['from_location'])}', style: tt.bodySmall),
        const SizedBox(height: 8),
        Row(children: [
          StatusChip(r['status'] as String?, label: '${r['status'] ?? ''}', tone: _issueTone(r['status'] as String?), dense: true),
          if (r['self_approved'] == true) ...[
            const SizedBox(width: 6),
            const StatusChip(null, label: 'Self-approved', tone: Tone.danger, dense: true),
          ],
          const Spacer(),
          Text(posted ? inr(r['total_cost']) : '—',
              style: tabular(tt.titleSmall).copyWith(color: posted ? p.fg : p.fgSubtle)),
        ]),
        const SizedBox(height: 4),
        _Meta('When', fmtDateTime(r['requested_at'])),
        _Meta('Issued by', r['issued_by'] as String?, sub: role == null ? null : humanize(role)),
        _Meta('Approved by', r['approved_by'] as String?, sub: r['approved_by'] != null ? fmtDateTime(r['decided_at']) : null),
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────── transfers

// Every transfer is confirmed at both ends: the sender's stock leaves on approval, the destination only
// gets it once its engineer (or a supervisor) confirms receipt here.
const _directionLabel = {
  'wh_to_site': 'Warehouse → Site',
  'site_to_wh': 'Site → Warehouse',
  'site_to_site': 'Site → Site',
  'wh_to_wh': 'Warehouse → Warehouse',
};

Tone _transferTone(String? s) => switch (s) {
      'Pending' => Tone.warning,
      'InTransit' => Tone.info,
      'Posted' => Tone.success,
      'Returned' => Tone.orange,
      'Rejected' => Tone.danger,
      _ => Tone.neutral,
    };

const _emptyTransferFilters = {
  'status': '',
  'direction': '',
  'material_id': '',
  'sent_by': '',
  'date_from': '',
  'date_to': '',
  'overdue': '',
};

/// Every transfer between stores, one card per cart, with who sent, approved and received or declined it,
/// how long it has been in transit (flagged overdue), and Confirm receipt / Decline (web TransferRegister).
class _TransferRegister extends StatefulWidget {
  final _InvData data;
  final int rev;
  final bool isAdmin;
  final Future<void> Function() onDone;
  const _TransferRegister({required this.data, required this.rev, required this.isAdmin, required this.onDone});

  @override
  State<_TransferRegister> createState() => _TransferRegisterState();
}

class _TransferRegisterState extends State<_TransferRegister> {
  Map<String, String> _f = Map.of(_emptyTransferFilters);
  List<(String, String)> _people = [];
  int? _peopleRev;
  String? _busy;

  Future<_Json> _load() async {
    final api = context.read<ApiClient>();
    final params = _activeParams(_f);
    final res = Map<String, dynamic>.from(await api.get('/inventory/transfers', params: params) as Map);
    if (params.isEmpty) {
      _people = _peopleOf(_list(res['transfers']), 'sent_by_id', 'sent_by');
      _peopleRev = widget.rev;
    } else if (_peopleRev != widget.rev) {
      final all = Map<String, dynamic>.from(await api.get('/inventory/transfers') as Map);
      _people = _peopleOf(_list(all['transfers']), 'sent_by_id', 'sent_by');
      _peopleRev = widget.rev;
    }
    return res;
  }

  Future<void> _act(String key, int id, String action) async {
    if (action == 'decline') {
      final ok = await confirmDialog(context,
          title: 'Decline this transfer?',
          message: 'The stock is returned to the source store.',
          confirmLabel: 'Decline',
          destructive: true);
      if (!ok || !mounted) return;
    }
    setState(() => _busy = key);
    final ok = await runAction(
      context,
      () => context.read<ApiClient>().post('/inventory/movements/$id/$action'),
      success: action == 'receive'
          ? 'Receipt confirmed — stock added at the destination'
          : 'Transfer declined — stock returned to the source',
    );
    if (!mounted) return;
    setState(() => _busy = null);
    if (ok) await widget.onDone();
  }

  Future<void> _openFilters() async {
    final d = widget.data;
    final local = Map.of(_f);
    final res = await showAppSheet<Map<String, String>>(
      context,
      title: 'Filter transfers',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: DateField(label: 'From', value: local['date_from'], onChanged: (v) => set(() => local['date_from'] = v ?? '')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DateField(label: 'To', value: local['date_to'], onChanged: (v) => set(() => local['date_to'] = v ?? '')),
            ),
          ]),
          kFieldGap,
          AppDropdown<String>(
            label: 'Direction',
            value: local['direction'],
            items: [('', 'All'), for (final e in _directionLabel.entries) (e.key, e.value)],
            onChanged: (v) => set(() => local['direction'] = v ?? ''),
          ),
          kFieldGap,
          AppDropdown<String>(
            label: 'Material',
            value: local['material_id'],
            items: [('', 'All'), for (final m in d.materials) ('${m['id']}', '${m['name']}')],
            onChanged: (v) => set(() => local['material_id'] = v ?? ''),
          ),
          kFieldGap,
          AppDropdown<String>(
            label: 'Sent by',
            value: local['sent_by'],
            items: [('', 'Anyone'), ..._people],
            onChanged: (v) => set(() => local['sent_by'] = v ?? ''),
          ),
          SwitchRow(
            label: 'Overdue only',
            value: local['overdue'] == 'true',
            onChanged: (v) => set(() => local['overdue'] = v ? 'true' : ''),
          ),
          const SizedBox(height: 16),
          SubmitButton(label: 'Apply filters', onPressed: () => Navigator.pop(ctx, local)),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx, Map.of(_emptyTransferFilters)),
              child: const Text('Clear'),
            ),
          ),
        ]),
      ),
    );
    if (res != null && mounted) setState(() => _f = res);
  }

  void _export(List<_Json> rows) {
    _shareCsv(
      context,
      'stock-transfers-${todayIso()}.csv',
      ['Sent', 'Material', 'Quantity', 'Unit', 'From', 'To', 'Direction', 'Status', 'Days in transit', 'Sent by', 'Approved by', 'Received / declined by', 'Received / declined at', 'Notes'],
      [
        for (final r in rows)
          [
            fmtDateTime(r['requested_at'], empty: ''),
            r['material_name'],
            inputNum(r['quantity']),
            r['unit'],
            (r['from'] as Map?)?['label'],
            (r['to'] as Map?)?['label'],
            _directionLabel[r['direction']],
            r['status_label'],
            r['days_in_transit'],
            r['sent_by'],
            r['approved_by'],
            r['received_by'],
            fmtDateTime(r['received_at'], empty: ''),
            r['notes'],
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final params = _activeParams(_f);
    final others = params.keys.where((k) => k != 'status').length;
    return Column(children: [
      _FilterHeader(
        status: _f['status']!,
        statusOptions: const [
          ('', 'All'),
          ('Pending', 'Awaiting approval'),
          ('InTransit', 'In transit'),
          ('Posted', 'Received'),
          ('Returned', 'Declined'),
          ('Rejected', 'Rejected'),
        ],
        onStatus: (v) => setState(() => _f = {..._f, 'status': v}),
        activeCount: others,
        onFilters: _openFilters,
        onClear: params.isEmpty ? null : () => setState(() => _f = Map.of(_emptyTransferFilters)),
      ),
      Expanded(
        child: AsyncView<_Json>(
          depKey: '${widget.rev}|$params',
          load: _load,
          builder: (context, data, reload) {
            final rows = _list(data['transfers']);
            final t = Map<String, dynamic>.from(data['totals'] as Map? ?? const {});
            final p = context.pal;
            // one card per cart (movements submitted together share a batch and are decided together)
            final carts = _groupBatches(rows);
            final inTransitValue = toNum(t['in_transit_value']);
            return RefreshList(onRefresh: reload, children: [
              _SummaryWrap([
                ('${t['pending'] ?? 0}', 'awaiting approval', p.warning),
                ('${t['in_transit'] ?? 0}', 'in transit${inTransitValue != 0 ? ', worth ${inr(inTransitValue)}' : ''}', p.info),
                ('${t['overdue'] ?? 0}', 'overdue (over ${data['overdue_after_days'] ?? 3} days)', toNum(t['overdue']) > 0 ? p.danger : null),
                ('${t['received'] ?? 0}', 'received', null),
                ('${toInt(t['declined']) + toInt(t['rejected'])}', 'declined or rejected', null),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: rows.isEmpty ? null : () => _export(rows),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Export CSV'),
                  ),
                ),
              ),
              if (carts.isEmpty)
                const EmptyState(
                  icon: Icons.swap_horiz,
                  title: 'No transfers match.',
                  message:
                      'Stock leaves the source when a transfer is approved and reaches the destination only after it confirms receipt.',
                ),
              for (final c in carts) _TransferCard(
                cart: c,
                isAdmin: widget.isAdmin,
                busy: _busy == c.key,
                onAct: (action) => _act(c.key, c.first['id'] as int, action),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 0),
                child: Text(
                  'Every transfer is recorded with who sent it, who approved it and who received or declined it, and cannot be edited or deleted. Showing the latest 1,000 matches.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ]);
          },
        ),
      ),
    ]);
  }
}

class _TransferCard extends StatelessWidget {
  final _Batch cart;
  final bool isAdmin;
  final bool busy;
  final ValueChanged<String> onAct;
  const _TransferCard({required this.cart, required this.isAdmin, required this.busy, required this.onAct});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final first = cart.first;
    final lines = cart.lines;
    final status = first['status'] as String?;
    final overdue = first['overdue'] == true;
    final days = toInt(first['days_in_transit']);
    final from = Map<String, dynamic>.from(first['from'] as Map? ?? const {});
    final to = Map<String, dynamic>.from(first['to'] as Map? ?? const {});

    return Surface(
      margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
      borderColor: overdue ? p.toneBorder(Tone.danger) : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(fmtDateTime(first['requested_at']), style: tabular(tt.bodySmall))),
          StatusChip(status,
              label: status == 'Returned' ? 'Declined' : '${first['status_label'] ?? status ?? ''}',
              tone: _transferTone(status),
              dense: true),
        ]),
        const SizedBox(height: 8),
        for (final m in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              Expanded(child: Text(dash(m['material_name']), style: tt.titleSmall)),
              Text('${qty(m['quantity'])} ${m['unit'] ?? ''}', style: tabular(tt.bodyMedium).copyWith(fontWeight: FontWeight.w600)),
            ]),
          ),
        if ((first['notes'] ?? '').toString().isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 2), child: Text('${first['notes']}', style: tt.bodySmall)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: p.muted, borderRadius: BorderRadius.circular(Radii.control)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dash(from['label']), style: tt.bodyMedium),
            Icon(Icons.arrow_downward, size: 16, color: p.fgSubtle),
            Text(dash(to['label']), style: tt.bodyMedium),
            const SizedBox(height: 6),
            CodeTag((_directionLabel[first['direction']] ?? '').toUpperCase()),
          ]),
        ),
        if (status == 'Returned')
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('Stock went back to the source', style: tt.bodySmall)),
        if (status == 'InTransit')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${days == 0 ? 'Left today' : 'In transit $days day${days > 1 ? 's' : ''}'}${overdue ? ' — overdue' : ''}',
              style: tt.bodySmall?.copyWith(
                  color: overdue ? p.danger : null, fontWeight: overdue ? FontWeight.w700 : null),
            ),
          ),
        if (status == 'Pending')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(isAdmin ? 'Approve it in the Approvals tab.' : 'A supervisor must approve it.', style: tt.bodySmall),
          ),
        const SizedBox(height: 4),
        _Meta('Sent by', first['sent_by'] as String?),
        _Meta('Approved by', first['approved_by'] as String?,
            sub: first['approved_by'] != null ? fmtDateTime(first['decided_at']) : null),
        _Meta('Received / declined by', first['received_by'] as String?,
            sub: first['received_by'] != null ? fmtDateTime(first['received_at']) : null),
        if (status == 'InTransit' && first['can_receive'] == true) ...[
          const SizedBox(height: 12),
          _DecisionButtons(
            okLabel: 'Confirm receipt${lines.length > 1 ? ' (${lines.length})' : ''}',
            noLabel: 'Decline',
            busy: busy,
            onOk: () => onAct('receive'),
            onNo: () => onAct('decline'),
          ),
        ],
        if (status == 'InTransit' && first['can_receive'] != true)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Waiting for the destination to confirm', style: tt.bodySmall),
          ),
      ]),
    );
  }
}
