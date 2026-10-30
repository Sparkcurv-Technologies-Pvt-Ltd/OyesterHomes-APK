import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import 'labour_shared.dart';

// Ports of EmployeeFormModal.jsx, EmployeeCategoryFormModal.jsx and CategoryManagerModal.jsx as bottom sheets.

const _wageTypes = <(String, String)>[('daily', 'Daily'), ('monthly', 'Monthly'), ('piece_rate', 'Piece Rate')];
const _newCategory = '__new';

/// Add (or edit, when [employee] is given) a field worker. With [projectId] the worker is created on that
/// project (POST /projects/{id}/employees), otherwise org-wide (POST /employees). True when saved.
Future<bool> showEmployeeForm(BuildContext context, {int? projectId, Map<String, dynamic>? employee}) async {
  final r = await showAppSheet<bool>(
    context,
    title: employee != null ? 'Edit Employee' : 'Add Employee',
    subtitle: 'Field workers for this project — separate from portal users.',
    builder: (ctx) => _EmployeeForm(projectId: projectId, employee: employee),
  );
  return r == true;
}

class _EmployeeForm extends StatefulWidget {
  final int? projectId;
  final Map<String, dynamic>? employee;
  const _EmployeeForm({this.projectId, this.employee});

  @override
  State<_EmployeeForm> createState() => _EmployeeFormState();
}

class _EmployeeFormState extends State<_EmployeeForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _wage = TextEditingController();
  String? _categoryId;
  String _wageType = 'daily';
  String? _joining;
  List<Map<String, dynamic>> _categories = [];
  Map<String, dynamic>? _picked; // the category just created here
  int _catKey = 0;
  bool _saving = false;
  String? _error;

  Map<String, dynamic>? get _emp => widget.employee;

  @override
  void initState() {
    super.initState();
    final e = _emp;
    if (e != null) {
      _name.text = (e['name'] ?? '').toString();
      _categoryId = e['category_id']?.toString();
      _phone.text = (e['phone'] ?? '').toString();
      _wageType = (e['wage_type'] ?? 'daily').toString();
      _wage.text = inputNum(e['daily_wage']);
      _joining = e['joining_date'] as String?;
    }
    _loadCategories();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _wage.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final d = await context.read<ApiClient>().get('/employee-categories');
      if (mounted) setState(() => _categories = asMaps(d));
    } catch (_) {
      // The picker simply stays empty; "Add Category" still works.
    }
  }

  bool get _canEditWage => _emp == null || (context.read<AuthProvider>().user?.roleIn(['Admin', 'Accountant']) ?? false);

  List<Map<String, dynamic>> get _catOptions => [
        ..._categories,
        if (_picked != null && !_categories.any((c) => c['id'] == _picked!['id'])) _picked!,
      ];

  void _usePicked(Map<String, dynamic> cat) {
    setState(() {
      _picked = cat;
      _categoryId = cat['id'].toString();
      if (_emp == null && cat['default_wage_type'] != null) _wageType = cat['default_wage_type'];
      _catKey++;
    });
  }

  Future<void> _onCategory(String? v) async {
    if (v == _newCategory) {
      setState(() => _catKey++); // put the picker back on the current category
      final cat = await showCategoryForm(context);
      if (cat != null && mounted) {
        _usePicked(cat);
        _loadCategories();
      }
      return;
    }
    if (v == null) return;
    final cat = _catOptions.where((c) => c['id'].toString() == v).firstOrNull;
    setState(() {
      _categoryId = v;
      if (_emp == null && cat?['default_wage_type'] != null) _wageType = cat!['default_wage_type'];
    });
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Employee name is required');
      showToast(context, 'Employee name is required', error: true);
      return;
    }
    final canEditWage = _canEditWage;
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'category_id': _categoryId != null ? int.parse(_categoryId!) : null,
      'phone': _phone.text.isEmpty ? null : _phone.text,
      'joining_date': (_joining ?? '').isEmpty ? null : _joining,
      if (canEditWage) 'wage_type': _wageType,
      if (canEditWage) 'daily_wage': _wage.text.trim().isEmpty ? null : toNum(_wage.text),
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      if (_emp != null) {
        await api.patch('/employees/${_emp!['id']}', data: payload);
      } else if (widget.projectId != null) {
        await api.post('/projects/${widget.projectId}/employees', data: payload);
      } else {
        await api.post('/employees', data: payload);
      }
      if (!mounted) return;
      showToast(context, _emp != null ? 'Employee updated' : 'Employee added');
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
    final canEditWage = _canEditWage;
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTextField(controller: _name, label: 'Name', hint: 'e.g. Ramesh Kumar', requiredField: true, capitalization: TextCapitalization.words),
      kFieldGap,
      AppDropdown<String>(
        key: ValueKey('cat$_catKey'),
        label: 'Category',
        hint: 'Select trade',
        value: _categoryId,
        items: [
          for (final c in _catOptions) (c['id'].toString(), (c['name'] ?? '').toString()),
          (_newCategory, '+ Add Category'),
        ],
        onChanged: _onCategory,
      ),
      kFieldGap,
      AppTextField(
        controller: _phone,
        label: 'Phone',
        hint: 'e.g. 98765 43210',
        keyboardType: TextInputType.phone,
      ),
      kFieldGap,
      DateField(label: 'Joining Date', value: _joining, onChanged: (v) => setState(() => _joining = v)),
      kFieldGap,
      if (canEditWage) ...[
        AppDropdown<String>(
          label: 'Wage Type',
          value: _wageType,
          items: _wageTypes,
          onChanged: (v) => setState(() => _wageType = v ?? 'daily'),
        ),
        kFieldGap,
        AppTextField(controller: _wage, label: 'Daily Wage (₹)', hint: 'e.g. 800', money: true),
      ] else
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(8)),
          child: Text(
            'Wage: ${_wage.text.isNotEmpty ? '₹${_wage.text}' : '—'} / $_wageType — only Admin or Accountant can edit wage fields.',
            style: tt.bodySmall,
          ),
        ),
      const SizedBox(height: 20),
      SheetError(_error),
      SubmitButton(label: _emp != null ? 'Save Changes' : 'Add Employee', busy: _saving, onPressed: _submit),
    ]);
  }
}

