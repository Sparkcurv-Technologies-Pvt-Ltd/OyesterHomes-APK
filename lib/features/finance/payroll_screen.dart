import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../shell/routes.dart';
import 'finance_shared.dart';

/// Monthly payroll (web PayrollPage.jsx): create a run for a month, preview the attendance-based pay,
/// process it at month end, and mark each salary paid. Top-level page (Admin, Accountant): no AppBar.
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _Run {
  final Map<String, dynamic> run;
  final List<Map<String, dynamic>>? entries;
  const _Run(this.run, this.entries);
}

String _thisMonth() => todayIso().substring(0, 7);

class _PayrollScreenState extends State<PayrollScreen> {
  final _key = GlobalKey<AsyncViewState<List<_Run>>>();
  String _month = _thisMonth();
  bool _creating = false;

  Future<List<_Run>> _load() async {
    final api = apiOf(context);
    final runs = jList(await api.get('/payroll-runs'));
    final entries = await Future.wait(runs.map((r) async =>
        r['status'] == 'Draft' ? null : jList(await api.get('/payroll-runs/${r['id']}/entries'))));
    return [for (var i = 0; i < runs.length; i++) _Run(runs[i], entries[i])];
  }

  Future<void> _reload() async => _key.currentState?.reload();

  Future<void> _create() async {
    setState(() => _creating = true);
    final ok = await runAction(context, () => apiOf(context).post('/payroll-runs', data: {'month': _month}),
        success: 'Payroll run created');
    if (!mounted) return;
    setState(() => _creating = false);
    if (ok) await _reload();
  }

  Future<void> _markPaid(Map<String, dynamic> e) async {
    final ok = await confirmDialog(context,
        title: 'Mark paid?', message: '${e['staff_name'] ?? 'Staff'} · ${inr(e['net_pay'])}', confirmLabel: 'Mark Paid');
    if (!ok || !mounted) return;
    final done = await runAction(context, () => apiOf(context).post('/payroll-entries/${e['id']}/mark-paid'), success: 'Marked paid');
    if (done) await _reload();
  }

  Future<void> _preview(Map<String, dynamic> run) async {
    final processed = await showAppSheet<bool>(context,
        title: 'Payroll · ${run['month_label'] ?? fmtDateRange(run['period_start'], run['period_end'])}',
        subtitle: 'Pay is based on attendance. Paid: present, paid leave, Sundays. Deducted: absent, unpaid leave, '
            'unmarked working days, ½ per half day.',
        builder: (ctx) => _PreviewBody(run: run));
    if (processed == true) await _reload();
  }

