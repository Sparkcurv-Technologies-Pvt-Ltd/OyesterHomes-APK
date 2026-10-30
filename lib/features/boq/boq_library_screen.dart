import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../shell/routes.dart';
import 'boq_api.dart';
import 'boq_sheets.dart';
import 'boq_template_screen.dart';

/// Setup → BOQ library (web BOQLibraryPage.jsx): BOQs set up once and applied to any project.
/// Admin and Project Managers keep the library (new, import, save a project, samples, apply, delete);
/// everyone with BOQ access can open and export a template. Top-level page: no AppBar (the shell draws it).
class BoqLibraryScreen extends StatefulWidget {
  const BoqLibraryScreen({super.key});

  @override
  State<BoqLibraryScreen> createState() => _BoqLibraryScreenState();
}

class _LibraryData {
  final List<Map<String, dynamic>> templates;
  final List<Map<String, dynamic>> samples;
  const _LibraryData(this.templates, this.samples);
}

class _BoqLibraryScreenState extends State<BoqLibraryScreen> {
  final _view = GlobalKey<AsyncViewState<_LibraryData>>();
  final Set<int> _open = {};
  final Set<String> _adding = {};
  int? _exporting;

  List<Map<String, dynamic>> _maps(dynamic d) =>
      (d as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<_LibraryData> _load() async {
    final api = context.read<ApiClient>();
    final templates = _maps(await api.get('/boq-templates'));
    var samples = <Map<String, dynamic>>[];
    try {
      samples = _maps(await api.get('/boq-templates/samples'));
    } catch (_) {
      // Samples are a convenience; the library still shows without them.
    }
    return _LibraryData(templates, samples);
  }

  Future<void> _reload() async => _view.currentState?.reload();

  Future<void> _openTemplate(int id) async {
    await push(context, BoqTemplateScreen(templateId: id));
    await _reload();
  }

  Future<void> _addSample(Map<String, dynamic> s) async {
    final api = context.read<ApiClient>();
    final key = s['key'].toString();
    setState(() => _adding.add(key));
    try {
      final data = await boqSend(api, 'POST', '/boq-templates/samples/$key');
      if (mounted) showToast(context, '${s['name']} added — ${data['lines']} lines');
      await _reload();
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _adding.remove(key));
    }
  }

  Future<void> _remove(Map<String, dynamic> t) async {
    final yes = await confirmDialog(context,
        title: 'Delete template',
        message: 'Delete the template "${t['name']}"? Projects that already used it keep their lines.',
        confirmLabel: 'Delete',
        destructive: true);
    if (!yes || !mounted) return;
    final api = context.read<ApiClient>();
    final ok = await runAction(context, () => api.delete('/boq-templates/${t['id']}'), success: 'Template deleted');
    if (ok) await _reload();
  }

  Future<void> _export(Map<String, dynamic> t) async {
    setState(() => _exporting = t['id'] as int);
    await downloadAndOpen(context, context.read<ApiClient>(), '/boq-templates/${t['id']}/export',
        fallbackName: 'boq-template.xlsx');
    if (mounted) setState(() => _exporting = null);
  }

  Future<void> _newTemplate() async {
    final id = await showAppSheet<int>(context,
        title: 'New BOQ template',
        subtitle: 'Name it, then add lines or import a sheet on the next screen.',
        builder: (ctx) => const _NewTemplateForm());
    if (id == null || !mounted) return;
    await _reload();
    if (mounted) await _openTemplate(id);
  }

  Future<void> _importNew() async {
    int? created;
    await showBoqImportSheet(context,
        url: '/boq-templates/import', hasLines: false, withName: true, onSaved: (d) => created = d['id'] as int?);
    if (created == null || !mounted) return;
    await _reload();
    if (mounted) await _openTemplate(created!);
  }

  Future<void> _saveProject() async {
    final d = await showSaveAsTemplateSheet(context);
    if (d == null || !mounted) return;
    await _reload();
    if (mounted) await _openTemplate(d['id'] as int);
  }