// ───────────────────────────────────────────────────────── add category

/// EmployeeCategoryFormModal: returns the created (or already existing / switched back on) category.
Future<Map<String, dynamic>?> showCategoryForm(BuildContext context) => showAppSheet<Map<String, dynamic>>(
      context,
      title: 'Add Category',
      subtitle: 'Labour trades are shared across all projects.',
      builder: (ctx) => const _CategoryForm(),
    );

class _CategoryForm extends StatefulWidget {
  const _CategoryForm();

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  final _name = TextEditingController();
  String _wageType = 'daily';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Category name is required');
      showToast(context, 'Category name is required', error: true);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await api.dio.post('/employee-categories', data: {'name': _name.text.trim(), 'default_wage_type': _wageType});
      final data = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      showToast(
          context,
          data['reactivated'] == true
              ? 'Category "${data['name']}" was switched off — it is back on and selected'
              : 'Category "${data['name']}" added');
      Navigator.pop(context, data);
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map ? (e.response!.data as Map)['detail'] : null;
      if (e.response?.statusCode == 409 && detail is Map && detail['category'] is Map) {
        // It already exists: just pick it.
        showToast(context, (detail['message'] ?? '').toString());
        Navigator.pop(context, Map<String, dynamic>.from(detail['category'] as Map));
        return;
      }
      setState(() {
        _saving = false;
        _error = dioDetail(e);
      });
      showToast(context, dioDetail(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(
          controller: _name,
          label: 'Name',
          hint: 'e.g. Welder',
          requiredField: true,
          autofocus: true,
          capitalization: TextCapitalization.words,
        ),
        kFieldGap,
        AppDropdown<String>(
          label: 'Default Wage Type',
          value: _wageType,
          items: _wageTypes,
          onChanged: (v) => setState(() => _wageType = v ?? 'daily'),
        ),
        const SizedBox(height: 20),
        SheetError(_error),
        SubmitButton(label: 'Add Category', busy: _saving, onPressed: _submit),
      ]);
}

// ───────────────────────────────────────────────────────── category manager

/// CategoryManagerModal: rename, switch off / on, or add worker trade categories (Admin / Accountant).
Future<void> showCategoryManager(BuildContext context) => showAppSheet<void>(
      context,
      title: 'Employee Categories',
      subtitle: 'Rename, deactivate or add worker trade categories.',
      builder: (ctx) => const _CategoryManager(),
    );

