import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import 'finance_shared.dart';

/// One project's money (web ProjectFinancePage.jsx): summary cards, contract value and variations,
/// invoices with record payment and print / share, the expense log, expense categories and the ledger.
/// Pushed screen.
class ProjectFinanceScreen extends StatefulWidget {
  final int projectId;
  const ProjectFinanceScreen({super.key, required this.projectId});

  @override
  State<ProjectFinanceScreen> createState() => _ProjectFinanceScreenState();
}

class _Data {
  final Map<String, dynamic> project;
  final Map<String, dynamic>? summary;
  final List<Map<String, dynamic>> invoices;
  final List<Map<String, dynamic>>? expenses;
  final List<Map<String, dynamic>>? categories;
  final Map<String, dynamic>? ledger;
  const _Data(this.project, this.summary, this.invoices, this.expenses, this.categories, this.ledger);
}

class _ProjectFinanceScreenState extends State<ProjectFinanceScreen> {
  final _key = GlobalKey<AsyncViewState<_Data>>();
  String? _projectName;

  int get _id => widget.projectId;

  Future<_Data> _load() async {
    final api = apiOf(context);
    final user = context.read<AuthProvider>().user;
    final canFin = user?.roleIn(['Admin', 'Accountant']) ?? false;
    final canSee = canFin || (user?.roleIn(['ProjectManager', 'SiteEngineer']) ?? false);
    final canLedger = canSee || user?.role == 'ProcurementOfficer';
    Future<dynamic> none() async => null;
    final r = await Future.wait([
      api.get('/projects/$_id'),
      canSee ? api.get('/projects/$_id/finance/summary') : none(),
      api.get('/projects/$_id/invoices'),
      canSee ? api.get('/projects/$_id/expenses') : none(),
      canSee ? api.get('/expense-categories') : none(),
      canLedger ? api.get('/projects/$_id/ledger') : none(),
    ]);
    final project = jMap(r[0]);
    if (mounted && _projectName != project['name']) setState(() => _projectName = project['name'] as String?);
    return _Data(
      project,
      r[1] == null ? null : jMap(r[1]),
      jList(r[2]),
      r[3] == null ? null : jList(r[3]),
      r[4] == null ? null : jList(r[4]),
      r[5] == null ? null : jMap(r[5]),
    );
  }

