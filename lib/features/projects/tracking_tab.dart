import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import 'project_common.dart';

const _flags = ['OnTrack', 'Delayed', 'Blocked'];
const _docCategories = ['Drawing', 'Contract', 'Invoice', 'Approval', 'Other'];
const _docExtensions = ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'gif', 'doc', 'docx', 'xls', 'xlsx', 'csv', 'txt', 'dwg', 'zip'];

/// Tracking tab (web ProjectDetailPage "tracking"): the progress feed (ProgressUpdateFeed.jsx with
/// ProgressUpdateFormModal.jsx) followed by the documents panel (DocumentsPanel.jsx, DocumentUploadCard.jsx,
/// DocumentListItem.jsx).
class TrackingTab extends StatefulWidget {
  final int projectId;
  final List<Map<String, dynamic>> phases;
  final bool canWrite;
  final bool isAdmin;

  /// Called after an update is posted / edited / deleted (phase % and the project's issues flag change).
  final Future<void> Function() onProjectChanged;

  const TrackingTab({
    super.key,
    required this.projectId,
    required this.phases,
    required this.canWrite,
    required this.isAdmin,
    required this.onProjectChanged,
  });

  @override
  State<TrackingTab> createState() => _TrackingTabState();
}

class _TrackingTabState extends State<TrackingTab> {
  late final ApiClient _api = context.read<ApiClient>();

  Map<String, dynamic>? _feed;
  Object? _feedError;
  List<Map<String, dynamic>>? _docs;
  Object? _docsError;

  String _docSearch = '';
  String _docCategory = 'all';

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _loadDocs();
  }

  Future<void> _loadFeed() async {
    try {
      final d = await _api.get('/projects/${widget.projectId}/updates');
      if (mounted) {
        setState(() {
          _feed = Map<String, dynamic>.from(d as Map);
          _feedError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _feedError = e);
    }
  }

  Future<void> _loadDocs() async {
    try {
      final d = await _api.get('/projects/${widget.projectId}/documents');
      if (mounted) {
        setState(() {
          _docs = asMapList(d);
          _docsError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _docsError = e);
    }
  }

  Future<void> _refresh() => Future.wait([_loadFeed(), _loadDocs()]);

  Future<void> _openUpdateForm([Map<String, dynamic>? update]) async {
    final saved = await showAppSheet<bool>(
      context,
      title: update != null ? 'Edit Progress Update' : 'Post Progress Update',
      builder: (ctx) => _UpdateForm(projectId: widget.projectId, phases: widget.phases, update: update),
    );
    if (saved == true) {
      await _loadFeed();
      await widget.onProjectChanged();
    }
  }

  Future<void> _deleteUpdate(Map<String, dynamic> u) async {
    final yes = await confirmDialog(context, title: 'Delete this progress update?', confirmLabel: 'Delete', destructive: true);
    if (!yes || !mounted) return;
    final ok = await runAction(context, () => _api.delete('/updates/${u['id']}'), success: 'Update deleted');
    if (ok) {
      await _loadFeed();
      await widget.onProjectChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = asMapList(_feed);
    return RefreshList(
      onRefresh: _refresh,
      children: [
        SectionHeader(
          'Progress Feed · ${_feed?['total'] ?? 0} updates',
          padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 8),
          trailing: widget.canWrite
              ? FilledButton.icon(
                  onPressed: () => _openUpdateForm(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Post Update'),
                )
              : null,
        ),
        if (_feed == null && _feedError == null)
          const LoadingView()
        else if (_feed == null)
          ErrorRetry(message: errorText(_feedError), onRetry: _loadFeed)
        else if (items.isEmpty)
          const EmptyState(icon: Icons.feed_outlined, title: 'No progress updates yet.')
        else
          for (final u in items)
            _UpdateCard(
              update: u,
              api: _api,
              canManage: widget.canWrite,
              onEdit: () => _openUpdateForm(u),
              onDelete: () => _deleteUpdate(u),
            ),
        const SizedBox(height: 8),
        ..._documents(context),
      ],
    );
  }

  // ───────────────────────────── documents (DocumentsPanel.jsx)

  List<Widget> _documents(BuildContext context) {
    final docs = _docs ?? const <Map<String, dynamic>>[];
    final q = _docSearch.toLowerCase();
    final filtered = docs.where((d) {
      if (_docCategory != 'all' && (d['category'] ?? 'Other') != _docCategory) return false;
      if (q.isNotEmpty && !(d['document_name'] ?? '').toString().toLowerCase().contains(q)) return false;
      return true;
    }).toList();

    return [
      SectionHeader('Documents · ${_docs?.length ?? 0}', padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 8)),
      if (widget.canWrite)
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
          child: _DocumentUploadCard(projectId: widget.projectId, api: _api, onUploaded: _loadDocs),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGutter),
        child: SearchField(hint: 'Search documents…', onChanged: (v) => setState(() => _docSearch = v)),
      ),
      FilterBar<String>(
        value: _docCategory,
        options: [('all', 'All'), for (final c in _docCategories) (c, c)],
        onChanged: (v) => setState(() => _docCategory = v),
      ),
      if (_docs == null && _docsError == null)
        const LoadingView()
      else if (_docs == null)
        ErrorRetry(message: errorText(_docsError), onRetry: _loadDocs)
      else if (filtered.isEmpty)
        const EmptyState(icon: Icons.folder_open_outlined, title: 'No documents found.')
      else
        RowGroup(children: [
          for (final d in filtered) _DocumentRow(doc: d, api: _api, isAdmin: widget.isAdmin, onChanged: _loadDocs),
        ]),
    ];
  }
}

// ───────────────────────────── progress update card (ProgressUpdateFeed.jsx)

class _UpdateCard extends StatelessWidget {
  final Map<String, dynamic> update;
  final ApiClient api;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _UpdateCard({required this.update, required this.api, required this.canManage, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final u = update;
    final atts = ((u['attachments'] as List?) ?? const []).map((e) => e.toString()).toList();
    final pct = u['percent_progress'];
    return Surface(
      margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          InitialsAvatar(u['author_name']?.toString(), size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u['author_name']?.toString() ?? 'Unknown', style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(fmtDate(u['update_date']), style: tabular(tt.bodySmall)),
            ]),
          ),
          if (canManage) ...[
            IconButton(
                tooltip: 'Edit update', icon: Icon(Icons.edit_outlined, size: 18, color: p.fgMuted), onPressed: onEdit),
            IconButton(
                tooltip: 'Delete update', icon: Icon(Icons.delete_outline, size: 18, color: p.fgMuted), onPressed: onDelete),
          ],
        ]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatusChip(u['status_flag'] as String?, dense: true),
              if (u['phase_name'] != null) TagChip(u['phase_name'].toString()),
              if (u['visible_to_client'] == false) const TagChip('Internal', icon: Icons.visibility_off_outlined),
            ]),
            const SizedBox(height: 8),
            Text(dash(u['description']), style: tt.bodyMedium?.copyWith(color: p.fgMuted)),
            if (pct != null) ...[
              const SizedBox(height: 10),
              ProgressLine(toNum(pct), useProjectTone: false),
            ],
            if (atts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in atts) _Thumb(url: a, onTap: () => openServerFile(context, api, a)),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String url;
  final VoidCallback? onTap;
  final double width;
  final double height;
  const _Thumb({required this.url, this.onTap, this.width = 112, this.height = 80});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(border: Border.all(color: p.border), color: p.muted),
        child: Image.network(
          ApiConfig.fileUrl(url),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: p.fgSubtle),
        ),
      ),
    );
  }
}

