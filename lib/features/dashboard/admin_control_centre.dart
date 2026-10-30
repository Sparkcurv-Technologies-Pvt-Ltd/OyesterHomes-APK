import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../projects/project_common.dart';
import '../projects/project_detail_screen.dart';
import '../shell/routes.dart';

// The Admin's (MD's) one-screen view of everything (web AdminControlCentre.jsx, GET /dashboard/overview).

/// Whole rupees, as the web's `inr` here (`maximumFractionDigits: 0`).
String _inr(dynamic n) => inr(toNum(n).roundToDouble());

Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class _Kind {
  final String label;
  final IconData icon;
  final Tone tone;
  final String? approve;
  const _Kind(this.label, this.icon, this.tone, {this.approve});
}

const _kinds = <String, _Kind>{
  'requirement': _Kind('Requirement', Icons.assignment_outlined, Tone.warning),
  'requirement_po': _Kind('Needs PO', Icons.assignment_outlined, Tone.info),
  'contractor_release': _Kind('Release payment', Icons.account_balance_wallet_outlined, Tone.success, approve: 'Release'),
  'contractor_request': _Kind('Contractor payment', Icons.engineering_outlined, Tone.orange),
  'petty_cash': _Kind('Petty cash', Icons.account_balance_wallet_outlined, Tone.info),
  'stock_issue': _Kind('Stock issue', Icons.inventory_2_outlined, Tone.warning),
  'stock_transfer': _Kind('Transfer', Icons.swap_horiz, Tone.warning),
  'leave': _Kind('Leave', Icons.event_busy_outlined, Tone.info),
  'site_visit': _Kind('Site visit', Icons.location_on_outlined, Tone.info),
  'po_draft': _Kind('PO to issue', Icons.description_outlined, Tone.info),
  'quotation': _Kind('Quote, no PO', Icons.assignment_outlined, Tone.info),
  'change_order': _Kind('Change order', Icons.edit_note_outlined, Tone.success),
  'contract_draft': _Kind('Contract draft', Icons.engineering_outlined, Tone.orange),
  'contractor_bill': _Kind('Contractor bill', Icons.receipt_long_outlined, Tone.orange),
  'invoice_overdue': _Kind('Overdue invoice', Icons.warning_amber_rounded, Tone.danger),
};

/// A titled Surface (web Panel).
class _Panel extends StatelessWidget {
  final String title;
  final Widget? action;
  final Widget child;
  const _Panel({required this.title, this.action, required this.child});

  @override
  Widget build(BuildContext context) => Surface(
        margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: Eyebrow(title)), if (action != null) action!]),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

/// Accent text link ("Manage →").
class _Link extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _Link(this.text, this.onTap);

  @override
  Widget build(BuildContext context) => TextButton(
        style: TextButton.styleFrom(
          foregroundColor: context.pal.accentText,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(48, 40),
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        onPressed: onTap,
        child: Text(text),
      );
}

