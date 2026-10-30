import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import 'daily_attendance_card.dart';
import 'employee_forms.dart';
import 'labour_shared.dart';

/// Project → Employees tab (web EmployeesTab.jsx with AttendanceMarkGrid, DailyAttendanceCard,
/// LabourPaymentModal and EmployeeFormModal): today's marking, the last 7 days grid, the employee register
/// (add / edit / deactivate) and the labour cost report with wage payments.
/// Embedded in the project's TabBarView: no Scaffold, scrolls itself, pull-to-refresh.
class EmployeesTab extends StatefulWidget {
  final int projectId;
  const EmployeesTab({super.key, required this.projectId});

  @override
  State<EmployeesTab> createState() => _EmployeesTabState();
}

List<String> _lastNDays(int n) => [for (var i = n - 1; i >= 0; i--) daysAgoIso(i)];

class _EmployeesTabState extends State<EmployeesTab> {
  List<Map<String, dynamic>>? _employees;
  final Map<String, String> _att = {}; // "employeeId|date" → status
  final Set<String> _saving = {};
  Object? _error;
  late List<String> _dates;
  String _from = monthStartIso();
  String _to = todayIso();
  int _labourTick = 0;

  int get _pid => widget.projectId;

  @override
  void initState() {
    super.initState();
    _dates = _lastNDays(7);
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final dates = _lastNDays(7);
    try {
      final res = await Future.wait([
        api.get('/projects/$_pid/employees'),
        api.get('/projects/$_pid/attendance', params: {'date_from': dates.first, 'date_to': dates.last}),
      ]);
      if (!mounted) return;
      setState(() {
        _dates = dates;
        _employees = asMaps(res[0]);
        _att
          ..clear()
          ..addAll({for (final a in asMaps(res[1])) '${a['employee_id']}|${a['attendance_date']}': a['status'].toString()});
        _error = null;
        _labourTick++;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _mark(Map<String, dynamic> e, String status, String date) async {
    final key = '${e['id']}|$date';
    final prev = _att[key];
    setState(() {
      _att[key] = status; // show it straight away; put it back if the server refuses
      _saving.add(key);
    });
    try {
      await context.read<ApiClient>().post('/projects/$_pid/attendance',
          data: {'employee_id': e['id'], 'attendance_date': date, 'status': status});
      if (mounted) showToast(context, '${e['name']}: ${status.replaceFirst('_', ' ')} on ${fmtDate(date)}');
      _load();
    } catch (err) {
      if (!mounted) return;
      setState(() {
        if (prev == null) {
          _att.remove(key);
        } else {
          _att[key] = prev;
        }
      });
      showToast(context, errorText(err), error: true);
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  Future<void> _deactivate(Map<String, dynamic> e) async {
    final ok = await confirmDialog(context,
        title: 'Deactivate ${e['name']}?', message: 'Attendance history is preserved.', confirmLabel: 'Deactivate', destructive: true);
    if (!ok || !mounted) return;
    if (await runAction(context, () => context.read<ApiClient>().post('/employees/${e['id']}/deactivate'),
        success: 'Employee deactivated')) {
      _load();
    }
  }

  Future<void> _editEmployee([Map<String, dynamic>? e]) async {
    if (await showEmployeeForm(context, projectId: _pid, employee: e)) _load();
  }

  Future<void> _pay(Map<String, dynamic> row) async {
    if (await _showLabourPayment(context, _pid, row)) setState(() => _labourTick++);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final canManageWage = user?.roleIn(['Admin', 'Accountant']) ?? false;
    if (_employees == null) {
      if (_error != null) {
        return RefreshList(onRefresh: _load, children: [ErrorRetry(message: errorText(_error), onRetry: _load)]);
      }
      return const LoadingView();
    }
    final employees = _employees!;
    final active = employees.where((e) => e['status'] == 'active').toList();
    final today = _dates.last;
    final p = context.pal;

    return RefreshList(onRefresh: _load, children: [
      // ── today's attendance
      SectionHeader(
        "Today's Attendance · ${fmtDate(today)}",
        padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 8),
        trailing: FilledButton.icon(
          onPressed: () => _editEmployee(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Employee'),
        ),
      ),
      if (active.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: kGutter),
          child: Surface(
            child: EmptyState(icon: Icons.engineering_outlined, title: 'No employees on this project yet. Add your first field worker.'),
          ),
        ),
      for (final e in active)
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
          child: DailyAttendanceCard(
            key: ValueKey('today-${e['id']}'),
            employee: e,
            status: _att['${e['id']}|$today'],
            onMark: (emp, s) => _mark(emp, s, today),
          ),
        ),

      // ── last 7 days
      if (active.isNotEmpty) ...[
        const SectionHeader('Attendance — Last 7 Days (tap a cell to mark/cycle)'),
        _AttendanceGrid(employees: active, dates: _dates, att: _att, saving: _saving, onMark: _mark),
      ],

      // ── register
      SectionHeader('Employee Register · ${employees.length}'),
      RowGroup(children: [
        if (employees.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No employees yet.'))),
        for (final e in employees)
          RowTile(
            onTap: () => _editEmployee(e),
            title: (e['name'] ?? '').toString(),
            subtitle: [
              dash(e['role_title']),
              if ((e['phone'] ?? '').toString().isNotEmpty) e['phone'],
              if (e['joining_date'] != null) 'Joined ${fmtDate(e['joining_date'])}',
            ].join(' · '),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                Text(wageText(e), style: tabular(Theme.of(context).textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                StatusChip(e['status'], dense: true, tone: e['status'] == 'active' ? Tone.success : Tone.neutral),
              ]),
              if (e['status'] == 'active' && canManageWage)
                IconButton(
                  tooltip: 'Deactivate',
                  onPressed: () => _deactivate(e),
                  icon: Icon(Icons.person_off_outlined, color: p.danger),
                ),
            ]),
          ),
      ]),

      // ── labour cost
      const SectionHeader('Labour Cost Report'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGutter),
        child: Row(children: [
          Expanded(
              child: DateField(
                  label: 'From', value: _from, clearable: false, onChanged: (v) => setState(() => _from = v ?? _from))),
          const SizedBox(width: 10),
          Expanded(
              child: DateField(label: 'To', value: _to, clearable: false, onChanged: (v) => setState(() => _to = v ?? _to))),
        ]),
      ),
      const SizedBox(height: 10),
      InlineAsync<Map<String, dynamic>>(
        depKey: '$_from|$_to|$_labourTick',
        load: () async => Map<String, dynamic>.from(await context
            .read<ApiClient>()
            .get('/projects/$_pid/labour-cost', params: {'date_from': _from, 'date_to': _to}) as Map),
        builder: (ctx, labour, _) => _LabourReport(labour: labour, canPay: canManageWage, onPay: _pay),
      ),
    ]);
  }
}

// ───────────────────────────────────────────────────────── 7-day grid (AttendanceMarkGrid.jsx)

const _cycle = ['present', 'half_day', 'absent', 'leave'];
const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _letter = {'present': 'P', 'half_day': '½', 'absent': 'A', 'leave': 'L'};

class _AttendanceGrid extends StatelessWidget {
  final List<Map<String, dynamic>> employees;
  final List<String> dates;
  final Map<String, String> att;
  final Set<String> saving;
  final Future<void> Function(Map<String, dynamic> e, String status, String date) onMark;
  const _AttendanceGrid({required this.employees, required this.dates, required this.att, required this.saving, required this.onMark});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;

    return RowGroup(
      header: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Row(children: [
          for (final d in dates)
            Expanded(
              child: Column(children: [
                Text(_weekdays[toDate(d)!.weekday - 1], style: tt.labelSmall),
                Text('${d.substring(8)}/${d.substring(5, 7)}', style: tabular(tt.bodySmall)),
              ]),
            ),
        ]),
      ),
      children: [
        for (final e in employees)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: (e['name'] ?? '').toString(), style: tt.titleSmall),
                    TextSpan(text: '  ${dash(e['role_title'])}', style: tt.bodySmall),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(children: [
                for (final d in dates)
                  Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: _cell(context, p, e, d))),
              ]),
            ]),
          ),
      ],
    );
  }

  Widget _cell(BuildContext context, AppPalette p, Map<String, dynamic> e, String d) {
    final key = '${e['id']}|$d';
    final status = att[key];
    final next = _cycle[(_cycle.indexOf(status ?? '') + 1) % _cycle.length];
    final busy = saving.contains(key);
    final t = dayTone(status);
    return Tooltip(
      message: status != null ? '${humanize(status)} — tap to change' : 'Tap to mark present',
      child: Material(
        color: status == null ? p.card : p.toneFill(t),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          side: BorderSide(color: status == null ? p.border : p.toneBorder(t)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : () => onMark(e, status != null ? next : 'present', d),
          child: SizedBox(
            height: 48,
            child: Center(
              child: busy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(status != null ? (_letter[status] ?? '·') : '·',
                      style: TextStyle(
                          fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: status == null ? p.fgSubtle : p.tone(t))),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────── labour cost report

class _LabourReport extends StatelessWidget {
  final Map<String, dynamic> labour;
  final bool canPay;
  final void Function(Map<String, dynamic> row) onPay;
  const _LabourReport({required this.labour, required this.canPay, required this.onPay});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final rows = asMaps(labour['rows']);
    return RowGroup(
      footer: Container(
        color: p.muted,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Eyebrow('Total · ${fmtDateRange(labour['date_from'], labour['date_to'])}'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Fig('Earned', inr(labour['total_amount']), color: p.accentText, large: true)),
            Expanded(child: Fig('Paid', inr(labour['total_paid']), color: p.success, large: true)),
            Expanded(child: Fig('Due', inr(labour['total_due']), color: p.danger, large: true)),
          ]),
        ]),
      ),
      children: [
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No employees yet.'))),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((r['name'] ?? '').toString(), style: tt.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if ((r['role_title'] ?? '').toString().isNotEmpty) r['role_title'],
                        'Daily wage ${r['daily_wage'] != null ? inr(r['daily_wage']) : '—'}',
                      ].join(' · '),
                      style: tt.bodySmall,
                    ),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(qty(r['days_present']), style: tabular(tt.titleLarge).copyWith(fontWeight: FontWeight.w800)),
                  const Eyebrow('Days present'),
                ]),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Fig('Earned', r['amount'] != null ? inr(r['amount']) : 'manual (${r['wage_type']})',
                      color: r['amount'] != null ? p.fg : p.fgSubtle),
                ),
                Expanded(child: Fig('Paid', inr(r['paid']), color: p.success)),
                Expanded(child: _due(p, r['due'])),
              ]),
              if (canPay) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => onPay(r),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('Make Payment'),
                  ),
                ),
              ],
            ]),
          ),
      ],
    );
  }

  Widget _due(AppPalette p, dynamic due) {
    if (due == null) return Fig('Due', '—', color: p.fgSubtle);
    final d = toNum(due);
    if (d > 0) return Fig('Due', inr(d), color: p.danger);
    if (d < 0) return Fig('Due', 'Adv ${inr(-d)}', color: p.info);
    return Fig('Due', 'Settled', color: p.success);
  }
}

