import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../shell/routes.dart';
import 'finance_shared.dart';
import 'project_finance_screen.dart';

/// Organisation finance (web FinancePage.jsx): Overview (KPI cards, overdue invoices, payroll runs)
/// and Balance Sheet (OrgBalanceSheetTab.jsx), plus Add Income / Add Expense.
/// Top-level page (Admin, Accountant; module `finance`): no AppBar, the shell draws it.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  final _overviewKey = GlobalKey<AsyncViewState<_Overview>>();
  final _sheetKey = GlobalKey<_OrgBalanceSheetTabState>();

  /// The web's `invalidateFinance`: refresh both tabs after a transaction.
  void _changed() {
    _overviewKey.currentState?.reload();
    _sheetKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      body: DefaultTabController(
        length: 2,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 4),
            child: Row(children: [
              Expanded(
                child: ToneButton(
                  label: 'Add Income',
                  icon: Icons.add,
                  color: p.success,
                  height: 46,
                  onPressed: () => showIncomeSheet(context, onSaved: _changed),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ToneButton(
                  label: 'Add Expense',
                  icon: Icons.remove,
                  color: p.danger,
                  height: 46,
                  onPressed: () => showExpenseSheet(context, onSaved: _changed),
                ),
              ),
            ]),
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Balance Sheet'),
            ]),
          ),
          Expanded(
            child: TabBarView(children: [
              _KeepAlive(
                child: AsyncView<_Overview>(
                  key: _overviewKey,
                  load: () async {
                    final api = apiOf(context);
                    final r = await Future.wait([api.get('/finance/dashboard-summary'), api.get('/payroll-runs')]);
                    return _Overview(jMap(r[0]), jList(r[1]));
                  },
                  builder: (context, d, reload) => _OverviewTab(data: d, onRefresh: reload),
                ),
              ),
              _OrgBalanceSheetTab(key: _sheetKey),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Overview {
  final Map<String, dynamic> s;
  final List<Map<String, dynamic>> runs;
  const _Overview(this.s, this.runs);
}

class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _OverviewTab extends StatelessWidget {
  final _Overview data;
  final Future<void> Function() onRefresh;
  const _OverviewTab({required this.data, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = data.s;
    final overdue = jList(s['overdue_invoices']);
    final profit = toNum(s['profit']);
    return RefreshList(onRefresh: onRefresh, children: [
      const SizedBox(height: 4),
      KpiGrid(children: [
        KpiTile(label: 'Income To Date', value: compactCr(s['income_to_date']), icon: Icons.trending_up),
        KpiTile(label: 'Cost To Date', value: compactCr(s['cost_to_date']), icon: Icons.trending_down),
        KpiTile(
            label: 'Profit',
            value: compactCr(profit),
            icon: Icons.currency_rupee,
            tone: profit < 0 ? Tone.danger : null),
        KpiTile(label: 'Outstanding Invoices', value: compactCr(s['outstanding_invoices']), icon: Icons.receipt_long_outlined),
      ]),
      const SectionHeader('Overdue Invoices'),
      if (overdue.isEmpty) const EmptyLine('No overdue invoices.'),
      for (final inv in overdue)
        Surface(
          margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
          padding: EdgeInsets.zero,
          color: p.toneFill(Tone.danger),
          borderColor: p.toneBorder(Tone.danger),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            RowTile(
              title: '${inv['invoice_number']}',
              subtitle: 'Due ${fmtDate(inv['due_date'])}',
              trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                figure(context, fmtCr(inv['balance_due']), strong: true),
                const SizedBox(height: 4),
                const StatusChip('Overdue', dense: true),
              ]),
              chevron: true,
              onTap: () => push(context, ProjectFinanceScreen(projectId: inv['project_id'] as int)),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 2),
              child: Align(alignment: Alignment.centerRight, child: InvoiceShareButtons(inv: inv)),
            ),
          ]),
        ),
      SectionHeader(
        'Payroll Runs · allocated ${fmtCr(s['payroll_total_all'])}',
        trailing: TextButton.icon(
          onPressed: () => openWebPath(context, '/admin/finance/payroll'),
          icon: const Icon(Icons.payments_outlined, size: 16),
          label: const Text('Payroll'),
        ),
      ),
      if (data.runs.isEmpty)
        const EmptyLine('No payroll runs yet.')
      else
        RowGroup(children: [
          for (final r in data.runs)
            RowTile(
              title: fmtDateRange(r['period_start'], r['period_end']),
              subtitle: '${toInt(r['entry_count'])} staff',
              trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                figure(context, fmtCr(r['total_net_pay']), strong: true),
                const SizedBox(height: 4),
                StatusChip('${r['status']}', dense: true),
              ]),
              chevron: true,
              onTap: () => openWebPath(context, '/admin/finance/payroll'),
            ),
        ]),
    ]);
  }
}

