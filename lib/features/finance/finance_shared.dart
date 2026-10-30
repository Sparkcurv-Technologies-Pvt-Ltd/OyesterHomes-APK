import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';

// Shared pieces of the finance screens (private to lib/features/finance):
// JSON helpers, the web's money formats, BalancePeriodPicker, AddIncomeModal / AddExpenseModal as
// bottom sheets, an amount prompt, and the invoice share / print helpers from utils/invoiceShare.js.

// ───────────────────────────────────────────────────────── json & formats

Map<String, dynamic> jMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> jList(dynamic v) => v is List ? v.map(jMap).toList() : <Map<String, dynamic>>[];

/// Web `fmtCr`: "−₹1,23,456" for negatives.
String fmtCr(dynamic n) {
  final v = toNum(n);
  return '${v < 0 ? '−' : ''}${inr(v.abs())}';
}

/// Web OrgBalanceSheetTab `fmt` / `fmtCr`: whole rupees.
String fmtCrRound(dynamic n) => fmtCr(toNum(n).roundToDouble());

/// Accounting format (ProjectBalanceSheetTab `fmtAmt`): two decimals, negatives in parentheses.
String fmtAmt(dynamic n) {
  final v = toNum(n);
  final s = inr(v.abs(), forceDecimals: true);
  return v < 0 ? '($s)' : s;
}

/// Compact figure for KPI tiles with the web's leading minus.
String compactCr(dynamic n) {
  final v = toNum(n);
  return '${v < 0 ? '−' : ''}${inrCompact(v.abs())}';
}

/// Web lib/date.js `fmtDateRange`.
String fmtDateRange(dynamic a, dynamic b) {
  final ea = a == null || a.toString().isEmpty, eb = b == null || b.toString().isEmpty;
  if (ea && eb) return '—';
  final x = fmtDate(a, empty: '…'), y = fmtDate(b, empty: '…');
  return x == y ? x : '$x – $y';
}

ApiClient apiOf(BuildContext context) => context.read<ApiClient>();

// ───────────────────────────────────────────────────────── BalancePeriodPicker

/// A report period; empty strings mean open-ended (web `{from, to}`).
@immutable
class Period {
  final String from, to;
  const Period([this.from = '', this.to = '']);

  bool get valid => !(from.isNotEmpty && to.isNotEmpty && from.compareTo(to) > 0);
  bool get ranged => from.isNotEmpty || to.isNotEmpty;

  /// `periodParams`.
  Map<String, dynamic> get params => {if (from.isNotEmpty) 'date_from': from, if (to.isNotEmpty) 'date_to': to};

  /// `periodFileTag`.
  String get fileTag => ranged ? '${from.isEmpty ? 'start' : from}_to_${to.isEmpty ? 'today' : to}' : 'all-time';

  /// `periodText`.
  String get text {
    if (!ranged) return 'All time';
    if (from.isNotEmpty && to.isNotEmpty) return from == to ? fmtDate(from) : '${fmtDate(from)} – ${fmtDate(to)}';
    return from.isNotEmpty ? 'From ${fmtDate(from)}' : 'Up to ${fmtDate(to)}';
  }

  @override
  bool operator ==(Object other) => other is Period && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
}

String _shift(int days) => isoDay(DateTime.now().add(Duration(days: days)));

/// `PERIOD_PRESETS`.
List<(String, String, Period Function())> get periodPresets {
  final now = DateTime.now();
  return [
    ('all', 'All time', () => const Period()),
    ('today', 'Today', () => Period(_shift(0), _shift(0))),
    ('yesterday', 'Yesterday', () => Period(_shift(-1), _shift(-1))),
    ('week', 'This week', () => Period(isoDay(now.subtract(Duration(days: now.weekday - 1))), _shift(0))),
    ('7d', 'Last 7 days', () => Period(_shift(-6), _shift(0))),
    ('month', 'This month', () => Period(isoDay(DateTime(now.year, now.month, 1)), _shift(0))),
  ];
}

class PeriodPicker extends StatelessWidget {
  final Period value;
  final ValueChanged<Period> onChanged;
  const PeriodPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final presets = periodPresets;
    String? active;
    for (final (k, _, fn) in presets) {
      if (fn() == value) {
        active = k;
        break;
      }
    }
    return Surface(
      margin: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 8),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilterBar<String?>(
          value: active,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          options: [for (final (k, l, _) in presets) (k, l)],
          onChanged: (k) => onChanged(presets.firstWhere((e) => e.$1 == k).$3()),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
              child: DateField(
                  label: 'From',
                  value: value.from.isEmpty ? null : value.from,
                  onChanged: (v) => onChanged(Period(v ?? '', value.to))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DateField(
                  label: 'To', value: value.to.isEmpty ? null : value.to, onChanged: (v) => onChanged(Period(value.from, v ?? ''))),
            ),
          ]),
        ),
        if (!value.valid)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text('“From” is after “To”.', style: TextStyle(color: p.danger, fontSize: 12.5)),
          ),
      ]),
    );
  }
}

