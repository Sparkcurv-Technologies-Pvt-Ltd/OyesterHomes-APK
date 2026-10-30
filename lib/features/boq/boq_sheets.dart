import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../org/org_provider.dart';
import 'boq_api.dart';

// The web BOQTab.jsx dialogs (LineDialog, ImportDialog, ApplyTemplateDialog, SaveAsTemplateDialog) and the
// BOQLibraryPage.jsx ones (NewTemplateDialog, ApplyToProjectDialog, SaveProjectDialog) as bottom sheets.

/// `₹1,25,000` — the web BOQ's `inr(n)` (no decimals).
String boqInr(dynamic v) => inr(toNum(v).roundToDouble());

/// `₹5,200.00` — the web BOQ's `inr(n, 2)` (rates).
String boqInr2(dynamic v) => inr(v, forceDecimals: true);

String? _nonNegative(String? v) {
  final n = toNumOrNull(v);
  if (v != null && v.trim().isNotEmpty && (n == null || n < 0)) return 'Enter 0 or more';
  return null;
}

// ───────────────────────────────────────────────────────── line

/// Add / edit a BOQ line. Pops `true` when saved or deleted.
Future<bool?> showBoqLineSheet(BuildContext context,
    {required BoqEndpoints ep, Map<String, dynamic>? line, required List<String> sections}) {
  final isEdit = line?['id'] != null;
  return showAppSheet<bool>(context,
      title: isEdit ? 'Edit BOQ line' : 'Add BOQ line',
      builder: (ctx) => _LineForm(ep: ep, line: isEdit ? line : null, sections: sections));
}

class _LineForm extends StatefulWidget {
  final BoqEndpoints ep;
  final Map<String, dynamic>? line;
  final List<String> sections;
  const _LineForm({required this.ep, this.line, required this.sections});

  @override
  State<_LineForm> createState() => _LineFormState();
}

class _LineFormState extends State<_LineForm> {
  final _form = GlobalKey<FormState>();
  late final _section = TextEditingController(text: widget.line?['section']?.toString() ?? '');
  late final _code = TextEditingController(text: widget.line?['item_code']?.toString() ?? '');
  late final _desc = TextEditingController(text: widget.line?['description']?.toString() ?? '');
  late final _unit = TextEditingController(text: widget.line?['unit']?.toString() ?? '');
  late final _qty = TextEditingController(text: inputNum(widget.line?['quantity']));
  late final _rate = TextEditingController(text: inputNum(widget.line?['rate']));
  bool _busy = false;
  bool _deleting = false;