// ───────────────────────────── post / edit update (ProgressUpdateFormModal.jsx)

class _UpdateForm extends StatefulWidget {
  final int projectId;
  final List<Map<String, dynamic>> phases;
  final Map<String, dynamic>? update;
  const _UpdateForm({required this.projectId, required this.phases, this.update});

  @override
  State<_UpdateForm> createState() => _UpdateFormState();
}

class _UpdateFormState extends State<_UpdateForm> {
  final _desc = TextEditingController();
  final _pct = TextEditingController();
  int? _phaseId;
  String _flag = 'OnTrack';
  bool _visible = true;
  final List<String> _files = [];
  bool _uploading = false;
  bool _busy = false;
  String _error = '';
  late final ApiClient _api = context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    final u = widget.update;
    if (u != null) {
      _phaseId = u['phase_id'] as int?;
      _desc.text = (u['description'] ?? '').toString();
      _pct.text = inputNum(u['percent_progress']);
      _flag = (u['status_flag'] ?? 'OnTrack') as String;
      _visible = u['visible_to_client'] != false;
      _files.addAll(((u['attachments'] as List?) ?? const []).map((e) => e.toString()));
    }
  }

  @override
  void dispose() {
    _desc.dispose();
    _pct.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    setState(() => _uploading = true);
    final res = await pickAndUpload(context, _api, imagesOnly: true);
    if (!mounted) return;
    setState(() {
      if (res != null && res['url'] != null) _files.add(res['url'].toString());
      _uploading = false;
    });
  }

  Future<void> _submit() async {
    if (_desc.text.trim().isEmpty) {
      setState(() => _error = 'Description is required');
      return;
    }
    final pctText = _pct.text.trim();
    final pct = pctText.isEmpty ? null : toNum(pctText);
    if (pct != null && (pct < 0 || pct > 100)) {
      setState(() => _error = 'Percent must be 0–100');
      return;
    }
    setState(() {
      _error = '';
      _busy = true;
    });
    final payload = {
      'phase_id': _phaseId,
      'description': _desc.text.trim(),
      'percent_progress': pct == null ? null : (pct == pct.roundToDouble() ? pct.toInt() : pct),
      'status_flag': _flag,
      'attachments': _files,
      'visible_to_client': _visible,
    };
    final edit = widget.update != null;
    final ok = await runAction(context, () async {
      if (edit) {
        await _api.patch('/updates/${widget.update!['id']}', data: payload);
      } else {
        await _api.post('/projects/${widget.projectId}/updates', data: payload);
      }
    }, success: edit ? 'Update edited' : 'Update posted');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTextField(controller: _desc, label: 'Description', requiredField: true, maxLines: 4, minLines: 3),
      if (_error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(_error, style: tt.bodySmall?.copyWith(color: p.danger)),
        ),
      kFieldGap,
      AppDropdown<int?>(
        label: 'Phase',
        value: _phaseId,
        hint: 'Project-level',
        items: [
          (null, 'Project-level'),
          for (final ph in widget.phases) (ph['id'] as int, (ph['name'] ?? '').toString()),
        ],
        onChanged: (v) => setState(() => _phaseId = v),
      ),
      kFieldGap,
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: AppTextField(controller: _pct, label: '% Progress', number: true, keyboardType: TextInputType.number),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppDropdown<String>(
            label: 'Status Flag',
            value: _flag,
            items: [for (final f in _flags) (f, f)],
            onChanged: (v) => setState(() => _flag = v ?? _flag),
          ),
        ),
      ]),
      kFieldGap,
      const Eyebrow('Photos'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < _files.length; i++)
          Stack(clipBehavior: Clip.none, children: [
            _Thumb(url: _files[i], width: 84, height: 66),
            Positioned(
              top: -8,
              right: -8,
              child: Material(
                color: p.danger,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _files.removeAt(i)),
                  child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close, size: 14, color: Colors.white)),
                ),
              ),
            ),
          ]),
        InkWell(
          onTap: _uploading ? null : _addPhoto,
          child: Container(
            width: 84,
            height: 66,
            decoration: BoxDecoration(border: Border.all(color: p.inputBorder)),
            alignment: Alignment.center,
            child: _uploading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.add_photo_alternate_outlined, color: p.fgMuted),
          ),
        ),
      ]),
      if (_uploading) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Uploading…', style: tt.bodySmall)),
      const SizedBox(height: 6),
      SwitchRow(label: 'Visible to client', value: _visible, onChanged: (v) => setState(() => _visible = v)),
      const SizedBox(height: 14),
      SubmitButton(
        label: widget.update != null ? 'Save Changes' : 'Post Update',
        busy: _busy,
        onPressed: _uploading ? null : _submit,
      ),
    ]);
  }
}