class AdminControlCentre extends StatelessWidget {
  final Map<String, dynamic> overview;
  final Future<void> Function() onRefresh;
  const AdminControlCentre({super.key, required this.overview, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final c = _m(o['counts']);
    final m = _m(o['money']);
    final r = _m(c['users_by_role']);
    final ongoing = toInt(_m(c['projects_by_status'])['Ongoing']);
    void go(String path) => openWebPath(context, path);
    final waiting = asMapList(o['waiting'] ?? const []);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrid(children: [
        KpiTile(label: 'Companies', value: '${c['companies'] ?? 0}', icon: Icons.domain_outlined, onTap: () => go('/admin/companies')),
        KpiTile(label: 'Branches', value: '${c['branches'] ?? 0}', icon: Icons.account_tree_outlined, onTap: () => go('/admin/companies')),
        KpiTile(
            label: 'Projects',
            value: '${c['projects'] ?? 0}',
            sub: '$ongoing ongoing · ${_inr(c['budget'])}',
            icon: Icons.folder_outlined,
            onTap: () => go('/admin/projects')),
        KpiTile(
            label: 'Users',
            value: '${c['users'] ?? 0}',
            sub: '${r['ProjectManager'] ?? 0} PM · ${r['SiteEngineer'] ?? 0} SE',
            icon: Icons.people_outline,
            onTap: () => go('/admin/users')),
        KpiTile(label: 'Clients', value: '${c['clients'] ?? 0}', icon: Icons.how_to_reg_outlined, onTap: () => go('/admin/clients')),
        KpiTile(
            label: 'Vendors',
            value: '${c['vendors'] ?? 0}',
            sub: '${c['purchase_orders'] ?? 0} POs',
            icon: Icons.local_shipping_outlined,
            onTap: () => go('/admin/procurement/vendors')),
        KpiTile(
            label: 'Contractors',
            value: '${c['contractors'] ?? 0}',
            sub: '${_inr(_m(m['contractors'])['due'])} due',
            icon: Icons.engineering_outlined,
            onTap: () => go('/admin/procurement/vendors')),
        KpiTile(
            label: 'Site labour',
            value: '${c['labour'] ?? 0}',
            sub: '${c['change_orders'] ?? 0} change orders',
            icon: Icons.groups_outlined,
            onTap: () => go('/admin/projects')),
      ]),
      const SizedBox(height: 12),
      _Panel(
        title: 'Waiting for you · ${waiting.length}',
        child: _WaitingList(items: waiting, counts: _m(o['waiting_counts']), onDone: onRefresh),
      ),
      _Panel(title: 'Today · ${fmtDate(o['today'])}', child: _TodayPanel(att: _m(o['attendance']))),
      _Panel(
        title: 'Money',
        action: Icon(Icons.account_balance_wallet_outlined, size: 16, color: context.pal.accentText),
        child: _MoneyPanel(m: m),
      ),
      if (o['costs'] != null) _CostsPanel(costs: _m(o['costs'])),
      _Panel(
        title: 'Companies → branches → projects',
        action: _Link('Manage →', () => go('/admin/companies')),
        child: _OrgTree(org: asMapList(o['org'] ?? const [])),
      ),
      _Panel(title: 'Contractor balances', child: _ContractorRows(rows: asMapList(o['contractors'] ?? const []))),
      _Panel(
        title: 'Recent purchase orders',
        child: _RecentRows(
          rows: asMapList(_m(o['recent'])['purchase_orders'] ?? const []),
          empty: 'No purchase orders yet.',
          number: 'po_number',
          title: (x) => dash(x['vendor']),
          amount: 'total',
        ),
      ),
      _Panel(
        title: 'Recent change orders',
        child: _RecentRows(
          rows: asMapList(_m(o['recent'])['change_orders'] ?? const []),
          empty: 'No change orders yet.',
          number: 'co_number',
          title: (x) => dash(x['title']),
          amount: 'amount',
        ),
      ),
    ]);
  }
}

// ───────────────────────────── waiting list

class _WaitingList extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> counts;
  final Future<void> Function() onDone;
  const _WaitingList({required this.items, required this.counts, required this.onDone});

  @override
  State<_WaitingList> createState() => _WaitingListState();
}

class _WaitingListState extends State<_WaitingList> {
  String _kind = '';
  String? _busy;

  String _key(Map<String, dynamic> w) => '${w['kind']}-${w['id']}';

  Future<void> _act(Map<String, dynamic> w, String verb, [Map<String, dynamic>? body]) async {
    final api = context.read<ApiClient>();
    if (verb == 'approve' && ['contractor_release', 'petty_cash'].contains(w['kind']) && body == null) {
      final b = await _askRelease(w);
      if (b == null) return;
      body = b;
    }
    if (verb == 'reject') {
      if (!mounted) return;
      final yes = await confirmDialog(context, title: 'Reject?', message: dash(w['title']), confirmLabel: 'Reject', destructive: true);
      if (!yes) return;
    }
    if (_busy != null || !mounted) return; // one tap = one action
    final path = _m(w['actions'])[verb]?.toString();
    if (path == null) return;
    setState(() => _busy = _key(w));
    final success = verb == 'approve'
        ? (_kinds[w['kind']]?.approve == 'Release' ? 'Payment released' : 'Approved')
        : 'Rejected';
    final ok = await runAction(context, () => api.post(path, data: body), success: success);
    if (!mounted) return;
    setState(() => _busy = null);
    if (ok) await widget.onDone();
  }