  @override
  void dispose() {
    for (final c in [_section, _code, _desc, _unit, _qty, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _orNull(TextEditingController c) => c.text.isEmpty ? null : c.text;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final api = context.read<ApiClient>();
    final isEdit = widget.line != null;
    final body = {
      'section': _orNull(_section),
      'item_code': _orNull(_code),
      'description': _desc.text,
      'unit': _orNull(_unit),
      'quantity': toNum(_qty.text),
      'rate': toNum(_rate.text),
      'notes': widget.line?['notes'],
    };
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      if (isEdit) {
        await boqSend(api, 'PATCH', widget.ep.item(widget.line!['id']), data: body);
      } else {
        await boqSend(api, 'POST', widget.ep.add, data: body);
      }
    }, success: isEdit ? 'BOQ line updated' : 'BOQ line added');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final line = widget.line!;
    final yes = await confirmDialog(context,
        title: 'Delete line', message: 'Delete "${line['description']}"?', confirmLabel: 'Delete', destructive: true);
    if (!yes || !mounted) return;
    final api = context.read<ApiClient>();
    setState(() => _deleting = true);
    final ok = await runAction(context, () => boqSend(api, 'DELETE', widget.ep.item(line['id'])), success: 'Line deleted');
    if (!mounted) return;
    setState(() => _deleting = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final amount = toNum(_qty.text) * toNum(_rate.text);
    final others = widget.sections;
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(controller: _section, label: 'Section', hint: 'e.g. Civil', onChanged: (_) => setState(() {})),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in others)
              ActionChip(
                label: Text(s),
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: _section.text == s ? p.accent : p.border),
                onPressed: () => setState(() => _section.text = s),
              ),
          ]),
        ],
        kFieldGap,
        AppTextField(controller: _code, label: 'Item code', capitalization: TextCapitalization.characters),
        kFieldGap,
        AppTextField(controller: _desc, label: 'Description', requiredField: true),
        kFieldGap,
        AppTextField(controller: _unit, label: 'Unit', hint: 'sqft', capitalization: TextCapitalization.none),
        kFieldGap,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: AppTextField(
                  controller: _qty, label: 'Quantity', number: true, validator: _nonNegative, onChanged: (_) => setState(() {}))),
          const SizedBox(width: 12),
          Expanded(
              child: AppTextField(
                  controller: _rate, label: 'Rate (₹)', number: true, validator: _nonNegative, onChanged: (_) => setState(() {}))),
        ]),
        kFieldGap,
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: p.muted, borderRadius: BorderRadius.circular(Radii.control)),
          child: Row(children: [
            const Expanded(child: Eyebrow('Amount')),
            Text(boqInr2(amount), style: tabular(tt.titleSmall).copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 18),
        SubmitButton(label: 'Save line', busy: _busy, onPressed: _deleting ? null : _save),
        if (widget.line != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: TextButton.icon(
              onPressed: _busy || _deleting ? null : _delete,
              style: TextButton.styleFrom(foregroundColor: p.danger),
              icon: _deleting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete line'),
            ),
          ),
        ],
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────── import

/// Import an Excel BOQ into a project / template ([withName] false) or as a new library template ([withName] true).
/// [onSaved] gets the response. A project / template import stays open to show the result, as on the web.
Future<void> showBoqImportSheet(BuildContext context,
    {required String url, required bool hasLines, bool withName = false, required void Function(Map<String, dynamic>) onSaved}) {
  return showAppSheet<void>(context,
      title: withName ? 'New template from Excel' : 'Import BOQ from Excel',
      builder: (ctx) => _ImportForm(url: url, hasLines: hasLines, withName: withName, onSaved: onSaved));
}

class _ImportForm extends StatefulWidget {
  final String url;
  final bool hasLines;
  final bool withName;
  final void Function(Map<String, dynamic>) onSaved;
  const _ImportForm({required this.url, required this.hasLines, required this.withName, required this.onSaved});

  @override
  State<_ImportForm> createState() => _ImportFormState();
}

class _ImportFormState extends State<_ImportForm> {
  final _name = TextEditingController();
  PickedFile? _file;
  String _mode = 'append';
  bool _busy = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final f = await pickFile(context, allowCamera: false, extensions: const ['xlsx', 'xlsm']);
    if (f != null && mounted) setState(() => _file = f);
  }

  Future<void> _upload() async {
    if (_file == null) {
      showToast(context, 'Choose the BOQ Excel file first', error: true);
      return;
    }
    if (widget.withName && _name.text.trim().isEmpty) {
      showToast(context, 'Give the template a name', error: true);
      return;
    }
    final api = context.read<ApiClient>();
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final data = Map<String, dynamic>.from(await boqUpload(api, widget.url, _file!.path, _file!.name,
          widget.withName ? {'name': _name.text.trim()} : {'mode': _mode}) as Map);
      if (!mounted) return;
      setState(() => _result = data);
      showToast(context, '${data['imported']} BOQ lines imported');
      widget.onSaved(data);
      // A new library template opens its own screen next (web: close the dialog and navigate).
      if (widget.withName) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _result = e is BoqApiException && e.errors.isNotEmpty ? {'imported': 0, 'errors': e.errors} : null);
      showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final errors = (_result?['errors'] as List?) ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text.rich(
        TextSpan(style: tt.bodySmall, children: const [
          TextSpan(text: 'The first sheet is read. It needs a header row with '),
          TextSpan(text: 'Description', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' and '),
          TextSpan(text: 'Qty', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' or '),
          TextSpan(text: 'Rate', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(
              text: '; Section, Item code and Unit are picked up when present. Rows with only a description become '
                  'section headings. An exported BOQ imports back as it is.'),
        ]),
      ),
      const SizedBox(height: 16),
      if (widget.withName) ...[
        AppTextField(controller: _name, label: 'Template name', hint: 'e.g. Villa G+1 — standard'),
        kFieldGap,
      ],
      OutlinedButton.icon(
        onPressed: _busy ? null : _pick,
        icon: const Icon(Icons.attach_file, size: 18),
        label: Text(_file == null ? 'Choose Excel file (.xlsx)' : _file!.name, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
      if (widget.hasLines && !widget.withName) ...[
        const SizedBox(height: 14),
        ChoiceRow<String>(
          value: _mode,
          options: const [('append', 'Add to current lines'), ('replace', 'Replace current lines')],
          onChanged: (v) => setState(() => _mode = v),
        ),
      ],
      if (_result != null) ...[
        const SizedBox(height: 14),
        Surface(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: '${_result!['imported']}', style: tabular(tt.titleSmall).copyWith(fontWeight: FontWeight.w700)),
              TextSpan(text: ' lines imported', style: tt.bodyMedium),
            ])),
            for (final e in errors)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('Row ${e is Map ? e['row'] : ''}: ${e is Map ? e['message'] : e}',
                    style: tt.bodySmall?.copyWith(color: p.danger)),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 18),
      SubmitButton(label: 'Import', icon: Icons.upload_outlined, busy: _busy, onPressed: _upload),
    ]);
  }
}

