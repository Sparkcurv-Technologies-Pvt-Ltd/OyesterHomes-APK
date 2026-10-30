import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import 'boq_editor.dart';

/// Setup → BOQ library → one template (web BOQTemplatePage.jsx): name / description (editable by Admin and
/// Project Managers) plus the same line editor a project BOQ uses. Pushed screen.
class BoqTemplateScreen extends StatelessWidget {
  final int templateId;
  const BoqTemplateScreen({super.key, required this.templateId});

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().user?.role;
    final canEdit = const ['Admin', 'ProjectManager'].contains(role);
    return AppScaffold(
      title: 'BOQ template',
      subtitle: 'BOQ library',
      body: BoqEditor(
        isProject: false,
        id: templateId,
        header: (context, data, reload) => _TemplateMeta(templateId: templateId, data: data, canEdit: canEdit, reload: reload),
      ),
    );
  }
}

class _TemplateMeta extends StatefulWidget {
  final int templateId;
  final Map<String, dynamic> data;
  final bool canEdit;
  final Future<void> Function() reload;
  const _TemplateMeta({required this.templateId, required this.data, required this.canEdit, required this.reload});

  @override
  State<_TemplateMeta> createState() => _TemplateMetaState();
}

class _TemplateMetaState extends State<_TemplateMeta> {
  late final _name = TextEditingController(text: _savedName);
  late final _description = TextEditingController(text: _savedDescription);
  bool _busy = false;

  String get _savedName => (widget.data['name'] ?? '').toString();
  String get _savedDescription => (widget.data['description'] ?? '').toString();

  @override
  void didUpdateWidget(covariant _TemplateMeta old) {
    super.didUpdateWidget(old);
    if (old.data['name'] != widget.data['name'] || old.data['description'] != widget.data['description']) {
      _name.text = _savedName;
      _description.text = _savedDescription;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _dirty => _name.text != _savedName || _description.text != _savedDescription;

  Future<void> _save() async {
    final api = context.read<ApiClient>();
    setState(() => _busy = true);
    final ok = await runAction(
        context,
        () => api.patch('/boq-templates/${widget.templateId}',
            data: {'name': _name.text, 'description': _description.text.isEmpty ? null : _description.text}),
        success: 'Template saved');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) await widget.reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Eyebrow('BOQ template', color: p.accentText),
        const SizedBox(height: 8),
        if (widget.canEdit) ...[
          AppTextField(controller: _name, label: 'Name', onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          AppTextField(controller: _description, label: 'Description', onChanged: (_) => setState(() {})),
          if (_dirty) ...[
            const SizedBox(height: 10),
            SubmitButton(
              label: 'Save',
              icon: Icons.save_outlined,
              busy: _busy,
              onPressed: _name.text.trim().isEmpty ? null : _save,
            ),
          ],
        ] else ...[
          Text(_savedName, style: tt.headlineSmall),
          if (_savedDescription.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_savedDescription, style: tt.bodyMedium?.copyWith(color: p.fgMuted)),
          ],
        ],
      ]),
    );
  }
}