  Future<void> _pickMonth() async {
    final picked = await showAppSheet<String>(context, title: 'Month', builder: (ctx) => _MonthPicker(value: _month));
    if (picked != null) setState(() => _month = picked);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: AsyncView<List<_Run>>(
        key: _key,
        load: _load,
        builder: (context, runs, reload) => RefreshList(onRefresh: reload, children: [
          Surface(
            margin: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.control),
                    onTap: _pickMonth,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Month', suffixIcon: Icon(Icons.calendar_month_outlined, size: 18)),
                      child: Text(DateTime.tryParse('$_month-01') == null ? '' : fmtMonth(_month),
                          style: tabular(tt.bodyLarge)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _creating || _month.isEmpty ? null : _create,
                    icon: _creating
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2))
                        : const Icon(Icons.add, size: 18),
                    label: const Text('New Run'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Text('One run per month · process on the last day of the month or later · pay is based on attendance',
                  style: tt.bodySmall),
            ]),
          ),
          if (runs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: EmptyState(icon: Icons.payments_outlined, title: 'No payroll runs yet.'),
            ),
          for (final r in runs)
            _RunCard(
              run: r.run,
              entries: r.entries,
              onProcess: () => _preview(r.run),
              onMarkPaid: _markPaid,
            ),
        ]),
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  final Map<String, dynamic> run;
  final List<Map<String, dynamic>>? entries;
  final VoidCallback onProcess;
  final void Function(Map<String, dynamic>) onMarkPaid;
  const _RunCard({required this.run, required this.entries, required this.onProcess, required this.onMarkPaid});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final draft = run['status'] == 'Draft';
    final processFrom = run['process_from'] as String?;
    final waiting = draft && processFrom != null && todayIso().compareTo(processFrom) < 0;
    final list = entries ?? const <Map<String, dynamic>>[];
    return Surface(
      margin: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 0),
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text('Run #${run['id']}', style: tt.titleMedium?.copyWith(color: p.accentText, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              StatusChip('${run['status']}', dense: true),
              const Spacer(),
              if (!draft) figure(context, inr(run['total_net_pay']), strong: true),
            ]),
            const SizedBox(height: 4),
            Text(
              [if ((run['month_label'] ?? '').toString().isNotEmpty) run['month_label'], fmtDateRange(run['period_start'], run['period_end'])]
                  .join(' · '),
              style: tt.bodySmall,
            ),
            if (draft) ...[
              const SizedBox(height: 10),
              if (waiting)
                Row(children: [
                  Icon(Icons.event_outlined, size: 15, color: p.fgMuted),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Process from ${fmtDate(processFrom)}', style: tt.bodySmall)),
                  TextButton(onPressed: onProcess, child: const Text('Preview')),
                ])
              else
                SizedBox(
                  height: 44,
                  child: FilledButton(onPressed: onProcess, child: const Text('Review & Process')),
                ),
            ],
          ]),
        ),
        for (final e in list) ...[
          Divider(height: 1, color: p.border),
          _EntryTile(entry: e, onMarkPaid: () => onMarkPaid(e)),
        ],
      ]),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  final VoidCallback onMarkPaid;
  const _EntryTile({required this.entry, required this.onMarkPaid});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final e = entry;
    final ded = toNum(e['deductions']);
    final viaAdvance = e['settled_via_advance'] == true;
    Widget status;
    if (e['payment_status'] == 'Paid') {
      status = Row(mainAxisSize: MainAxisSize.min, children: [
        if (viaAdvance) ...[Text('FROM ADVANCE', style: tt.labelSmall), const SizedBox(width: 6)],
        const StatusChip('Paid', dense: true),
      ]);
    } else if (viaAdvance) {
      status = Text('AWAITING TOP-UP', style: tt.labelSmall?.copyWith(color: p.danger, fontWeight: FontWeight.w700));
    } else {
      status = TextButton(
        onPressed: onMarkPaid,
        style: TextButton.styleFrom(foregroundColor: p.success),
        child: const Text('Mark Paid'),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['staff_name'] ?? '—'}', style: tt.titleSmall),
              Text(humanize(e['role_at_time'] as String?), style: tt.bodySmall),
            ]),
          ),
          Padding(padding: const EdgeInsets.only(right: 6), child: figure(context, inr(e['net_pay']), strong: true)),
        ]),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Column(children: [
            KeyValueRow('Base', inr(e['base_salary']), padding: const EdgeInsets.symmetric(vertical: 2)),
            KeyValueRow(
              ded > 0 ? 'Deductions · ${e['deduction_note'] ?? '${qty(e['deduction_days'])} day(s)'}' : 'Deductions',
              ded > 0 ? '−${inr(ded)}' : '—',
              valueColor: ded > 0 ? p.danger : null,
              padding: const EdgeInsets.symmetric(vertical: 2),
            ),
          ]),
        ),
        Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(top: 2), child: status)),
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────── preview (PreviewDialog)

class _PreviewBody extends StatefulWidget {
  final Map<String, dynamic> run;
  const _PreviewBody({required this.run});

  @override
  State<_PreviewBody> createState() => _PreviewBodyState();
}

class _PreviewBodyState extends State<_PreviewBody> {
  Map<String, dynamic>? _data;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = jMap(await apiOf(context).get('/payroll-runs/${widget.run['id']}/preview'));
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _process() async {
    setState(() => _busy = true);
    final label = (widget.run['month_label'] ?? '').toString().isNotEmpty ? widget.run['month_label'] : 'the month';
    final ok = await runAction(context, () => apiOf(context).post('/payroll-runs/${widget.run['id']}/process'),
        success: 'Payroll for $label processed');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  Widget _banner(IconData icon, Tone tone, Widget child) {
    final p = context.pal;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.toneFill(tone),
        border: Border.all(color: p.toneBorder(tone)),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: p.tone(tone)),
        const SizedBox(width: 8),
        Expanded(child: child),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(message: errorText(_error), onRetry: _load);
    final d = _data;
    if (d == null) return const LoadingView();
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final lines = jList(d['lines']);
    final run = jMap(d['run']);
    final canProcess = d['can_process'] == true;
    final unmarked = toInt(d['unmarked_total']);
    final lastDay = canProcess &&
        lines.any((x) => jMap(x['breakdown'])['counted_until'] == run['period_end']) &&
        todayIso() == run['period_end'];
    final hasAdvance = lines.any((x) => x.containsKey('advance_after'));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (lastDay)
        _banner(Icons.event_outlined, Tone.info,
            Text("Today is the last day of the month and counts too — mark today's attendance before processing.", style: tt.bodySmall)),
      if (unmarked > 0)
        _banner(
          Icons.warning_amber_rounded,
          Tone.warning,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(style: tt.bodySmall, children: [
              TextSpan(text: '$unmarked unmarked working day(s)', style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: ' will be deducted as absent. Fix them first in Users → Attendance if staff were actually working.'),
            ])),
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => openWebPath(context, '/admin/users?tab=attendance'),
              child: const Text('Open Users → Attendance'),
            ),
          ]),
        ),
      RowGroup(
        margin: EdgeInsets.zero,
        footer: TotalBand('Total', inr(d['total_net_pay'])),
        children: [
          if (lines.isEmpty)
            Padding(padding: const EdgeInsets.all(18), child: Text('No staff on payroll.', style: tt.bodySmall, textAlign: TextAlign.center)),
          for (final x in lines) _PreviewLine(line: x, showAdvance: hasAdvance),
        ],
      ),
      const SizedBox(height: 12),
      Text(canProcess ? 'Day rate = base ÷ days in the month.' : 'Can be processed from ${fmtDate(d['process_from'])} (month end).',
          style: tt.bodySmall),
      const SizedBox(height: 16),
      if (canProcess)
        SubmitButton(label: 'Process payroll', busy: _busy, onPressed: _process)
      else
        OutlinedButton(onPressed: () => Navigator.pop(context), child: Text('Close', style: TextStyle(color: p.fg))),
    ]);
  }
}

