import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import 'finance_shared.dart';

/// Project balance sheet (web ProjectBalanceSheetTab.jsx + BalancePeriodPicker): period picker, PDF / Excel
/// export, period and lifetime cards, money-released breakdown, subcontractors, and the chronological
/// ledger with voucher numbers and a running balance. Embedded in a project TabBarView: no Scaffold.
class ProjectBalanceSheetTab extends StatefulWidget {
  final int projectId;
  const ProjectBalanceSheetTab({super.key, required this.projectId});

  @override
  State<ProjectBalanceSheetTab> createState() => _ProjectBalanceSheetTabState();
}

class _LedgerRow {
  final String? date;
  final String voucher;
  final String particulars;
  final bool isCredit;
  final bool isVariation;
  final double credit;
  final double debit;
  final double balance;
  const _LedgerRow(this.date, this.voucher, this.particulars, this.isCredit, this.isVariation, this.credit, this.debit,
      this.balance);
}

class _Ledger {
  final List<_LedgerRow> rows;
  final double totalCredit, totalDebit, closing, opening;
  const _Ledger(this.rows, this.totalCredit, this.totalDebit, this.closing, this.opening);
}

double _r2(double v) => (v * 100).roundToDouble() / 100;
String _pad3(int n) => n.toString().padLeft(3, '0');

/// The web's `buildLedger`: drops the synthetic opening row, sorts ascending (credits before debits on a
/// day), numbers vouchers per type (RCPT-, PYMT-, CO-) and runs Balance = Prev + Credit − Debit.
_Ledger _buildLedger(List<Map<String, dynamic>> raw, double opening) {
  final txns = raw.where((e) => e['type'] == 'credit' || e['type'] == 'debit' || e['type'] == 'variation').toList();
  int rank(dynamic t) => (t == 'credit' || t == 'variation') ? 0 : 1;
  txns.sort((a, b) {
    final da = '${a['date'] ?? ''}', db = '${b['date'] ?? ''}';
    if (da != db) return da.compareTo(db);
    return rank(a['type']) - rank(b['type']);
  });
  var rcpt = 0, pymt = 0, co = 0;
  var running = opening;
  final rows = <_LedgerRow>[];
  for (final e in txns) {
    final isCredit = e['type'] == 'credit' || e['type'] == 'variation';
    String voucher;
    if (e['type'] == 'variation') {
      voucher = 'CO-${_pad3(++co)}';
    } else if (isCredit) {
      voucher = 'RCPT-${_pad3(++rcpt)}';
    } else {
      voucher = 'PYMT-${_pad3(++pymt)}';
    }
    final amount = toNum(e['amount']);
    final credit = isCredit ? amount : 0.0;
    final debit = isCredit ? 0.0 : amount;
    running = running + credit - debit;
    rows.add(_LedgerRow(e['date'] as String?, voucher, '${e['description'] ?? ''}', isCredit, e['type'] == 'variation', credit,
        debit, _r2(running)));
  }
  final tc = _r2(rows.fold(0.0, (s, r) => s + r.credit));
  final td = _r2(rows.fold(0.0, (s, r) => s + r.debit));
  return _Ledger(rows, tc, td, _r2(opening + tc - td), opening);
}