/// Export PDF / Export Excel buttons for a balance sheet.
class ExportButtons extends StatelessWidget {
  final bool enabled;
  final Future<void> Function(String fmt) onExport;
  const ExportButtons({super.key, required this.enabled, required this.onExport});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: enabled ? () => onExport('pdf') : null,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Export PDF'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: enabled ? () => onExport('xlsx') : null,
              icon: const Icon(Icons.table_chart_outlined, size: 18),
              label: const Text('Export Excel'),
            ),
          ),
        ]),
      );
}

/// Muted explanatory line.
class NoteText extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;
  const NoteText(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8)});

  @override
  Widget build(BuildContext context) =>
      Padding(padding: padding, child: Text(text, style: Theme.of(context).textTheme.bodySmall));
}

/// Small centred "nothing here" line inside a list section.
class EmptyLine extends StatelessWidget {
  final String text;
  const EmptyLine(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Surface(
        margin: const EdgeInsets.symmetric(horizontal: kGutter),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      );
}

/// Filled button in a state colour (green "Save Income", red "Add Expense") with a busy spinner.
class ToneButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool busy;
  final VoidCallback? onPressed;
  final double height;
  const ToneButton(
      {super.key, required this.label, required this.color, this.icon, this.busy = false, this.onPressed, this.height = 50});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
          onPressed: busy ? null : onPressed,
          child: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ]),
        ),
      );
}

// ───────────────────────────────────────────────────────── amount prompt

/// Asks for one ₹ amount (the web's `window.prompt` for a payment / approval). Null when dismissed.
Future<double?> askAmount(BuildContext context,
    {required String title, String? subtitle, String label = 'Amount (₹)', dynamic initial, String confirmLabel = 'Save'}) {
  return showAppSheet<double>(context,
      title: title,
      subtitle: subtitle,
      builder: (ctx) => _AmountForm(label: label, initial: initial, confirmLabel: confirmLabel));
}

class _AmountForm extends StatefulWidget {
  final String label;
  final dynamic initial;
  final String confirmLabel;
  const _AmountForm({required this.label, this.initial, required this.confirmLabel});

  @override
  State<_AmountForm> createState() => _AmountFormState();
}

class _AmountFormState extends State<_AmountForm> {
  late final _c = TextEditingController(text: inputNum(widget.initial));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double get _v => toNum(_c.text);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(controller: _c, label: widget.label, money: true, autofocus: true, onChanged: (_) => setState(() {})),
        const SizedBox(height: 18),
        SubmitButton(label: widget.confirmLabel, onPressed: _v > 0 ? () => Navigator.pop(context, _v) : null),
      ]);
}

// ───────────────────────────────────────────────────────── AddIncomeModal / AddExpenseModal

const paymentTypes = ['Advance Payment', 'Partial Payment', 'Full Payment'];
const _addNew = -1;

/// AddIncomeModal. [onSaved] runs after every saved income (the sheet may stay open for "Save + Add Another").
Future<void> showIncomeSheet(BuildContext context, {int? defaultProjectId, required VoidCallback onSaved}) =>
    showAppSheet<void>(context,
        title: 'Add Income',
        subtitle: "Record a client payment — it posts as a CREDIT in the project's balance sheet.",
        builder: (ctx) => _IncomeForm(defaultProjectId: defaultProjectId, onSaved: onSaved));

/// AddExpenseModal with inline vendor / product / employee creation.
Future<void> showExpenseSheet(BuildContext context, {int? defaultProjectId, required VoidCallback onSaved}) =>
    showAppSheet<void>(context,
        title: 'Add Expense',
        subtitle: 'Record an outgoing payment — it posts as a DEBIT and syncs with Vendors, Procurement or Field Ops.',
        builder: (ctx) => _ExpenseForm(defaultProjectId: defaultProjectId, onSaved: onSaved));

class _IncomeForm extends StatefulWidget {
  final int? defaultProjectId;
  final VoidCallback onSaved;
  const _IncomeForm({this.defaultProjectId, required this.onSaved});