class _PreviewLine extends StatelessWidget {
  final Map<String, dynamic> line;
  final bool showAdvance;
  const _PreviewLine({required this.line, required this.showAdvance});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final x = line;
    final b = jMap(x['breakdown']);
    final att = b['attendance_based'] == true;
    String n(dynamic v) => toNum(v) == 0 ? '–' : qty(v);
    final half = toNum(b['half_day']);
    final ded = toNum(x['deductions']);
    final unmarked = toNum(b['unmarked']);
    final adv = x.containsKey('advance_after') ? toNumOrNull(x['advance_after']) : null;
    const kv = EdgeInsets.symmetric(vertical: 2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${x['name']}', style: tt.titleSmall),
              Text('${humanize(x['role'] as String?)}${att ? '' : ' · full salary'}', style: tt.bodySmall),
            ]),
          ),
          figure(context, inr(x['net_pay']), strong: true),
        ]),
        const SizedBox(height: 6),
        KeyValueRow('Base', inr(x['base_salary']), padding: kv),
        if (att) ...[
          KeyValueRow('Present', '${qty(b['present'])}${half > 0 ? ' +${qty(half)}½' : ''}', padding: kv),
          KeyValueRow('Paid leave', n(b['paid_leave']), padding: kv),
          KeyValueRow('Absent', n(toNum(b['absent']) + toNum(b['unpaid_leave'])), padding: kv),
          KeyValueRow('Unmarked', n(unmarked), valueColor: unmarked > 0 ? p.warning : null, padding: kv),
        ],
        KeyValueRow(
          toNum(x['deduction_days']) > 0 ? 'Deduction · ${qty(x['deduction_days'])} day(s)' : 'Deduction',
          ded > 0 ? '−${inr(ded)}' : '—',
          valueColor: ded > 0 ? p.danger : null,
          padding: kv,
        ),
        if (showAdvance)
          KeyValueRow(
            'Advance after',
            adv == null ? '—' : adv < 0 ? '${inr(-adv)} owed' : '${inr(adv)} carried',
            valueColor: adv == null ? null : adv < 0 ? p.danger : p.success,
            padding: kv,
          ),
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────── month picker (web <input type="month">)

class _MonthPicker extends StatefulWidget {
  final String value;
  const _MonthPicker({required this.value});

  @override
  State<_MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  late int _year;
  int? _month;
  static const _names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  void initState() {
    super.initState();
    final d = DateTime.tryParse('${widget.value}-01') ?? DateTime.now();
    _year = d.year;
    _month = d.month;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final current = DateTime.tryParse('${widget.value}-01');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton(tooltip: 'Previous year', onPressed: () => setState(() => _year--), icon: const Icon(Icons.chevron_left)),
        Expanded(child: Text('$_year', textAlign: TextAlign.center, style: tabular(tt.titleLarge))),
        IconButton(tooltip: 'Next year', onPressed: () => setState(() => _year++), icon: const Icon(Icons.chevron_right)),
      ]),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.9,
        children: [
          for (var m = 1; m <= 12; m++)
            Builder(builder: (_) {
              final selected = current != null && current.year == _year && current.month == m && _month == m;
              return Material(
                color: selected ? p.primaryBtn : p.card,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.control), side: BorderSide(color: selected ? p.primaryBtn : p.border)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.control),
                  onTap: () => Navigator.pop(context, '$_year-${m.toString().padLeft(2, '0')}'),
                  child: Center(
                    child: Text(_names[m - 1],
                        style: tt.titleSmall?.copyWith(color: selected ? p.onPrimaryBtn : p.fg, fontWeight: FontWeight.w600)),
                  ),
                ),
              );
            }),
        ],
      ),
    ]);
  }
}