  Future<void> _reload() async => _key.currentState?.reload();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final canFin = user?.roleIn(['Admin', 'Accountant']) ?? false;
    final canSee = canFin || (user?.roleIn(['ProjectManager', 'SiteEngineer']) ?? false);
    return AppScaffold(
      title: 'Project Finance',
      subtitle: _projectName,
      body: AsyncView<_Data>(
        key: _key,
        load: _load,
        builder: (context, d, reload) => _Body(
          projectId: _id,
          data: d,
          canFin: canFin,
          canSee: canSee,
          reload: reload,
          onAddIncome: () => showIncomeSheet(context, defaultProjectId: _id, onSaved: _reload),
          onAddExpense: () => showExpenseSheet(context, defaultProjectId: _id, onSaved: _reload),
        ),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  final int projectId;
  final _Data data;
  final bool canFin;
  final bool canSee;
  final Future<void> Function() reload;
  final VoidCallback onAddIncome;
  final VoidCallback onAddExpense;
  const _Body({
    required this.projectId,
    required this.data,
    required this.canFin,
    required this.canSee,
    required this.reload,
    required this.onAddIncome,
    required this.onAddExpense,
  });

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _expAmount = TextEditingController();
  final _newCat = TextEditingController();
  String? _expCategory;
  bool _expBusy = false;
  bool _catBusy = false;

  int get _id => widget.projectId;
  String? get _projectName => widget.data.project['name'] as String?;
  String? get _clientName => widget.data.project['client_name'] as String?;

  @override
  void dispose() {
    _expAmount.dispose();
    _newCat.dispose();
    super.dispose();
  }

  /// The web's `run(fn, ok)`: toast, then refresh.
  Future<bool> _run(Future<void> Function() fn, String ok) async {
    final done = await runAction(context, fn, success: ok);
    if (done) await widget.reload();
    return done;
  }

  Future<void> _newInvoice() async {
    final created = await showAppSheet<bool>(context,
        title: 'New invoice', builder: (ctx) => _InvoiceForm(projectId: _id));
    if (created == true) await widget.reload();
  }

  Future<void> _recordPayment(Map<String, dynamic> inv) async {
    final amt = await askAmount(context,
        title: 'Record payment',
        subtitle: 'Payment amount for ${inv['invoice_number']} (balance ${inr(inv['balance_due'])})',
        initial: inv['balance_due'],
        confirmLabel: 'Record payment');
    if (amt == null || !mounted) return;
    await _run(() => apiOf(context).post('/invoices/${inv['id']}/payments', data: {'amount': amt}), 'Payment recorded');
  }

  Future<void> _addExpense() async {
    setState(() => _expBusy = true);
    final ok = await _run(
        () => apiOf(context).post('/projects/$_id/expenses',
            data: {'category': _expCategory ?? 'Misc', 'amount': toNum(_expAmount.text)}),
        'Expense added');
    if (!mounted) return;
    setState(() {
      _expBusy = false;
      if (ok) {
        _expCategory = null;
        _expAmount.clear();
      }
    });
  }

  Future<void> _addCategory() async {
    setState(() => _catBusy = true);
    final ok = await _run(() => apiOf(context).post('/expense-categories', data: {'name': _newCat.text.trim()}), 'Category added');
    if (!mounted) return;
    setState(() {
      _catBusy = false;
      if (ok) _newCat.clear();
    });
  }

  Future<void> _editCategory(Map<String, dynamic> c) async {
    final name = await promptText(context,
        title: 'Rename category', label: 'Rename category "${c['name']}" to:', initial: '${c['name']}', maxLines: 1);
    if (name == null || name.trim().isEmpty || name.trim() == c['name'] || !mounted) return;
    await _run(() => apiOf(context).patch('/expense-categories/${c['id']}', data: {'name': name.trim()}), 'Category renamed');
  }

  Future<void> _deleteCategory(Map<String, dynamic> c) async {
    final ok = await confirmDialog(context,
        title: 'Delete category?',
        message: 'Delete category "${c['name']}"? Existing expenses keep their label.',
        confirmLabel: 'Delete',
        destructive: true);
    if (!ok || !mounted) return;
    await _run(() => apiOf(context).delete('/expense-categories/${c['id']}'), 'Category deleted');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final d = widget.data;
    final s = d.summary;
    final canExp = widget.canSee;
    final cats = d.categories ?? const <Map<String, dynamic>>[];
    final children = <Widget>[];

    if (widget.canSee) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 8),
        child: Row(children: [
          if (widget.canFin) ...[
            Expanded(
              child: ToneButton(
                  label: 'Add Income', icon: Icons.add, color: p.success, height: 46, onPressed: widget.onAddIncome),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: ToneButton(
                label: 'Add Expense', icon: Icons.remove, color: p.danger, height: 46, onPressed: widget.onAddExpense),
          ),
        ]),
      ));
    }