class _ProjectBalanceSheetTabState extends State<ProjectBalanceSheetTab> with AutomaticKeepAliveClientMixin {
  Period _period = const Period();
  Map<String, dynamic>? _bs;
  _Ledger? _ledger;
  Object? _error;
  int _gen = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant ProjectBalanceSheetTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _bs = null;
      _reload();
    }
  }

  /// Keeps the last sheet visible while another period loads (web `placeholderData`).
  Future<void> _reload() async {
    if (!_period.valid) return;
    final gen = ++_gen;
    setState(() => _error = null);
    try {
      final d = jMap(await apiOf(context).get('/projects/${widget.projectId}/balance-sheet', params: _period.params));
      if (!mounted || gen != _gen) return;
      final opening = toNum(jMap(d['period'])['opening_balance']);
      setState(() {
        _bs = d;
        _ledger = _buildLedger(jList(d['entries']), opening);
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() => _error = e);
    }
  }

  void _setPeriod(Period v) {
    setState(() => _period = v);
    _reload();
  }

  Future<void> _export(String fmt) => downloadAndOpen(
        context,
        apiOf(context),
        '/projects/${widget.projectId}/balance-sheet/export',
        params: {'fmt': fmt, ..._period.params},
        fallbackName: 'project-balance-sheet-${_period.fileTag}.$fmt',
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final pal = context.pal;
    final bs = _bs;
    final ledger = _ledger;
    final children = <Widget>[PeriodPicker(value: _period, onChanged: _setPeriod)];
    if (bs == null || ledger == null) {
      children.add(_error != null
          ? ErrorRetry(message: errorText(_error), onRetry: _reload)
          : const LoadingView(label: 'Loading balance sheet…'));
      return RefreshList(onRefresh: _reload, children: children);
    }

    final p = bs['period'] == null ? null : jMap(bs['period']);
    final r = jMap(p != null ? p['released'] : bs['released']);
    final sc = bs['subcontractors'] == null ? null : jMap(bs['subcontractors']);
    Tone signTone(dynamic v) => toNum(v) < 0 ? Tone.danger : Tone.success;
    Color? balColor(double v) => v < 0 ? pal.danger : null;
    final released = [
      ('Daily-Wage Labour', r['labour_wages']),
      ('Staff Payroll', r['staff_payroll']),
      ('Site Expenses', r['expenses']),
      ('Procurement (paid to POs + subcontractors)', r['procurement']),
      ('Vendor Payments', r['vendor_payments']),
    ];
    final releasedTotal = released.fold(0.0, (s, x) => s + toNum(x.$2));
    final approvedVariations = toNum(bs['approved_variations']);

    children.addAll([
      if (_error != null) NoteText(errorText(_error)),
      ExportButtons(enabled: _period.valid, onExport: _export),
      if (p != null) ...[
        SectionHeader('Period · ${_period.text}', padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 8)),
        KpiGrid(children: [
          KpiTile(
              label: 'Opening Balance',
              value: compactCr(p['opening_balance']),
              sub: 'Brought forward from before the period',
              icon: Icons.account_balance_wallet_outlined,
              tone: toNum(p['opening_balance']) < 0 ? Tone.danger : null),
          KpiTile(label: 'Money In', value: compactCr(p['credit']), icon: Icons.trending_up, tone: Tone.success),
          KpiTile(label: 'Money Out', value: compactCr(p['debit']), icon: Icons.trending_down, tone: Tone.danger),
          KpiTile(
              label: 'Closing Balance',
              value: compactCr(p['closing_balance']),
              sub: 'Net for the period: ${fmtAmt(p['net'])}',
              icon: Icons.account_balance_wallet_outlined,
              tone: signTone(p['closing_balance'])),
        ]),
        const NoteText('The cards below are for the whole project to date.',
            padding: EdgeInsets.fromLTRB(kGutter, 8, kGutter, 4)),
      ],
      const SizedBox(height: 8),
      KpiGrid(children: [
        KpiTile(
            label: 'Total Budget',
            value: compactCr(bs['budget']),
            sub: approvedVariations > 0
                ? 'Revised contract: ${fmtAmt(bs['revised_contract_value'])} (incl. variations +${fmtAmt(approvedVariations)})'
                : null,
            icon: Icons.currency_rupee,
            tone: Tone.info),
        KpiTile(
            label: 'Client Payment (In)',
            value: compactCr(bs['client_paid']),
            sub: 'Outstanding from client: ${fmtAmt(bs['client_outstanding'])}',
            icon: Icons.trending_up,
            tone: Tone.success),
        KpiTile(label: 'Payment Released (Out)', value: compactCr(bs['total_released']), icon: Icons.trending_down, tone: Tone.danger),
        KpiTile(
            label: 'Balance (In − Out)',
            value: compactCr(bs['balance']),
            sub: 'Budget remaining: ${fmtAmt(bs['budget_remaining'])}',
            icon: Icons.account_balance_wallet_outlined,
            tone: signTone(bs['balance'])),
      ]),
      SectionHeader('Where the money is going — Payment Released Breakdown${p != null ? ' · ${_period.text}' : ''}'),
      RowGroup(
        footer: TotalBand('Payment Released (Out)', fmtAmt(releasedTotal), valueColor: pal.danger),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Column(children: [for (final (label, amt) in released) KeyValueRow(label, fmtAmt(amt))]),
          ),
        ],
      ),
      if (sc != null && (toNum(sc['paid']) > 0 || toNum(sc['contract_value']) > 0)) ...[
        const SectionHeader('Subcontractors — contract, paid and due'),
        RowGroup(
          footer: TotalBand('Due (contract − paid)', fmtAmt(sc['due'])),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              child: Column(children: [
                KeyValueRow('Contract given', fmtAmt(sc['contract_value'])),
                KeyValueRow('Paid to them (money out)', fmtAmt(sc['paid']), valueColor: pal.danger),
              ]),
            ),
          ],
        ),
        const NoteText('Only what has been paid reduces the balance. Due is still to be paid, so it is not money out yet.',
            padding: EdgeInsets.fromLTRB(kGutter, 8, kGutter, 0)),
      ],
      SectionHeader('Transaction Ledger — Chronological Order${p != null ? ' · ${_period.text}' : ''}'),
      RowGroup(
        header: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(children: [
            Expanded(child: Text('Opening Balance b/f'.toUpperCase(), style: Theme.of(context).textTheme.labelSmall)),
            Text(fmtAmt(ledger.opening),
                style: tabular(Theme.of(context).textTheme.titleSmall)
                    .copyWith(fontWeight: FontWeight.w700, color: balColor(ledger.opening))),
          ]),
        ),
        footer: ledger.rows.isEmpty
            ? null
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                  child: Column(children: [
                    KeyValueRow('Total Debit', fmtAmt(ledger.totalDebit), valueColor: pal.danger),
                    KeyValueRow('Total Credit', fmtAmt(ledger.totalCredit), valueColor: pal.success),
                  ]),
                ),
                TotalBand('Totals / Closing Balance c/f', fmtAmt(ledger.closing), valueColor: balColor(ledger.closing)),
              ]),
        children: [
          if (ledger.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(p != null ? 'No transactions in this period.' : 'No transactions yet.',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ),
          for (final row in ledger.rows) _LedgerTile(row: row, balanceColor: balColor(row.balance)),
        ],
      ),
    ]);
    return RefreshList(onRefresh: _reload, children: children);
  }
}

class _LedgerTile extends StatelessWidget {
  final _LedgerRow row;
  final Color? balanceColor;
  const _LedgerTile({required this.row, this.balanceColor});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.particulars, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 5),
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(fmtDate(row.date), style: tabular(tt.bodySmall)),
              CodeTag(row.voucher),
              StatusChip(row.isCredit ? 'Credit' : 'Debit', tone: row.isCredit ? Tone.success : Tone.danger, dense: true),
              if (row.isVariation) const StatusChip('Variation', tone: Tone.warning, dense: true),
            ]),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          figure(context, row.isCredit ? '+${fmtAmt(row.credit)}' : '−${fmtAmt(row.debit)}',
              color: row.isCredit ? p.success : p.danger, strong: true),
          const SizedBox(height: 4),
          Text('Bal ${fmtAmt(row.balance)}',
              style: tabular(tt.bodySmall).copyWith(color: balanceColor, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}