// ───────────────────────────── documents (DocumentUploadCard.jsx / DocumentListItem.jsx)

class _DocumentUploadCard extends StatefulWidget {
  final int projectId;
  final ApiClient api;
  final Future<void> Function() onUploaded;
  const _DocumentUploadCard({required this.projectId, required this.api, required this.onUploaded});

  @override
  State<_DocumentUploadCard> createState() => _DocumentUploadCardState();
}

class _DocumentUploadCardState extends State<_DocumentUploadCard> {
  PickedFile? _file;
  final _name = TextEditingController();
  String _category = 'Other';
  bool _visible = true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
        _file = null;
        _name.clear();
        _category = 'Other';
        _visible = true;
      });

  Future<void> _pick() async {
    final f = await pickFile(context, extensions: _docExtensions);
    if (f == null || !mounted) return;
    setState(() {
      _file = f;
      _name.text = f.name;
    });
  }

  Future<void> _submit() async {
    final f = _file;
    if (f == null) return;
    if (f.size > 20 * 1024 * 1024) {
      showToast(context, 'File too large (max 20MB)', error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      await widget.api.postMultipart('/projects/${widget.projectId}/documents', {
        'file': await MultipartFile.fromFile(f.path, filename: f.name),
        'document_name': _name.text.trim(),
        'category': _category,
        'is_client_visible': _visible.toString(),
      });
    }, success: 'Document uploaded');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _reset();
      await widget.onUploaded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    return Surface(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Eyebrow('Upload Document'),
        const SizedBox(height: 10),
        if (_file == null)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64)),
            onPressed: _pick,
            icon: const Icon(Icons.upload_outlined),
            label: const Text('Choose file'),
          )
        else ...[
          Row(children: [
            Icon(Icons.insert_drive_file_outlined, size: 16, color: p.fgMuted),
            const SizedBox(width: 6),
            Expanded(child: Text(_file!.name, style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
            IconButton(tooltip: 'Clear file', icon: const Icon(Icons.close, size: 18), onPressed: _busy ? null : _reset),
          ]),
          const SizedBox(height: 6),
          AppTextField(controller: _name, label: 'Document Name'),
          kFieldGap,
          AppDropdown<String>(
            label: 'Category',
            value: _category,
            items: [for (final c in _docCategories) (c, c)],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          SwitchRow(label: 'Visible to client', value: _visible, onChanged: (v) => setState(() => _visible = v)),
          const SizedBox(height: 8),
          SubmitButton(label: _busy ? 'Uploading…' : 'Upload', busy: _busy, onPressed: _submit),
        ],
      ]),
    );
  }
}