  /// Point 10: the MD checks and may change the amount before releasing / giving.
  Future<Map<String, dynamic>?> _askRelease(Map<String, dynamic> w) {
    final petty = w['kind'] == 'petty_cash';
    final amount = TextEditingController(text: inputNum(w['amount']));
    final note = TextEditingController();
    return showAppSheet<Map<String, dynamic>>(
      context,
      title: dash(w['title']),
      subtitle: '${dash(w['subtitle'])}. Asked ${_inr(w['amount'])} — change it if needed, then ${petty ? 'approve' : 'release'}.',
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final p = ctx.pal;
        final amt = toNum(amount.text);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppTextField(
            controller: amount,
            label: petty ? 'Amount to give (₹)' : 'Amount to release (₹)',
            money: true,
            autofocus: true,
            onChanged: (_) => set(() {}),
          ),
          kFieldGap,
          AppTextField(controller: note, label: 'Note (optional)', hint: 'e.g. Holding 10% till snag list'),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: p.success, foregroundColor: Colors.white),
              onPressed: amt > 0
                  ? () => Navigator.pop(ctx, {'amount': amt, 'note': note.text.isEmpty ? null : note.text})
                  : null,
              icon: const Icon(Icons.check, size: 18),
              label: Text('${petty ? 'Give' : 'Release'} ${_inr(amt)}'),
            ),
          ),
        ]);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final items = widget.items;
    final shown = _kind.isEmpty ? items : items.where((w) => w['kind'] == _kind).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilterBar<String>(
        padding: const EdgeInsets.only(bottom: 8),
        value: _kind,
        options: [
          ('', 'All ${items.length}'),
          for (final e in _kinds.entries)
            if (toInt(widget.counts[e.key]) > 0) (e.key, '${e.value.label} ${toInt(widget.counts[e.key])}'),
        ],
        onChanged: (v) => setState(() => _kind = v),
      ),
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(children: [
            Icon(Icons.inbox_outlined, color: p.fgSubtle),
            const SizedBox(height: 6),
            Text('Nothing is waiting. All clear.', style: tt.bodySmall),
          ]),
        )
      else
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) Divider(height: 1, color: p.border),
          _waitingRow(context, shown[i]),
        ],
    ]);
  }

  Widget _waitingRow(BuildContext context, Map<String, dynamic> w) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final k = _kinds[w['kind']] ?? _Kind(w['kind']?.toString() ?? '', Icons.inbox_outlined, Tone.neutral);
    final key = _key(w);
    final busy = _busy == key;
    final hasActions = w['actions'] is Map;
    final link = w['link']?.toString();
    final meta = [if (w['date'] != null) fmtDate(w['date']), if (w['by'] != null) w['by'].toString()].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(k.icon, size: 18, color: p.tone(k.tone))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Eyebrow(k.label, color: p.tone(k.tone))),
              if (meta.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(fontSize: 11))),
              ],
            ]),
            const SizedBox(height: 2),
            InkWell(
              onTap: link == null ? null : () => openWebPath(context, link),
              child: Text(dash(w['title']), style: tt.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            if (w['subtitle'] != null)
              Text(w['subtitle'].toString(), style: tt.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Row(children: [
              if (w['amount'] != null)
                Expanded(child: Text(_inr(w['amount']), style: tabular(tt.titleSmall)))
              else
                const Spacer(),
              if (hasActions) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: p.success,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: busy ? null : () => _act(w, 'approve'),
                  icon: busy
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, size: 16),
                  label: Text(k.approve ?? 'Approve'),
                ),
                const SizedBox(width: 6),
                IconButton.outlined(
                  tooltip: 'Reject',
                  onPressed: busy || _m(w['actions'])['reject'] == null ? null : () => _act(w, 'reject'),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ] else if (link != null)
                _Link('Open ›', () => openWebPath(context, link)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────────── today

const _staffParts = [
  ('present', 'Present', Tone.success),
  ('half_day', 'Half day', Tone.warning),
  ('leave', 'Leave', Tone.info),
  ('absent', 'Absent', Tone.danger),
  ('unmarked', 'Not marked', Tone.neutral),
];

class _TodayPanel extends StatelessWidget {
  final Map<String, dynamic> att;
  const _TodayPanel({required this.att});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final s = _m(att['staff']);
    final l = _m(att['labour']);
    Color col(Tone t) => t == Tone.neutral ? p.inputBorder : p.tone(t);
    final notMarked = asMapList(l['not_marked'] ?? const []);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Staff', style: tt.titleSmall)),
        Text('${s['total'] ?? 0} people', style: tt.bodySmall),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 10,
          child: Container(
            color: p.muted,
            child: Row(children: [
              for (final (k, _, t) in _staffParts)
                if (toInt(s[k]) > 0) Expanded(flex: toInt(s[k]), child: Container(color: col(t))),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 4, children: [
        for (final (k, label, t) in _staffParts)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: col(t), shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text('$label ', style: tt.bodySmall),
            Text('${s[k] ?? 0}', style: tabular(tt.bodySmall).copyWith(fontWeight: FontWeight.w700, color: p.fg)),
          ]),
      ]),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text('Site labour', style: tt.titleSmall)),
        Flexible(
          child: Text('${l['projects_marked'] ?? 0} of ${l['projects_ongoing'] ?? 0} ongoing sites marked',
              textAlign: TextAlign.right, style: tt.bodySmall),
        ),
      ]),
      const SizedBox(height: 4),
      Text.rich(TextSpan(style: tt.bodySmall, children: [
        TextSpan(text: '${l['present'] ?? 0}', style: tabular(tt.bodySmall).copyWith(fontWeight: FontWeight.w700, color: p.success)),
        const TextSpan(text: ' present · '),
        TextSpan(text: '${l['absent'] ?? 0}', style: tabular(tt.bodySmall).copyWith(fontWeight: FontWeight.w700, color: p.danger)),
        const TextSpan(text: ' absent'),
      ])),
      if (notMarked.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Not marked yet:', style: tt.bodySmall),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final pr in notMarked)
            TagChip(dash(pr['name']), onTap: () => push(context, ProjectDetailScreen(projectId: toInt(pr['id'])))),
        ]),
      ],
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: _Link('Open staff attendance →', () => openWebPath(context, '/admin/users?tab=attendance')),
      ),
    ]);
  }
}