    if (s != null) {
      final period = '1 year · ${fmtDate(s['period_from'])} → ${fmtDate(s['period_to'])}';
      final profit = toNum(s['profit']);
      children.addAll([
        const SizedBox(height: 4),
        KpiGrid(children: [
          KpiTile(label: 'Revenue from Client', value: compactCr(s['revenue_last_year']), sub: period, icon: Icons.trending_up),
          KpiTile(label: 'Expense', value: compactCr(s['cost_last_year']), sub: period, icon: Icons.trending_down),
          KpiTile(
              label: 'Profit',
              value: compactCr(profit),
              sub: period,
              icon: Icons.currency_rupee,
              tone: profit < 0 ? Tone.danger : null),
          KpiTile(label: 'Outstanding', value: compactCr(s['outstanding_invoices']), icon: Icons.receipt_long_outlined),
        ]),
        const SizedBox(height: 14),
        Surface(
          margin: const EdgeInsets.symmetric(horizontal: kGutter),
          color: p.toneFill(Tone.warning),
          borderColor: p.toneBorder(Tone.warning),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Eyebrow('Contract Value & Approved Variations (Change Orders)', color: p.warning),
            const SizedBox(height: 6),
            KeyValueRow('Original Contract', inr(s['original_budget'])),
            KeyValueRow('Approved Variations', '+${inr(s['approved_variations'])} (${toInt(s['approved_co_count'])})',
                valueColor: p.accentText),
            KeyValueRow('Revised Contract Value', inr(s['revised_contract_value']), strong: true),
            KeyValueRow('Pending Client Review', inr(s['pending_co_value']), valueColor: p.info),
          ]),
        ),
      ]);
    }

    // Invoices & Payments
    children.add(SectionHeader('Invoices & Payments',
        trailing: widget.canFin
            ? TextButton.icon(onPressed: _newInvoice, icon: const Icon(Icons.add, size: 16), label: const Text('Invoice'))
            : null));
    if (d.invoices.isEmpty) {
      children.add(const EmptyLine('No invoices yet.'));
    }
    for (final inv in d.invoices) {
      children.add(_InvoiceCard(
        inv: inv,
        canWrite: widget.canFin,
        projectName: _projectName,
        clientName: _clientName,
        projectId: _id,
        onPay: () => _recordPayment(inv),
      ));
    }

    // Expense Log
    if (d.expenses != null) {
      children.add(const SectionHeader('Expense Log'));
      if (canExp) {
        children.add(Surface(
          margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 5,
              child: AppDropdown<String?>(
                label: 'Category',
                hint: 'Category…',
                value: _expCategory,
                items: [(null, 'Category…'), for (final c in cats) ('${c['name']}', '${c['name']}')],
                onChanged: (v) => setState(() => _expCategory = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: AppTextField(controller: _expAmount, label: '₹', money: true, onChanged: (_) => setState(() {})),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 52,
              child: IconButton.filled(
                tooltip: 'Add expense',
                onPressed: _expBusy || _expAmount.text.isEmpty ? null : _addExpense,
                icon: _expBusy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
                    : const Icon(Icons.add),
              ),
            ),
          ]),
        ));
      }
      final expenses = d.expenses!;
      if (expenses.isEmpty) {
        children.add(const EmptyLine('No expenses yet.'));
      } else {
        children.add(RowGroup(children: [
          for (final e in expenses)
            RowTile(
              title: '${e['category']}',
              subtitle: [fmtDate(e['expense_date']), if ((e['description'] ?? '').toString().isNotEmpty) e['description']]
                  .join(' · '),
              trailing: figure(context, inr(e['amount']), strong: true),
            ),
        ]));
      }
    }

    // Expense Categories
    if (canExp && d.categories != null) {
      children.addAll([
        const SectionHeader('Expense Categories'),
        Surface(
          margin: const EdgeInsets.symmetric(horizontal: kGutter),
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
              child: Row(children: [
                Expanded(
                  child: AppTextField(
                    controller: _newCat,
                    label: 'New category name',
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (_newCat.text.trim().isNotEmpty && !_catBusy) _addCategory();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: 'Add category',
                  onPressed: _catBusy || _newCat.text.trim().isEmpty ? null : _addCategory,
                  icon: const Icon(Icons.add),
                ),
              ]),
            ),
            if (cats.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                child: Text('No categories yet.', style: Theme.of(context).textTheme.bodySmall),
              ),
            for (final c in cats) ...[
              Divider(height: 1, indent: 14, endIndent: 14, color: p.border),
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Row(children: [
                  Icon(Icons.sell_outlined, size: 15, color: p.accentText),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${c['name']}', style: Theme.of(context).textTheme.bodyMedium)),
                  IconButton(
                    tooltip: 'Edit category',
                    icon: Icon(Icons.edit_outlined, size: 19, color: p.fgMuted),
                    onPressed: () => _editCategory(c),
                  ),
                  IconButton(
                    tooltip: 'Delete category',
                    icon: Icon(Icons.delete_outline, size: 19, color: p.danger),
                    onPressed: () => _deleteCategory(c),
                  ),
                ]),
              ),
            ],
          ]),
        ),
      ]);
    }

    // Ledger
    final ledger = d.ledger;
    if (ledger != null) {
      final entries = jList(ledger['entries']);
      final net = toNum(ledger['net']);
      children.addAll([
        const SectionHeader('Project Ledger — Credits & Debits'),
        RowGroup(
          header: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Column(children: [
              KeyValueRow('Credit', inr(ledger['total_credit']), valueColor: p.success),
              KeyValueRow('Debit', inr(ledger['total_debit']), valueColor: p.danger),
            ]),
          ),
          footer: TotalBand('Net', inr(ledger['net']), valueColor: net >= 0 ? p.success : p.danger),
          children: [
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text('No transactions yet.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              ),
            for (final en in entries)
              RowTile(
                title: '${en['description']}',
                subtitle: fmtDate(en['date']),
                trailing: figure(
                  context,
                  '${en['type'] == 'credit' ? '+' : '−'}${inr(en['amount'])}',
                  color: en['type'] == 'credit' ? p.success : p.danger,
                  strong: true,
                ),
              ),
          ],
        ),
      ]);
    }

    return RefreshList(onRefresh: widget.reload, children: children);
  }
}