  @override
  State<_IncomeForm> createState() => _IncomeFormState();
}

class _IncomeFormState extends State<_IncomeForm> {
  List<Map<String, dynamic>>? _projects;
  Object? _error;
  int? _projectId;
  final _phase = TextEditingController();
  final _amount = TextEditingController();
  final _balance = TextEditingController();
  String _ptype = 'Partial Payment';
  bool _touched = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _projectId = widget.defaultProjectId;
    _load();
  }

  @override
  void dispose() {
    _phase.dispose();
    _amount.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = jMap(await apiOf(context).get('/finance/transaction-context'));
      if (!mounted) return;
      setState(() => _projects = jList(d['projects']));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Map<String, dynamic>? get _project {
    for (final p in _projects ?? const <Map<String, dynamic>>[]) {
      if (p['id'] == _projectId) return p;
    }
    return null;
  }

  double get _amt => toNum(_amount.text);

  double? get _autoBalance {
    final p = _project;
    if (p == null || _amount.text.isEmpty) return null;
    return ((toNum(p['budget']) - _amt) * 100).roundToDouble() / 100;
  }

  void _syncBalance() {
    if (_touched) return;
    final a = _autoBalance;
    _balance.text = a == null ? '' : inputNum(a);
  }

  bool get _valid => _projectId != null && _amt > 0;

  Future<void> _submit(bool addAnother) async {
    setState(() => _saving = true);
    try {
      final amt = _amt;
      final d = jMap(await apiOf(context).post('/transactions/income', data: {
        'project_id': _projectId,
        'phase': _phase.text.trim().isEmpty ? null : _phase.text.trim(),
        'amount': amt,
        'payment_type': _ptype,
        'balance': _touched && _balance.text.isNotEmpty ? toNum(_balance.text) : null,
      }));
      if (!mounted) return;
      showToast(context,
          'Income of ${inr(amt)} recorded · budget remaining ${inr(d['project_budget_remaining'])}${d['override'] == true ? ' (balance override logged)' : ''}');
      widget.onSaved();
      if (addAnother) {
        setState(() {
          _amount.clear();
          _balance.clear();
          _touched = false;
        });
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(message: errorText(_error), onRetry: _load);
    if (_projects == null) return const LoadingView();
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final project = _project;
    final auto = _autoBalance;
    final overridden = _touched && auto != null && toNum(_balance.text) != auto;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppDropdown<int>(
        label: 'Project',
        requiredField: true,
        hint: 'Select active project',
        value: _projectId,
        items: [for (final x in _projects!) (x['id'] as int, '${x['name']}')],
        onChanged: (v) => setState(() {
          _projectId = v;
          _syncBalance();
        }),
      ),
      kFieldGap,
      AppTextField(controller: _phase, label: 'Phase / Milestone (optional)', hint: 'e.g. Foundation advance'),
      kFieldGap,
      AppTextField(
          controller: _amount,
          label: 'Amount (₹)',
          money: true,
          requiredField: true,
          onChanged: (_) => setState(_syncBalance)),
      kFieldGap,
      ChoiceRow<String>(
          label: 'Payment Type *',
          value: _ptype,
          options: [for (final t in paymentTypes) (t, t)],
          onChanged: (v) => setState(() => _ptype = v)),
      kFieldGap,
      AppTextField(
        controller: _balance,
        label: 'Balance (auto: budget − amount, editable)',
        money: true,
        onChanged: (_) => setState(() => _touched = true),
      ),
      if (project != null && _amount.text.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(style: tt.bodySmall, children: [
            TextSpan(text: 'Budget ${inr(project['budget'])} − ${inr(_amt)} = '),
            TextSpan(text: inr(auto), style: TextStyle(fontWeight: FontWeight.w700, color: p.success)),
            if (overridden)
              TextSpan(
                  text: '  Override will be logged for audit', style: TextStyle(fontWeight: FontWeight.w600, color: p.warning)),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      ToneButton(
        label: 'Save Income',
        color: p.success,
        busy: _saving,
        onPressed: _valid ? () => _submit(false) : null,
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 48,
        child: OutlinedButton(
          onPressed: _valid && !_saving ? () => _submit(true) : null,
          child: const Text('Save + Add Another'),
        ),
      ),
    ]);
  }
}

class _ExpenseForm extends StatefulWidget {
  final int? defaultProjectId;
  final VoidCallback onSaved;
  const _ExpenseForm({this.defaultProjectId, required this.onSaved});

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  List<Map<String, dynamic>>? _projects;
  List<Map<String, dynamic>> _vendors = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _employees = [];
  Object? _error;

  int? _projectId, _phaseId, _vendorId, _productId, _employeeId;
  String _source = 'Vendor';
  String _ptype = 'Partial Payment';
  final _qty = TextEditingController(text: '1');
  final _desc = TextEditingController();
  final _amount = TextEditingController();

  /// Open inline form: 'vendor' | 'product' | 'employee'.
  String? _mini;
  final Map<String, TextEditingController> _miniC = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _projectId = widget.defaultProjectId;
    _load();
  }

  @override
  void dispose() {
    _qty.dispose();
    _desc.dispose();
    _amount.dispose();
    for (final c in _miniC.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final api = apiOf(context);
    try {
      final res = await Future.wait([
        api.get('/finance/transaction-context'),
        api.get('/transactions/vendors').catchError((_) => const []),
        api.get('/employees').catchError((_) => const []),
      ]);
      if (!mounted) return;
      final emp = res[2];
      setState(() {
        _projects = jList(jMap(res[0])['projects']);
        _vendors = jList(res[1]);
        _employees = emp is List ? jList(emp) : jList(jMap(emp)['items']);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadProducts(int vendorId) async {
    try {
      final d = jList(await apiOf(context).get('/vendors/$vendorId/products'));
      if (!mounted || _vendorId != vendorId) return;
      setState(() => _products = d);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    }
  }

  Map<String, dynamic>? get _project {
    for (final p in _projects ?? const <Map<String, dynamic>>[]) {
      if (p['id'] == _projectId) return p;
    }
    return null;
  }

  double get _amt => toNum(_amount.text);

  bool get _sourceValid => switch (_source) {
        'Vendor' => _vendorId != null && _productId != null,
        'Employee' => _employeeId != null,
        _ => _desc.text.trim().isNotEmpty,
      };

  bool get _valid => _projectId != null && _phaseId != null && _amt > 0 && _sourceValid;

  TextEditingController _mc(String k) => _miniC.putIfAbsent(k, () => TextEditingController());
  String _mv(String k) => _mc(k).text.trim();

  void _openMini(String kind) => setState(() {
        _mini = kind;
        for (final c in _miniC.values) {
          c.clear();
        }
      });

  Future<void> _saveMini() async {
    final api = apiOf(context);
    setState(() => _saving = true);
    try {
      if (_mini == 'vendor') {
        final d = jMap(await api.post('/transactions/inline/vendor', data: {
          'name': _mv('name'),
          'contact_name': _mv('contact').isEmpty ? null : _mv('contact'),
          'trade': _mv('category').isEmpty ? null : _mv('category'),
        }));
        if (!mounted) return;
        setState(() {
          _vendors = [..._vendors, {'id': d['id'], 'name': d['name']}];
          _vendorId = d['id'] as int;
          _productId = null;
          _products = [];
        });
        _loadProducts(_vendorId!);
        showToast(context, 'Vendor "${d['name']}" created & selected');
      } else if (_mini == 'product') {
        final d = jMap(await api.post('/transactions/inline/vendor/$_vendorId/product', data: {
          'name': _mv('name'),
          'unit_price': toNum(_mv('unit_price')),
          'unit': _mv('unit').isEmpty ? 'unit' : _mv('unit'),
        }));
        if (!mounted) return;
        setState(() {
          _products = [..._products, d];
          _productId = d['id'] as int;
        });
        showToast(context, 'Product "${d['name']}" added & selected');
      } else if (_mini == 'employee') {
        final rate = _mv('rate');
        final d = jMap(await api.post('/transactions/inline/employee', params: {
          'project_id': _projectId,
          'phase_id': _phaseId,
        }, data: {
          'name': _mv('name'),
          'role_title': _mv('role').isEmpty ? null : _mv('role'),
          'phone': _mv('contact').isEmpty ? null : _mv('contact'),
          'daily_wage': rate.isEmpty ? null : toNum(rate),
        }));
        if (!mounted) return;
        setState(() {
          _employees = [..._employees, d];
          _employeeId = d['id'] as int;
        });
        showToast(context, 'Employee "${d['name']}" created, assigned to phase & selected');
      }
      if (mounted) setState(() => _mini = null);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submit(bool addAnother) async {
    setState(() => _saving = true);
    try {
      final amt = _amt;
      final d = jMap(await apiOf(context).post('/transactions/expense', data: {
        'project_id': _projectId,
        'phase_id': _phaseId,
        'source_type': _source,
        'vendor_id': _vendorId,
        'product_id': _productId,
        'quantity': toNum(_qty.text) > 0 ? toNum(_qty.text) : 1,
        'employee_id': _employeeId,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'amount': amt,
        'payment_type': _ptype,
      }));
      if (!mounted) return;
      final q = d['quotation'];
      showToast(context,
          'Expense of ${inr(amt)} recorded · budget remaining ${inr(d['project_budget_remaining'])}${q is Map ? ' · Quotation ${q['quote_number']} generated' : ''}');
      widget.onSaved();
      if (addAnother) {
        setState(() {
          _amount.clear();
          _qty.text = '1';
          _desc.clear();
        });
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _miniForm(String title, List<Widget> fields) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Surface(
        color: p.toneFill(Tone.info),
        borderColor: p.toneBorder(Tone.info),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Eyebrow(title, color: p.info),
          const SizedBox(height: 10),
          for (final f in fields) ...[f, const SizedBox(height: 10)],
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(onPressed: () => setState(() => _mini = null), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving || _mv('name').isEmpty ? null : _saveMini,
              child: const Text('Save'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _miniField(String k, String label, {bool number = false}) =>
      AppTextField(controller: _mc(k), label: label, money: number, onChanged: (_) => setState(() {}));

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(message: errorText(_error), onRetry: _load);
    if (_projects == null) return const LoadingView();
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final project = _project;
    final phases = jList(project?['phases']);
    final activeProducts = _products.where((x) => x['is_active'] != false).toList();
    final balanceAfter = project != null && _amount.text.isNotEmpty
        ? ((toNum(project['budget_remaining']) - _amt) * 100).roundToDouble() / 100
        : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppDropdown<int>(
        label: 'Project',
        requiredField: true,
        hint: 'Select project',
        value: _projectId,
        items: [for (final x in _projects!) (x['id'] as int, '${x['name']}')],
        onChanged: (v) => setState(() {
          _projectId = v;
          _phaseId = null;
        }),
      ),
      kFieldGap,
      AppDropdown<int>(
        key: ValueKey('phase-$_projectId'),
        label: 'Phase',
        requiredField: true,
        hint: project != null ? 'Select phase' : 'Pick project first',
        value: _phaseId,
        items: [for (final ph in phases) (ph['id'] as int, '${ph['name']}')],
        onChanged: project == null ? null : (v) => setState(() => _phaseId = v),
      ),
      kFieldGap,
      ChoiceRow<String>(
        label: 'Expense Source *',
        value: _source,
        options: const [('Vendor', 'Vendor'), ('Employee', 'Employee'), ('Other', 'Other')],
        onChanged: (v) => setState(() {
          _source = v;
          _mini = null;
        }),
      ),
      kFieldGap,
      if (_source == 'Vendor') ...[
        AppDropdown<int>(
          key: ValueKey('vendor-$_vendorId-$_mini'),
          label: 'Vendor',
          requiredField: true,
          hint: 'Select vendor',
          value: _vendorId,
          items: [
            (_addNew, '+ Add New Vendor'),
            for (final v in _vendors) (v['id'] as int, '${v['name']}'),
          ],
          onChanged: (v) {
            if (v == null) return;
            if (v == _addNew) {
              _openMini('vendor');
            } else {
              setState(() {
                _vendorId = v;
                _productId = null;
                _products = [];
              });
              _loadProducts(v);
            }
          },
        ),
        if (_mini == 'vendor')
          _miniForm('New Vendor', [
            _miniField('name', 'Vendor name *'),
            _miniField('contact', 'Contact person / phone'),
            _miniField('category', 'Category / trade (e.g. Steel)'),
          ]),
        if (_vendorId != null) ...[
          kFieldGap,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 2,
              child: AppDropdown<int>(
                key: ValueKey('product-$_vendorId-$_productId-$_mini'),
                label: 'Product',
                requiredField: true,
                hint: 'Select product',
                value: _productId,
                items: [
                  (_addNew, '+ Add New Product'),
                  for (final x in activeProducts) (x['id'] as int, '${x['name']} — ${inr(x['unit_price'])}/${x['unit']}'),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  if (v == _addNew) {
                    _openMini('product');
                  } else {
                    setState(() => _productId = v);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: AppTextField(controller: _qty, label: 'Quantity', number: true)),
          ]),
        ],
        if (_mini == 'product')
          _miniForm('New Product', [
            _miniField('name', 'Product name *'),
            _miniField('unit_price', 'Unit price ₹ *', number: true),
            _miniField('unit', 'Unit (bag / ton / unit)'),
          ]),
      ],
      if (_source == 'Employee') ...[
        AppDropdown<int>(
          key: ValueKey('employee-$_employeeId-$_mini'),
          label: 'Employee',
          requiredField: true,
          hint: 'Select employee',
          value: _employeeId,
          items: [
            (_addNew, '+ Add New Employee'),
            for (final e in _employees)
              (
                e['id'] as int,
                '${e['name']}${(e['role_title'] ?? '').toString().isNotEmpty ? ' — ${e['role_title']}' : ''}'
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            if (v == _addNew) {
              _openMini('employee');
            } else {
              setState(() => _employeeId = v);
            }
          },
        ),
        if (_mini == 'employee')
          _miniForm('New Employee (created in Field Ops & assigned to selected phase)', [
            _miniField('name', 'Name *'),
            _miniField('role', 'Role (e.g. Mason)'),
            _miniField('contact', 'Contact'),
            _miniField('rate', 'Daily rate ₹', number: true),
          ]),
      ],
      if (_source == 'Other')
        AppTextField(
          controller: _desc,
          label: 'Description',
          requiredField: true,
          hint: 'What was this expense for?',
          onChanged: (_) => setState(() {}),
        ),
      kFieldGap,
      AppTextField(
          controller: _amount,
          label: 'Expense Amount (₹)',
          money: true,
          requiredField: true,
          onChanged: (_) => setState(() {})),
      kFieldGap,
      ChoiceRow<String>(
          label: 'Payment Type *',
          value: _ptype,
          options: [for (final t in paymentTypes) (t, t)],
          onChanged: (v) => setState(() => _ptype = v)),
      if (project != null) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.muted,
            border: Border.all(color: p.border),
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: Text.rich(TextSpan(style: tt.bodySmall, children: [
            TextSpan(text: 'Budget remaining ${inr(project['budget_remaining'])}'),
            if (_amount.text.isNotEmpty) ...[
              TextSpan(text: ' − ${inr(_amt)} = '),
              TextSpan(
                  text: inr(balanceAfter),
                  style: TextStyle(fontWeight: FontWeight.w700, color: (balanceAfter ?? 0) < 0 ? p.danger : p.success)),
            ],
            TextSpan(text: '  (project-level, read-only)', style: TextStyle(color: p.fgSubtle)),
          ])),
        ),
      ],
      const SizedBox(height: 20),
      SubmitButton(
        label: 'Save Expense',
        destructive: true,
        busy: _saving,
        onPressed: _valid ? () => _submit(false) : null,
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: p.danger, side: BorderSide(color: p.danger.withValues(alpha: 0.6))),
          onPressed: _valid && !_saving ? () => _submit(true) : null,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Save + Add Another'),
        ),
      ),
    ]);
  }
}

// ───────────────────────────────────────────────────────── invoices (utils/invoiceShare.js)

String _brand(String? b) => (b == null || b.isEmpty) ? 'Sitera' : b;

/// `invoiceText`: the plain-text invoice sent over WhatsApp / email.
String invoiceText(Map<String, dynamic> inv, String? projectName, String? brand) =>
    '${_brand(brand)} — Invoice ${inv['invoice_number']}\n'
    '${(projectName ?? '').isNotEmpty ? 'Project: $projectName\n' : ''}'
    'Amount: ${inr(inv['amount'])}\nTax: ${inr(inv['tax_amount'])}\nTotal: ${inr(inv['total'])}\n'
    'Paid: ${inr(inv['paid_amount'])}\nBalance Due: ${inr(inv['balance_due'])}\n'
    'Issue Date: ${fmtDate(inv['issue_date'])}\nDue Date: ${fmtDate(inv['due_date'])}\nStatus: ${inv['status']}'
    '${(inv['description'] ?? '').toString().isNotEmpty ? '\nNote: ${inv['description']}' : ''}';

Future<void> shareInvoiceWhatsApp(BuildContext context, Map<String, dynamic> inv, String? projectName, String? brand) =>
    openExternal(context, 'https://wa.me/?text=${Uri.encodeComponent(invoiceText(inv, projectName, brand))}');

Future<void> shareInvoiceEmail(BuildContext context, Map<String, dynamic> inv, String? projectName, String? brand) {
  final subject = Uri.encodeComponent('Invoice ${inv['invoice_number']} — ${_brand(brand)}');
  final body = Uri.encodeComponent(invoiceText(inv, projectName, brand));
  return openExternal(context, 'mailto:?subject=$subject&body=$body');
}

String _esc(dynamic s) => '${s ?? ''}'.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');

const _mimeByExt = {'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'webp': 'image/webp', 'gif': 'image/gif'};

/// The printable invoice of `printInvoice`, with the letterhead from GET /company/letterhead.
/// The logo is inlined so the file opens offline.
Future<String> buildInvoiceHtml(ApiClient api, Map<String, dynamic> inv,
    {String? projectName, String? clientName, int? projectId}) async {
  final pid = inv['project_id'] ?? projectId;
  Map<String, dynamic>? lh;
  try {
    lh = jMap(await api.get('/company/letterhead', params: pid != null ? {'project_id': pid} : null));
  } catch (_) {
    lh = null;
  }
  String logo;
  final logoUrl = lh?['logo_url'];
  if (logoUrl is String && logoUrl.isNotEmpty) {
    var src = ApiConfig.fileUrl(logoUrl);
    try {
      final rel = logoUrl.startsWith('/api/') ? logoUrl.substring(4) : logoUrl;
      final (bytes, _) = await api.download(rel);
      final ext = logoUrl.split('.').last.toLowerCase();
      src = 'data:${_mimeByExt[ext] ?? 'image/png'};base64,${base64Encode(bytes)}';
    } catch (_) {}
    logo = '<img id="inv-logo" src="${_esc(src)}" alt="${_esc(lh!['name'])}" style="max-height:64px;max-width:240px;object-fit:contain" />';
  } else {
    var src = '';
    try {
      final b = await rootBundle.load('assets/images/sitera-logo-horizontal.png');
      src = 'data:image/png;base64,${base64Encode(b.buffer.asUint8List())}';
    } catch (_) {}
    logo = '<img id="inv-logo" src="$src" alt="Sitera ERP" style="max-height:56px;max-width:240px;object-fit:contain" />';
  }
  final lines = (lh?['lines'] as List? ?? const []).map((l) => '<div>${_esc(l)}</div>').join();
  final brand = '<div>$logo${lh != null ? '<div class="issuer"><b>${_esc(lh['name'])}</b>$lines</div>' : ''}</div>';
  final desc = (inv['description'] ?? '').toString().isNotEmpty ? inv['description'] : 'Construction work — progress billing';
  final pn = (projectName ?? '').isNotEmpty ? '<div><b>Project</b>${_esc(projectName)}</div>' : '';
  final cn = (clientName ?? '').isNotEmpty ? '<div><b>Billed To</b>${_esc(clientName)}</div>' : '';
  final footName = (lh?['name'] ?? '').toString().isNotEmpty ? lh!['name'] : 'Sitera';
  return '''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Invoice ${_esc(inv['invoice_number'])}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: Arial, Helvetica, sans-serif; color: #18181b; padding: 40px; }
  .head { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 4px solid #f97316; padding-bottom: 16px; margin-bottom: 24px; }
  .brand { font-size: 26px; font-weight: 900; letter-spacing: 2px; }
  .brand span { color: #f97316; }
  .inv-no { font-size: 20px; font-weight: 700; text-align: right; }
  .status { display: inline-block; margin-top: 6px; padding: 3px 10px; border: 1px solid #18181b; font-size: 11px; letter-spacing: 1px; text-transform: uppercase; }
  .meta { display: flex; flex-wrap: wrap; gap: 16px 40px; margin-bottom: 24px; font-size: 13px; }
  .meta b { display: block; font-size: 11px; text-transform: uppercase; letter-spacing: 1px; color: #71717a; margin-bottom: 3px; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 24px; }
  th { text-align: left; font-size: 11px; text-transform: uppercase; letter-spacing: 1px; color: #71717a; border-bottom: 2px solid #18181b; padding: 8px 6px; }
  td { padding: 10px 6px; border-bottom: 1px solid #e4e4e7; font-size: 14px; }
  td.r, th.r { text-align: right; }
  .totals { margin-left: auto; width: 280px; max-width: 100%; font-size: 14px; }
  .totals div { display: flex; justify-content: space-between; padding: 6px 0; }
  .totals .grand { border-top: 2px solid #18181b; font-weight: 800; font-size: 16px; }
  .balance { color: #dc2626; font-weight: 700; }
  .issuer { margin-top: 8px; font-size: 12px; color: #52525b; white-space: pre-line; }
  .issuer b { display: block; font-size: 15px; color: #18181b; }
  .foot { margin-top: 48px; font-size: 11px; color: #71717a; border-top: 1px solid #e4e4e7; padding-top: 12px; }
  @media (max-width: 600px) { body { padding: 20px; } }
  @media print { body { padding: 20px; } }
</style></head><body>
  <div class="head">
    $brand
    <div class="inv-no">INVOICE ${_esc(inv['invoice_number'])}<br/><span class="status">${_esc(inv['status'])}</span></div>
  </div>
  <div class="meta">
    $pn
    $cn
    <div><b>Issue Date</b>${fmtDate(inv['issue_date'])}</div>
    <div><b>Due Date</b>${fmtDate(inv['due_date'])}</div>
  </div>
  <table>
    <tr><th>Description</th><th class="r">Amount</th></tr>
    <tr><td>${_esc(desc)}</td><td class="r">${inr(inv['amount'])}</td></tr>
    <tr><td>Tax</td><td class="r">${inr(inv['tax_amount'])}</td></tr>
  </table>
  <div class="totals">
    <div><span>Total</span><span>${inr(inv['total'])}</span></div>
    <div><span>Paid</span><span>${inr(inv['paid_amount'])}</span></div>
    <div class="grand"><span>Balance Due</span><span class="balance">${inr(inv['balance_due'])}</span></div>
  </div>
  <div class="foot">${_esc(footName)} · Printed ${fmtDate(DateTime.now())}</div>
</body></html>''';
}

String _invoiceFile(Map<String, dynamic> inv) => 'Invoice-${inv['invoice_number'] ?? inv['id']}.html';

/// `printInvoice`: builds the printable invoice and opens it (print from the viewer's menu).
Future<void> printInvoice(BuildContext context, Map<String, dynamic> inv,
    {String? projectName, String? clientName, int? projectId}) async {
  showToast(context, 'Preparing invoice…');
  try {
    final html = await buildInvoiceHtml(apiOf(context), inv,
        projectName: projectName, clientName: clientName, projectId: projectId);
    if (!context.mounted) return;
    await openBytes(context, utf8.encode(html), _invoiceFile(inv));
  } catch (e) {
    if (context.mounted) showToast(context, errorText(e), error: true);
  }
}

/// Shares the printable invoice as an HTML file (WhatsApp, email, Drive...).
Future<void> shareInvoiceFile(BuildContext context, Map<String, dynamic> inv,
    {String? projectName, String? clientName, int? projectId}) async {
  showToast(context, 'Preparing invoice…');
  try {
    final html = await buildInvoiceHtml(apiOf(context), inv,
        projectName: projectName, clientName: clientName, projectId: projectId);
    final dir = await getTemporaryDirectory();
    final name = _invoiceFile(inv).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}/$name');
    await file.writeAsString(html, flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/html')], subject: 'Invoice ${inv['invoice_number']}');
  } catch (e) {
    if (context.mounted) showToast(context, errorText(e), error: true);
  }
}

/// Company name from Company settings (web `user.tenant_name`).
String? _brandOf(BuildContext context) => context.read<AuthProvider>().user?.tenantName;

/// Print / share / WhatsApp / email icons for one invoice.
class InvoiceShareButtons extends StatelessWidget {
  final Map<String, dynamic> inv;
  final String? projectName;
  final String? clientName;
  final int? projectId;
  const InvoiceShareButtons({super.key, required this.inv, this.projectName, this.clientName, this.projectId});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: 'Print invoice',
        icon: Icon(Icons.print_outlined, size: 20, color: p.fgMuted),
        onPressed: () => printInvoice(context, inv, projectName: projectName, clientName: clientName, projectId: projectId),
      ),
      IconButton(
        tooltip: 'Share invoice file',
        icon: Icon(Icons.share_outlined, size: 20, color: p.fgMuted),
        onPressed: () => shareInvoiceFile(context, inv, projectName: projectName, clientName: clientName, projectId: projectId),
      ),
      IconButton(
        tooltip: 'Send via WhatsApp',
        icon: Icon(Icons.chat_outlined, size: 20, color: p.success),
        onPressed: () => shareInvoiceWhatsApp(context, inv, projectName, _brandOf(context)),
      ),
      IconButton(
        tooltip: 'Send via Email',
        icon: Icon(Icons.mail_outline, size: 20, color: p.info),
        onPressed: () => shareInvoiceEmail(context, inv, projectName, _brandOf(context)),
      ),
    ]);
  }
}

/// Figure with a state colour, right-aligned and tabular.
Widget figure(BuildContext context, String text, {Color? color, bool strong = false}) => Text(text,
    textAlign: TextAlign.right,
    style: tabular(strong ? Theme.of(context).textTheme.titleSmall : Theme.of(context).textTheme.bodyMedium)
        .copyWith(color: color, fontWeight: strong ? FontWeight.w700 : FontWeight.w600));