// ───────────────────────────── money

class _MoneyPanel extends StatelessWidget {
  final Map<String, dynamic> m;
  const _MoneyPanel({required this.m});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final po = _m(m['purchase_orders']), sub = _m(m['contractors']), rc = _m(m['receivables']), co = _m(m['change_orders']);
    final youOwe = toNum(po['due']) + toNum(sub['due']);
    final poCount = toInt(po['count']);
    final overdueCount = toInt(rc['overdue_count']);

    Widget box(Tone tone, String label, dynamic value, String note) => Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(color: p.toneFill(tone), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Eyebrow(label, color: p.tone(tone)),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(_inr(value), style: tabular(tt.titleLarge).copyWith(fontWeight: FontWeight.w700))),
            Text(note, style: tt.bodySmall?.copyWith(fontSize: 11)),
          ]),
        );

    Widget coBox(String label, dynamic v, {bool warn = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(6)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: tt.bodySmall),
              Text(_inr(v),
                  style: tabular(tt.titleSmall).copyWith(color: warn && toNum(v) > 0 ? p.accentText : null)),
            ]),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: box(Tone.accent, 'You still pay', youOwe, 'vendors + contractors')),
        const SizedBox(width: 8),
        Expanded(child: box(Tone.success, 'Clients still owe', rc['outstanding'], 'on invoices sent')),
      ]),
      const SizedBox(height: 8),
      _MoneyGroup(
        title: 'Vendors',
        note: '$poCount purchase order${poCount == 1 ? '' : 's'}',
        done: toNum(po['paid']),
        total: toNum(po['total']),
        doneWord: 'Paid',
        leftWord: 'to pay',
      ),
      Divider(height: 1, color: p.border),
      _MoneyGroup(
        title: 'Contractors',
        note: 'signed contracts',
        done: toNum(sub['paid']),
        total: toNum(sub['contract_value']),
        doneWord: 'Paid',
        leftWord: 'to pay',
      ),
      Divider(height: 1, color: p.border),
      _MoneyGroup(
        title: 'Client invoices',
        note: 'money coming in',
        done: toNum(rc['received']),
        total: toNum(rc['invoiced']),
        doneWord: 'Received',
        leftWord: 'to collect',
        alert: overdueCount > 0
            ? '${_inr(rc['overdue'])} overdue on $overdueCount invoice${overdueCount == 1 ? '' : 's'}'
            : null,
      ),
      Divider(height: 1, color: p.border),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text('Change orders', style: tt.titleSmall)),
        Text('extra work for clients', style: tt.bodySmall?.copyWith(fontSize: 11)),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        coBox('Waiting for client', co['pending'], warn: true),
        const SizedBox(width: 8),
        coBox('Approved by client', co['approved']),
      ]),
    ]);
  }
}