class _InvoiceCard extends StatelessWidget {
  final Map<String, dynamic> inv;
  final bool canWrite;
  final String? projectName;
  final String? clientName;
  final int projectId;
  final VoidCallback onPay;
  const _InvoiceCard({
    required this.inv,
    required this.canWrite,
    required this.projectName,
    required this.clientName,
    required this.projectId,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final canPay = canWrite && toNum(inv['balance_due']) > 0 && inv['status'] != 'Cancelled';
    final desc = (inv['description'] ?? '').toString();
    return Surface(
      margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Flexible(
            child: Text('${inv['invoice_number']}',
                overflow: TextOverflow.ellipsis,
                style: tt.titleMedium?.copyWith(color: p.accentText, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          StatusChip('${inv['status']}', dense: true),
          const Spacer(),
          Padding(padding: const EdgeInsets.only(right: 8), child: figure(context, inr(inv['total']), strong: true)),
        ]),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(['Due ${fmtDate(inv['due_date'])}', if (desc.isNotEmpty) desc].join(' · '), style: tt.bodySmall),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text('Paid ${inr(inv['paid_amount'])}', style: _small(context, p.success)),
          const SizedBox(width: 14),
          Text('Balance ${inr(inv['balance_due'])}', style: _small(context, p.warning)),
        ]),
        Row(children: [
          if (canPay)
            TextButton.icon(
              onPressed: onPay,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Record Payment'),
            ),
          const Spacer(),
          InvoiceShareButtons(inv: inv, projectName: projectName, clientName: clientName, projectId: projectId),
        ]),
      ]),
    );
  }
}

TextStyle _small(BuildContext context, Color color) =>
    tabular(Theme.of(context).textTheme.bodySmall).copyWith(color: color, fontWeight: FontWeight.w600);

class _InvoiceForm extends StatefulWidget {
  final int projectId;
  const _InvoiceForm({required this.projectId});

  @override
  State<_InvoiceForm> createState() => _InvoiceFormState();
}

class _InvoiceFormState extends State<_InvoiceForm> {
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  String? _due;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => apiOf(context).post('/projects/${widget.projectId}/invoices', data: {
        'amount': toNum(_amount.text),
        'due_date': _due,
        'description': _desc.text.isEmpty ? null : _desc.text,
      }),
      success: 'Invoice created',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(controller: _amount, label: 'Amount ₹', money: true, requiredField: true, onChanged: (_) => setState(() {})),
        kFieldGap,
        DateField(label: 'Due date', value: _due, onChanged: (v) => setState(() => _due = v)),
        kFieldGap,
        AppTextField(controller: _desc, label: 'Description'),
        const SizedBox(height: 20),
        SubmitButton(
          label: 'Invoice',
          icon: Icons.add,
          busy: _busy,
          onPressed: _amount.text.isEmpty ? null : _save,
        ),
      ]);
}