class _CategoryManager extends StatefulWidget {
  const _CategoryManager();

  @override
  State<_CategoryManager> createState() => _CategoryManagerState();
}

class _CategoryManagerState extends State<_CategoryManager> {
  List<Map<String, dynamic>>? _cats;
  final Map<int, TextEditingController> _edits = {};
  final _newName = TextEditingController();
  final Set<int> _busy = {};
  bool _adding = false;
  String? _error;
  String? _flash;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _edits.values) {
      c.dispose();
    }
    _newName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<ApiClient>().get('/employee-categories', params: {'include_inactive': true});
      if (!mounted) return;
      final cats = asMaps(d);
      setState(() {
        _cats = cats;
        for (final c in cats) {
          final id = c['id'] as int;
          (_edits[id] ??= TextEditingController()).text = (c['name'] ?? '').toString();
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  void _say(String msg, {bool error = false}) {
    setState(() {
      _error = error ? msg : null;
      _flash = error ? null : msg;
    });
    showToast(context, msg, error: error);
  }

  Future<void> _rename(Map<String, dynamic> cat) async {
    final id = cat['id'] as int;
    final name = _edits[id]!.text.trim();
    if (name.isEmpty || name == cat['name']) return;
    setState(() => _busy.add(id));
    try {
      await context.read<ApiClient>().patch('/employee-categories/$id', data: {'name': name});
      _say('Category updated');
      await _load();
    } catch (e) {
      _say(errorText(e), error: true);
    }
    if (mounted) setState(() => _busy.remove(id));
  }

  Future<void> _toggle(Map<String, dynamic> cat) async {
    final id = cat['id'] as int;
    final active = cat['is_active'] != false;
    setState(() => _busy.add(id));
    try {
      await context.read<ApiClient>().patch('/employee-categories/$id', data: {'is_active': !active});
      _say(active ? 'Category deactivated' : 'Category activated');
      await _load();
    } catch (e) {
      _say(errorText(e), error: true);
    }
    if (mounted) setState(() => _busy.remove(id));
  }

  Future<void> _add() async {
    if (_newName.text.trim().isEmpty) return;
    setState(() => _adding = true);
    try {
      final res = await context.read<ApiClient>().dio.post('/employee-categories', data: {'name': _newName.text.trim()});
      final data = Map<String, dynamic>.from(res.data as Map);
      _newName.clear();
      _say(data['reactivated'] == true ? '"${data['name']}" was switched off — it is back on' : 'Category added');
    } on DioException catch (e) {
      _say(dioDetail(e), error: true);
    }
    await _load();
    if (mounted) setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final cats = _cats;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetError(_error),
      if (_flash != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(_flash!, style: tt.bodySmall?.copyWith(color: p.success, fontWeight: FontWeight.w600)),
        ),
      if (cats == null && _error == null) const LoadingView(),
      if (cats != null && cats.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text('No categories yet.', style: tt.bodySmall)),
      for (final cat in cats ?? const <Map<String, dynamic>>[])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _categoryRow(cat, p),
        ),
      Divider(color: p.border, height: 24),
      Row(children: [
        Expanded(
          child: AppTextField(
            controller: _newName,
            label: 'New category name…',
            capitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _adding ? null : _add,
            icon: _adding
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add, size: 18),
            label: const Text('Add'),
          ),
        ),
      ]),
    ]);
  }

  Widget _categoryRow(Map<String, dynamic> cat, AppPalette p) {
    final id = cat['id'] as int;
    final active = cat['is_active'] != false;
    final ctl = _edits[id]!;
    final busy = _busy.contains(id);
    return Opacity(
      opacity: active ? 1 : 0.6,
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: ctl,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            inputFormatters: [LengthLimitingTextInputFormatter(80)],
            decoration: const InputDecoration(isDense: false),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton.filled(
            tooltip: 'Save name',
            onPressed: busy || ctl.text.trim() == cat['name'] ? null : () => _rename(cat),
            icon: const Icon(Icons.check, size: 20),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          height: 48,
          child: OutlinedButton(
            onPressed: busy ? null : () => _toggle(cat),
            child: Text(active ? 'Disable' : 'Enable'),
          ),
        ),
      ]),
    );
  }
}