// ───────────────────────────────────────────────────────── wage payment (LabourPaymentModal.jsx)

const _paymentTypes = ['Advance Payment', 'Partial Payment', 'Full Payment'];

Future<bool> _showLabourPayment(BuildContext context, int projectId, Map<String, dynamic> row) async {
  final r = await showAppSheet<bool>(
    context,
    title: 'Pay ${row['name']}',
    subtitle: "Posts as a DEBIT (Employee Payment) in this project's balance sheet and the employee's payment history.",
    builder: (ctx) => _LabourPaymentForm(projectId: projectId, row: row),
  );
  return r == true;
}

class _LabourPaymentForm extends StatefulWidget {
  final int projectId;
  final Map<String, dynamic> row;
  const _LabourPaymentForm({required this.projectId, required this.row});

  @override
  State<_LabourPaymentForm> createState() => _LabourPaymentFormState();
}

class _LabourPaymentFormState extends State<_LabourPaymentForm> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late String _ptype;
  bool _saving = false;
  String? _error;

  Map<String, dynamic> get _row => widget.row;

  @override
  void initState() {
    super.initState();
    final due = toNum(_row['due']);
    _amount.text = due > 0 ? inputNum(due) : '';
    _ptype = due > 0 ? 'Full Payment' : 'Advance Payment';
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _amt => toNum(_amount.text);

  Future<void> _submit() async {
    if (!(_amt > 0)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = await context.read<ApiClient>().post('/projects/${widget.projectId}/labour-payments', data: {
        'employee_id': _row['employee_id'],
        'amount': _amt,
        'payment_type': _ptype,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      if (!mounted) return;
      showToast(context, 'Paid ${inr(_amt)} to ${_row['name']} · budget remaining ${inr((data as Map)['project_budget_remaining'])}');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorText(e);
      });
      showToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final due = _row['due'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FigBand(children: [
        Fig('Earned (total)', _row['earned_total'] != null ? inr(_row['earned_total']) : '—', align: CrossAxisAlignment.center, large: true),
        Fig('Paid', _row['paid'] != null ? inr(_row['paid']) : '—', align: CrossAxisAlignment.center, large: true),
        Fig('Due', due != null ? inr(due) : '—',
            align: CrossAxisAlignment.center, large: true, color: toNum(due) > 0 ? p.danger : p.success),
      ]),
      const SizedBox(height: 16),
      AppTextField(
        controller: _amount,
        label: 'Amount (₹)',
        requiredField: true,
        money: true,
        hint: 'e.g. 2400 (3 days at ₹800)',
        onChanged: (_) => setState(() {}),
      ),
      kFieldGap,
      ChoiceRow<String>(
        label: 'Payment Type *',
        value: _ptype,
        options: [for (final t in _paymentTypes) (t, t)],
        onChanged: (v) => setState(() => _ptype = v),
      ),
      kFieldGap,
      AppTextField(controller: _note, label: 'Note (optional)', hint: 'e.g. Week 32 wages'),
      const SizedBox(height: 20),
      SheetError(_error),
      SubmitButton(label: 'Make Payment', busy: _saving, onPressed: _amt > 0 ? _submit : null),
    ]);
  }
}