// ───────────────────────────────────────────────────────── apply a template to this project

/// Project → copy a library template's lines into this project's BOQ. Pops `true` when applied.
/// [openLibrary] opens the BOQ library when there are no templates yet.
Future<bool?> showApplyTemplateSheet(BuildContext context,
    {required int projectId, required bool hasLines, required VoidCallback openLibrary}) {
  return showAppSheet<bool>(context,
      title: 'Apply a BOQ template',
      subtitle: "The template's lines are copied into this project. Editing the template later does not change this project.",
      builder: (ctx) => _ApplyTemplateForm(projectId: projectId, hasLines: hasLines, openLibrary: openLibrary));
}

class _ApplyTemplateForm extends StatefulWidget {
  final int projectId;
  final bool hasLines;
  final VoidCallback openLibrary;
  const _ApplyTemplateForm({required this.projectId, required this.hasLines, required this.openLibrary});

  @override
  State<_ApplyTemplateForm> createState() => _ApplyTemplateFormState();
}

class _ApplyTemplateFormState extends State<_ApplyTemplateForm> {
  List<Map<String, dynamic>>? _templates;
  Object? _error;
  int? _picked;
  String _mode = 'append';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await context.read<ApiClient>().get('/boq-templates');
      if (mounted) setState(() => _templates = (d as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _apply() async {
    if (_picked == null) {
      showToast(context, 'Pick a template', error: true);
      return;
    }
    final api = context.read<ApiClient>();
    setState(() => _busy = true);
    try {
      final data = await boqSend(api, 'POST', '/projects/${widget.projectId}/boq/apply-template',
          data: {'template_id': _picked, 'mode': _mode});
      if (!mounted) return;
      showToast(context,
          '${data['applied']} lines from ${data['template']} ${_mode == 'replace' ? 'replaced the BOQ' : 'added'}');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    if (_error != null) return ErrorRetry(message: errorText(_error), onRetry: _load);
    final list = _templates;
    if (list == null) return const LoadingView();
    final picked = list.where((t) => t['id'] == _picked).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (list.isEmpty)
        EmptyState(
          icon: Icons.library_books_outlined,
          title: 'No templates yet.',
          action: TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.openLibrary();
            },
            child: const Text('Open the BOQ library →'),
          ),
        )
      else
        for (final t in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Surface(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              borderColor: t['id'] == _picked ? p.accent : null,
              color: t['id'] == _picked ? p.accent.withValues(alpha: 0.08) : null,
              onTap: () => setState(() => _picked = t['id'] as int),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Radio<int>(
                  value: t['id'] as int,
                  groupValue: _picked,
                  onChanged: (v) => setState(() => _picked = v),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${t['name']}', style: tt.titleSmall),
                      const SizedBox(height: 2),
                      Text('${t['lines']} lines · ${t['sections']} sections · ${boqInr(t['value'])}',
                          style: tabular(tt.bodySmall)),
                      if ((t['description'] ?? '').toString().isNotEmpty)
                        Text('${t['description']}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: p.fgSubtle)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
      if (widget.hasLines) ...[
        const SizedBox(height: 8),
        ChoiceRow<String>(
          value: _mode,
          options: const [('append', 'Add to current lines'), ('replace', 'Replace current lines')],
          onChanged: (v) => setState(() => _mode = v),
        ),
      ],
      const SizedBox(height: 18),
      SubmitButton(
        label: picked != null ? 'Apply ${picked['lines']} lines' : 'Apply',
        icon: Icons.library_add_outlined,
        busy: _busy,
        onPressed: picked == null ? null : _apply,
      ),
    ]);
  }
}

// ───────────────────────────────────────────────────────── save a project's BOQ as a template

/// Saves a project's BOQ to the library. With [projectId] null (library page) the sheet asks for the project
/// first ("Save a project as template"). Pops the response `{id, lines}` when saved.
Future<Map<String, dynamic>?> showSaveAsTemplateSheet(BuildContext context, {int? projectId}) {
  return showAppSheet<Map<String, dynamic>>(context,
      title: projectId == null ? 'Save a project as template' : 'Save BOQ as a template',
      subtitle: projectId == null
          ? 'Pick the project whose BOQ should become a template.'
          : 'Keeps a copy of these lines in Setup → BOQ library, ready for the next project.',
      builder: (ctx) => _SaveAsTemplateForm(projectId: projectId));
}

class _SaveAsTemplateForm extends StatefulWidget {
  final int? projectId;
  const _SaveAsTemplateForm({this.projectId});

  @override
  State<_SaveAsTemplateForm> createState() => _SaveAsTemplateFormState();
}

class _SaveAsTemplateFormState extends State<_SaveAsTemplateForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  late int? _projectId = widget.projectId;
  List<Map<String, dynamic>>? _projects;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.projectId == null) _loadProjects();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    try {
      _projects = await loadProjectOptions(context);
    } catch (e) {
      _projects = [];
      if (mounted) showToast(context, errorText(e), error: true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final api = context.read<ApiClient>();
    setState(() => _busy = true);
    try {
      final data = Map<String, dynamic>.from(await boqSend(api, 'POST', '/projects/$_projectId/boq/save-as-template',
          data: {'name': _name.text, 'description': _description.text.isEmpty ? null : _description.text}) as Map);
      if (!mounted) return;
      showToast(context, 'Saved ${data['lines']} lines to the BOQ library');
      Navigator.pop(context, data);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickProject = widget.projectId == null;
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (pickProject) ...[
          if (_projects == null)
            const LoadingView()
          else
            AppDropdown<int>(
              label: 'Project',
              hint: 'Choose a project',
              requiredField: true,
              value: _projectId,
              items: [for (final p in _projects!) (p['id'] as int, '${p['name']}')],
              onChanged: (v) => setState(() => _projectId = v),
            ),
          kFieldGap,
        ],
        AppTextField(controller: _name, label: 'Template name', requiredField: true),
        kFieldGap,
        AppTextField(controller: _description, label: 'Description'),
        const SizedBox(height: 18),
        SubmitButton(
            label: 'Save template',
            icon: Icons.save_outlined,
            busy: _busy,
            onPressed: _projectId == null ? null : _save),
      ]),
    );
  }
}

/// The web's `useProjectOptions`: GET /projects (limit 200, company / branch filter) → items.
Future<List<Map<String, dynamic>>> loadProjectOptions(BuildContext context) async {
  final org = context.read<OrgProvider>();
  final d = await context.read<ApiClient>().get('/projects', params: {'limit': 200, ...org.orgParams});
  final items = d is Map ? (d['items'] as List? ?? const []) : (d as List? ?? const []);
  return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}