// ───────────────────────────────────────────────────────── OrgBalanceSheetTab

class _OrgBalanceSheetTab extends StatefulWidget {
  const _OrgBalanceSheetTab({super.key});

  @override
  State<_OrgBalanceSheetTab> createState() => _OrgBalanceSheetTabState();
}

class _OrgBalanceSheetTabState extends State<_OrgBalanceSheetTab> with AutomaticKeepAliveClientMixin {
  Period _period = const Period();
  Map<String, dynamic>? _bs;
  Object? _error;
  int _gen = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Keeps the last sheet on screen while a new period loads (web `placeholderData`).
  Future<void> reload() async {
    if (!_period.valid) return;
    final gen = ++_gen;
    setState(() => _error = null);
    try {
      final d = jMap(await apiOf(context).get('/finance/balance-sheet', params: _period.params));
      if (!mounted || gen != _gen) return;
      setState(() => _bs = d);
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() => _error = e);
    }
  }

  void _setPeriod(Period v) {
    setState(() => _period = v);
    reload();
  }

  Future<void> _export(String fmt) => downloadAndOpen(context, apiOf(context), '/finance/balance-sheet/export',
      params: {'fmt': fmt, ..._period.params}, fallbackName: 'sitera-balance-sheet-${_period.fileTag}.$fmt');

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.pal;
    final bs = _bs;
    final children = <Widget>[PeriodPicker(value: _period, onChanged: _setPeriod)];
    if (bs == null) {
      children.add(_error != null
          ? ErrorRetry(message: errorText(_error), onRetry: reload)
          : const LoadingView(label: 'Loading balance sheet…'));
      return RefreshList(onRefresh: reload, children: children);
    }
    final ranged = bs['period'] != null;
    final dues = jMap(bs['employee_dues']);
    final cats = jList(dues['labour_by_category']);
    final lossProjects = jList(bs['loss_projects']);
    final rows = jList(bs['projects']);
    final overheadsPaid = toNum(jMap(bs['overheads'])['staff_payroll_paid']);
    final net = toNum(bs['net']);

    children.addAll([
      if (_error != null)
        NoteText(errorText(_error), padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8)),
      if (ranged)
        NoteText('Showing money that moved ${_period.text}: credit, debit and profit / loss count only receipts and payments '
            'dated in this period. Budgets and required employee payments are as of today.'),
      ExportButtons(enabled: _period.valid, onExport: _export),
      KpiGrid(children: [
        KpiTile(
            label: ranged ? 'Credit (In) · period' : 'Total Credit (In)',
            value: compactCr(bs['total_credit']),
            icon: Icons.trending_up,
            tone: Tone.success),
        KpiTile(
            label: ranged ? 'Debit (Out) · period' : 'Total Debit (Out)',
            value: compactCr(bs['total_debit']),
            icon: Icons.trending_down,
            tone: Tone.danger),
        KpiTile(
            label: ranged ? 'Profit · period' : 'Overall Profit',
            value: compactCr(bs['overall_profit']),
            icon: Icons.currency_rupee,
            tone: Tone.success),
        KpiTile(
            label: ranged ? 'Loss · period' : 'Overall Loss',
            value: compactCr(bs['overall_loss']),
            icon: Icons.warning_amber_rounded,
            tone: Tone.danger),
      ]),
      if (lossProjects.isNotEmpty) ...[
        const SizedBox(height: 14),
        Surface(
          margin: const EdgeInsets.symmetric(horizontal: kGutter),
          padding: EdgeInsets.zero,
          color: p.toneFill(Tone.danger),
          borderColor: p.toneBorder(Tone.danger),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, size: 15, color: p.danger),
                const SizedBox(width: 6),
                Eyebrow('Loss-Making Projects', color: p.danger),
              ]),
            ),
            for (final lp in lossProjects)
              RowTile(
                title: '${lp['name']}',
                trailing: figure(context, '−${fmtCrRound(lp['loss']).replaceAll('−', '')}', color: p.danger, strong: true),
                chevron: true,
                onTap: () => openWebPath(context, '/admin/projects/${lp['project_id']}'),
              ),
          ]),
        ),
      ],
      SectionHeader('All Projects — Balance Sheet${ranged ? ' · ${_period.text}' : ''}'),
      RowGroup(
        footer: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Column(children: [
              KeyValueRow('Total Credit (In)', fmtCrRound(bs['total_credit']), valueColor: p.success),
              KeyValueRow('Total Debit (Out)', fmtCrRound(bs['total_debit']), valueColor: p.danger),
            ]),
          ),
          TotalBand('Total · Profit / Loss', fmtCrRound(net), valueColor: net < 0 ? p.danger : p.success),
        ]),
        children: [
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(18), child: Text('No projects yet.', textAlign: TextAlign.center)),
          for (final r in rows)
            _ProjectBalanceRow(
              row: r,
              onTap: () => openWebPath(context, '/admin/projects/${r['project_id']}'),
            ),
          if (overheadsPaid > 0)
            RowTile(
              title: 'Company overheads — staff payroll',
              subtitle: 'Salaries not tied to a project · Debit (Out) ${fmtCrRound(overheadsPaid)}',
              trailing: figure(context, fmtCrRound(-overheadsPaid), color: p.danger, strong: true),
              chevron: true,
              onTap: () => openWebPath(context, '/admin/finance/payroll'),
            ),
        ],
      ),
      const SectionHeader('Required Employee Payments'),
      Surface(
        margin: const EdgeInsets.symmetric(horizontal: kGutter),
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: KeyValueRow('Staff payroll pending', fmtCrRound(dues['staff_payroll_pending']), strong: true),
          ),
          Divider(height: 1, indent: 14, endIndent: 14, color: p.border),
          const Padding(padding: EdgeInsets.fromLTRB(14, 12, 14, 4), child: Eyebrow('Daily-wage labour dues by type')),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final c in cats) KeyValueRow('${c['category']}', fmtCrRound(c['amount'])),
              if (cats.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('No labour attendance recorded.', style: Theme.of(context).textTheme.bodySmall),
                ),
              if (cats.isNotEmpty) KeyValueRow('Labour dues', fmtCrRound(dues['labour_total']), strong: true),
            ]),
          ),
          TotalBand('Total required', fmtCrRound(dues['total_required']), valueColor: p.accentText),
        ]),
      ),
    ]);
    return RefreshList(onRefresh: reload, children: children);
  }
}

class _ProjectBalanceRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onTap;
  const _ProjectBalanceRow({required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final loss = row['is_loss'] == true;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: loss ? p.toneFill(Tone.danger) : null,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('${row['name']}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.titleSmall?.copyWith(color: loss ? p.danger : null)),
            ),
            const SizedBox(width: 8),
            figure(context, fmtCrRound(row['profit_loss']), color: loss ? p.danger : p.success, strong: true),
            Icon(Icons.chevron_right, size: 20, color: p.fgSubtle),
          ]),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Column(children: [
              KeyValueRow('Budget', fmtCrRound(row['budget']), padding: const EdgeInsets.symmetric(vertical: 2)),
              KeyValueRow('Credit (In)', fmtCrRound(row['credit']),
                  valueColor: p.success, padding: const EdgeInsets.symmetric(vertical: 2)),
              KeyValueRow('Debit (Out)', fmtCrRound(row['debit']),
                  valueColor: p.danger, padding: const EdgeInsets.symmetric(vertical: 2)),
            ]),
          ),
        ]),
      ),
    );
  }
}