/// One money group in plain words: how much is settled out of the total, as a bar, and what is left.
class _MoneyGroup extends StatelessWidget {
  final String title;
  final String note;
  final double done;
  final double total;
  final String doneWord;
  final String leftWord;
  final String? alert;
  const _MoneyGroup({
    required this.title,
    required this.note,
    required this.done,
    required this.total,
    required this.doneWord,
    required this.leftWord,
    this.alert,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final pct = total > 0 ? (done / total * 100).round().clamp(0, 100) : 0;
    final left = (total - done).clamp(0, double.infinity);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, style: tt.titleSmall)),
          Text(note, style: tt.bodySmall?.copyWith(fontSize: 11)),
        ]),
        if (total > 0) ...[
          const SizedBox(height: 8),
          LevelBar(pct / 100, tone: pct == 100 ? Tone.success : null, height: 8),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text.rich(TextSpan(style: tt.bodySmall, children: [
                TextSpan(text: '$doneWord '),
                TextSpan(text: _inr(done), style: tabular(tt.bodySmall).copyWith(fontWeight: FontWeight.w700, color: p.fg)),
                TextSpan(text: ' of ${_inr(total)} · $pct%'),
              ])),
            ),
            const SizedBox(width: 6),
            left > 0
                ? StatusChip(null, label: '${_inr(left)} $leftWord', tone: Tone.accent, dense: true)
                : const StatusChip(null, label: 'Settled', tone: Tone.success, dense: true),
          ]),
        ] else
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Nothing yet.', style: tt.bodySmall)),
        if (alert != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded, size: 14, color: p.danger),
              const SizedBox(width: 4),
              Expanded(child: Text(alert!, style: tt.bodySmall?.copyWith(color: p.danger, fontWeight: FontWeight.w600))),
            ]),
          ),
      ]),
    );
  }
}

// ───────────────────────────── costs (point 12)

class _CostsPanel extends StatefulWidget {
  final Map<String, dynamic> costs;
  const _CostsPanel({required this.costs});

  @override
  State<_CostsPanel> createState() => _CostsPanelState();
}

class _CostsPanelState extends State<_CostsPanel> {
  String _labour = 'own';

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final c = widget.costs;
    final mt = _m(c['material']);
    final lab = _m(c['labour']);
    final own = _m(lab['own']), con = _m(lab['contractor']);
    final sal = _m(c['staff_salary']);

    Widget big(dynamic v, String note) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_inr(v), style: tabular(tt.headlineSmall)),
          Text(note, style: tt.bodySmall?.copyWith(fontSize: 11)),
          const SizedBox(height: 8),
        ]);
    Widget line(String label, String value) =>
        KeyValueRow(label, value, padding: const EdgeInsets.symmetric(vertical: 3));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Panel(
        title: 'Material purchased',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          big(mt['ordered'], 'ordered on issued POs'),
          line('Received on site', _inr(mt['received'])),
          line('Paid to vendors', _inr(mt['paid'])),
          line('POs still waiting for material', '${mt['open_pos'] ?? 0}'),
        ]),
      ),
      _Panel(
        title: 'Labour so far',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ChoiceRow<String>(
            value: _labour,
            options: const [('own', 'Own (NMR)'), ('contractor', 'Contractors')],
            onChanged: (v) => setState(() => _labour = v),
          ),
          const SizedBox(height: 12),
          if (_labour == 'own') ...[
            big(own['earned'], 'wages earned by your daily labour'),
            line('Present today', '${own['today'] ?? 0}'),
            line('Put on contractor work (NMR)', _inr(own['on_contracts'])),
          ] else ...[
            big(con['paid'], 'paid to contractors'),
            line('Contract value / earned', _inr(con['value'])),
            line('Contractor crew on site today', '${con['today'] ?? 0}'),
          ],
        ]),
      ),
      _Panel(
        title: 'Staff salary',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          big(sal['net_pay'], 'net pay since ${fmtDate(sal['since'])} (this financial year)'),
          line('Petty cash held by staff', _inr(_m(c['petty_cash'])['held'])),
          Align(alignment: Alignment.centerLeft, child: _Link('Payroll →', () => openWebPath(context, '/admin/finance/payroll'))),
        ]),
      ),
    ]);
  }
}

// ───────────────────────────── org tree

class _OrgTree extends StatefulWidget {
  final List<Map<String, dynamic>> org;
  const _OrgTree({required this.org});

  @override
  State<_OrgTree> createState() => _OrgTreeState();
}