IconData _docIcon(String? type) {
  final t = (type ?? '').toLowerCase();
  if (t == 'pdf') return Icons.picture_as_pdf_outlined;
  if (['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(t)) return Icons.image_outlined;
  if (['xls', 'xlsx', 'csv'].contains(t)) return Icons.table_chart_outlined;
  return Icons.insert_drive_file_outlined;
}

/// Web fmtSize: "1.2 MB" / "34 KB", empty when unknown.
String _docSize(dynamic b) {
  if (b == null) return '';
  final n = toNum(b);
  return n > 1048576 ? '${(n / 1048576).toStringAsFixed(1)} MB' : '${(n / 1024).round().clamp(1, 1 << 30)} KB';
}

class _DocumentRow extends StatelessWidget {
  final Map<String, dynamic> doc;
  final ApiClient api;
  final bool isAdmin;
  final Future<void> Function() onChanged;
  const _DocumentRow({required this.doc, required this.api, required this.isAdmin, required this.onChanged});

  Future<void> _edit(BuildContext context) async {
    final saved = await showAppSheet<bool>(context, title: 'Edit Document', builder: (ctx) => _DocumentEditForm(doc: doc, api: api));
    if (saved == true) await onChanged();
  }

  Future<void> _delete(BuildContext context) async {
    final yes = await confirmDialog(context, title: 'Delete "${doc['document_name']}"?', confirmLabel: 'Delete', destructive: true);
    if (!yes || !context.mounted) return;
    final ok = await runAction(context, () => api.delete('/documents/${doc['id']}'), success: 'Document deleted');
    if (ok) await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final meta = [doc['uploader_name'], fmtDate(doc['uploaded_at']), _docSize(doc['file_size'])]
        .where((e) => e != null && e.toString().isNotEmpty)
        .join(' · ');
    return RowTile(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      leading: Icon(_docIcon(doc['file_type'] as String?), color: p.accentText),
      title: dash(doc['document_name']),
      onTap: () => openServerFile(context, api, (doc['file_url'] ?? '').toString()),
      subtitleWidget: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(meta, style: tabular(Theme.of(context).textTheme.bodySmall), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          StatusChip(null, label: (doc['category'] ?? 'Other').toString(), dense: true),
          if (doc['is_client_visible'] == false) const StatusChip(null, label: 'Internal', dense: true),
        ]),
      ]),
      trailing: isAdmin
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  tooltip: 'Edit document', icon: Icon(Icons.edit_outlined, size: 18, color: p.fgMuted), onPressed: () => _edit(context)),
              IconButton(
                  tooltip: 'Delete document',
                  icon: Icon(Icons.delete_outline, size: 18, color: p.fgMuted),
                  onPressed: () => _delete(context)),
            ])
          : null,
    );
  }
}

class _DocumentEditForm extends StatefulWidget {
  final Map<String, dynamic> doc;
  final ApiClient api;
  const _DocumentEditForm({required this.doc, required this.api});

  @override
  State<_DocumentEditForm> createState() => _DocumentEditFormState();
}

class _DocumentEditFormState extends State<_DocumentEditForm> {
  late final _name = TextEditingController(text: (widget.doc['document_name'] ?? '').toString());
  late String _category = (widget.doc['category'] ?? 'Other').toString();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final ok = await runAction(
        context,
        () => widget.api.patch('/documents/${widget.doc['id']}',
            data: {'document_name': _name.text.trim(), 'category': _category}),
        success: 'Document updated');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(controller: _name, label: 'Document Name'),
        kFieldGap,
        AppDropdown<String>(
          label: 'Category',
          value: _category,
          items: [for (final c in _docCategories) (c, c)],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: 20),
        SubmitButton(label: 'Save', busy: _busy, onPressed: _save),
      ]);
}