  Future<void> _applyTo(Map<String, dynamic> t) async {
    final openProject = await showAppSheet<int>(context,
        title: 'Apply ${t['name']}',
        subtitle: '${t['lines']} lines are copied into the project. Later edits to the template do not change it.',
        builder: (ctx) => _ApplyToProjectForm(template: t));
    if (openProject != null && mounted) await openWebPath(context, '/admin/projects/$openProject?tab=boq');
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().user?.role;
    final canEdit = const ['Admin', 'ProjectManager'].contains(role);
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: _newTemplate, icon: const Icon(Icons.add), label: const Text('New template'))
          : null,
      body: AsyncView<_LibraryData>(
        key: _view,
        load: _load,
        builder: (context, data, reload) => _body(context, data, reload, canEdit),
      ),
    );
  }

  Widget _body(BuildContext context, _LibraryData data, Future<void> Function() reload, bool canEdit) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final names = data.templates.map((t) => t['name'].toString().toLowerCase()).toSet();
    final missing = data.samples.where((s) => !names.contains(s['name'].toString().toLowerCase())).toList();
    return RefreshList(
      onRefresh: reload,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Eyebrow('Setup', color: p.accentText),
            const SizedBox(height: 4),
            Text('BOQ library', style: tt.headlineMedium),
            const SizedBox(height: 8),
            Text(
                'Set a BOQ up once — sections, items, units, quantities and rates — then apply it to any project. '
                'Applying copies the lines, so each project can still be adjusted on its own.',
                style: tt.bodySmall),
            if (canEdit) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 4, children: [
                OutlinedButton.icon(
                    onPressed: _importNew,
                    icon: const Icon(Icons.upload_outlined, size: 16),
                    label: const Text('Import Excel')),
                OutlinedButton.icon(
                    onPressed: _saveProject,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Save a project as template')),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        if (canEdit && missing.isNotEmpty) ...[
          Surface(
            margin: const EdgeInsets.symmetric(horizontal: kGutter),
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.library_books_outlined, size: 18, color: p.accentText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(TextSpan(style: tt.bodyMedium, children: [
                    TextSpan(
                        text: 'Sample BOQ${missing.length > 1 ? 's' : ''} ready to use: ',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: missing.map((s) => '${s['name']} (${s['lines']} lines)').join(', ')),
                  ])),
                ),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final s in missing)
                  OutlinedButton.icon(
                    onPressed: _adding.contains(s['key'].toString()) ? null : () => _addSample(s),
                    icon: _adding.contains(s['key'].toString())
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add, size: 16),
                    label: Text('Add ${s['name']}'),
                  ),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        if (data.templates.isEmpty)
          const Surface(
            margin: EdgeInsets.symmetric(horizontal: kGutter),
            padding: EdgeInsets.zero,
            child: EmptyState(
              icon: Icons.library_books_outlined,
              title: 'No BOQ templates yet',
              message: "Create one from scratch, import your standard BOQ sheet, or save a project's BOQ.",
            ),
          )
        else
          for (final t in data.templates) ...[
            _templateCard(context, t, canEdit),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _templateCard(BuildContext context, Map<String, dynamic> t, bool canEdit) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final id = t['id'] as int;
    final open = _open.contains(id);
    final lines = toInt(t['lines']);
    final sections = (t['section_names'] as List? ?? const []).map((e) => e.toString()).toList();
    final meta = [
      '$lines lines · ${t['sections']} sections · ${boqInr(t['value'])}',
      if (t['updated_at'] != null) 'updated ${fmtDate(t['updated_at'])}',
      if (t['created_by'] != null) 'by ${t['created_by']}',
    ].join(' · ');
    return Surface(
      margin: const EdgeInsets.symmetric(horizontal: kGutter),
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => _openTemplate(id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 14, 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconButton(
                tooltip: 'Show sections',
                onPressed: () => setState(() {
                  if (!_open.remove(id)) _open.add(id);
                }),
                icon: Icon(open ? Icons.expand_more : Icons.chevron_right, color: p.fgSubtle),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${t['name']}', style: tt.titleMedium),
                    if ((t['description'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('${t['description']}', style: tt.bodySmall?.copyWith(color: p.fgMuted)),
                    ],
                    const SizedBox(height: 4),
                    Text(meta, style: tabular(tt.bodySmall)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(52, 4, 14, 8),
            child: sections.isEmpty
                ? Text('No lines yet.', style: tt.bodySmall?.copyWith(color: p.fgSubtle))
                : Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final s in sections) StatusChip(null, label: s, tone: Tone.neutral, dense: true),
                  ]),
          ),
        Divider(height: 1, color: p.border),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(children: [
            if (canEdit)
              TextButton.icon(
                  onPressed: () => _openTemplate(id),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit')),
            TextButton.icon(
              onPressed: lines == 0 || _exporting == id ? null : () => _export(t),
              icon: _exporting == id
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_download_outlined, size: 16),
              label: const Text('Export'),
            ),
            const Spacer(),
            if (canEdit)
              IconButton(
                tooltip: 'Delete',
                onPressed: () => _remove(t),
                icon: Icon(Icons.delete_outline, size: 20, color: p.fgSubtle),
              ),
            if (canEdit)
              FilledButton.icon(
                onPressed: lines == 0 ? null : () => _applyTo(t),
                icon: const Icon(Icons.library_add_outlined, size: 16),
                label: const Text('Apply'),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _NewTemplateForm extends StatefulWidget {
  const _NewTemplateForm();

  @override
  State<_NewTemplateForm> createState() => _NewTemplateFormState();
}

class _NewTemplateFormState extends State<_NewTemplateForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final api = context.read<ApiClient>();
    setState(() => _busy = true);
    try {
      final data = await api.post('/boq-templates',
          data: {'name': _name.text, 'description': _description.text.isEmpty ? null : _description.text});
      if (mounted) Navigator.pop(context, data['id'] as int);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppTextField(controller: _name, label: 'Name', hint: 'e.g. Villa G+1 — standard', requiredField: true),
          kFieldGap,
          AppTextField(controller: _description, label: 'Description'),
          const SizedBox(height: 18),
          SubmitButton(label: 'Create', icon: Icons.add, busy: _busy, onPressed: _save),
        ]),
      );
}

/// Library → pick a project and copy the template's lines into its BOQ.
class _ApplyToProjectForm extends StatefulWidget {
  final Map<String, dynamic> template;
  const _ApplyToProjectForm({required this.template});

  @override
  State<_ApplyToProjectForm> createState() => _ApplyToProjectFormState();
}

class _ApplyToProjectFormState extends State<_ApplyToProjectForm> {
  List<Map<String, dynamic>>? _projects;
  int? _projectId;
  String _mode = 'append';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadProjects();
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

  Future<void> _apply() async {
    final api = context.read<ApiClient>();
    setState(() => _busy = true);
    try {
      final data = await boqSend(api, 'POST', '/projects/$_projectId/boq/apply-template',
          data: {'template_id': widget.template['id'], 'mode': _mode});
      if (!mounted) return;
      showToast(context, "${data['applied']} lines added to the project's BOQ");
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_projects == null) return const LoadingView();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppDropdown<int>(
        label: 'Project',
        hint: 'Choose a project',
        value: _projectId,
        items: [
          for (final p in _projects!)
            (
              p['id'] as int,
              '${p['name']}${(p['branch_name'] ?? '').toString().isNotEmpty ? ' · ${p['branch_name']}' : ''}'
            ),
        ],
        onChanged: (v) => setState(() => _projectId = v),
      ),
      const SizedBox(height: 14),
      ChoiceRow<String>(
        value: _mode,
        options: const [('append', 'Add to its current lines'), ('replace', 'Replace its current lines')],
        onChanged: (v) => setState(() => _mode = v),
      ),
      const SizedBox(height: 18),
      SubmitButton(
          label: 'Apply', icon: Icons.library_add_outlined, busy: _busy, onPressed: _projectId == null ? null : _apply),
      if (_projectId != null) ...[
        const SizedBox(height: 6),
        SizedBox(
          height: 48,
          child: TextButton(
            // Pops the project id; the library opens that project's BOQ tab.
            onPressed: () => Navigator.pop(context, _projectId),
            child: const Text('Open project BOQ →'),
          ),
        ),
      ],
    ]);
  }
}