class _OrgTreeState extends State<_OrgTree> {
  final _open = <dynamic>{};

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    if (widget.org.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text('No companies yet.', textAlign: TextAlign.center, style: tt.bodySmall),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final c in widget.org)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: p.muted,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(children: [
                Icon(Icons.domain_outlined, size: 16, color: p.accentText),
                const SizedBox(width: 8),
                Flexible(child: Text(dash(c['name']), style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                if ((c['code'] ?? '').toString().isNotEmpty) ...[const SizedBox(width: 6), CodeTag(c['code'].toString())],
                const Spacer(),
                Text('${c['projects'] ?? 0} project${toInt(c['projects']) == 1 ? '' : 's'} · ${_inr(c['budget'])}',
                    style: tabular(tt.bodySmall)),
              ]),
            ),
            for (final b in asMapList(c['branches'] ?? const [])) ..._branch(context, b),
          ]),
        ),
    ]);
  }

  List<Widget> _branch(BuildContext context, Map<String, dynamic> b) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final has = toInt(b['projects']) > 0;
    final open = _open.contains(b['id']);
    return [
      Divider(height: 1, color: p.border),
      InkWell(
        onTap: has ? () => setState(() => open ? _open.remove(b['id']) : _open.add(b['id'])) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: Row(children: [
              SizedBox(
                width: 20,
                child: has ? Icon(open ? Icons.expand_more : Icons.chevron_right, size: 18, color: p.fgMuted) : null,
              ),
              Icon(Icons.account_tree_outlined, size: 14, color: p.fgSubtle),
              const SizedBox(width: 6),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(dash(b['name']), style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  if (b['city'] != null) Text(b['city'].toString(), style: tt.bodySmall?.copyWith(fontSize: 11)),
                ]),
              ),
              Text('${b['projects'] ?? 0} · ${b['ongoing'] ?? 0} ongoing · ${_inr(b['budget'])}',
                  style: tabular(tt.bodySmall).copyWith(fontSize: 11.5)),
            ]),
          ),
        ),
      ),
      if (open)
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 0, 12, 10),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final pr in asMapList(b['project_list'] ?? const []))
              TagChip('${pr['name']} · ${pr['status']}',
                  onTap: () => push(context, ProjectDetailScreen(projectId: toInt(pr['id'])))),
          ]),
        ),
    ];
  }
}

// ───────────────────────────── mini tables as lists

class _ContractorRows extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _ContractorRows({required this.rows});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text('No contracts yet.', textAlign: TextAlign.center, style: tt.bodySmall),
      );
    }
    return Column(children: [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) Divider(height: 1, color: p.border),
        Builder(builder: (context) {
          final x = rows[i];
          final contracts = toInt(x['contracts']);
          final basis = x['basis'] != null ? '${x['basis']} basis' : '$contracts contract${contracts == 1 ? '' : 's'}';
          final nmr = toNum(x['nmr']);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(dash(x['name']), style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${x['trade'] ?? '—'} · $basis', style: tt.bodySmall?.copyWith(fontSize: 11)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Eyebrow('Due'),
                  Text(_inr(x['due']),
                      style: tabular(tt.titleSmall).copyWith(color: toNum(x['due']) > 0 ? p.accentText : null)),
                ]),
              ]),
              const SizedBox(height: 4),
              Text(
                'Value ${_inr(x['contract_value'])} · NMR ${nmr > 0 ? _inr(nmr) : '—'}'
                '${nmr > 0 ? (x['basis'] == 'rate' ? ' (deducted)' : ' (shown only)') : ''} · Paid ${_inr(x['paid'])}',
                style: tabular(tt.bodySmall),
              ),
            ]),
          );
        }),
      ],
    ]);
  }
}

class _RecentRows extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final String empty;
  final String number;
  final String Function(Map<String, dynamic>) title;
  final String amount;
  const _RecentRows({required this.rows, required this.empty, required this.number, required this.title, required this.amount});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(empty, textAlign: TextAlign.center, style: tt.bodySmall),
      );
    }
    return Column(children: [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) Divider(height: 1, color: p.border),
        RowTile(
          padding: const EdgeInsets.symmetric(vertical: 10),
          title: '${rows[i][number] ?? '—'} · ${title(rows[i])}',
          subtitle: dash(rows[i]['project']),
          onTap: rows[i]['link'] == null ? null : () => openWebPath(context, rows[i]['link'].toString()),
          trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_inr(rows[i][amount]), style: tabular(tt.titleSmall)),
            const SizedBox(height: 4),
            StatusChip(null, label: dash(rows[i]['status']), tone: Tone.neutral, dense: true),
          ]),
        ),
      ],
    ]);
  }
}
