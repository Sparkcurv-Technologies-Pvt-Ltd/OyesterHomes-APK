import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../shell/routes.dart';
import 'boq_api.dart';
import 'boq_library_screen.dart';
import 'boq_sheets.dart';

/// The web's `BOQEditor` (BOQTab.jsx): one editor for a project's BOQ ([isProject]) and for a BOQ library
/// template. Both APIs return `{items, sections, totals, can_edit}`; editing is gated by the server's
/// `can_edit` (project: Admin or the project's manager; template: Admin / ProjectManager).
///
/// Embedded (no Scaffold): scrolls itself with pull-to-refresh. [header] is drawn above the figures
/// (the template screen's name / description) and gets the loaded data.
class BoqEditor extends StatefulWidget {
  final bool isProject;
  final int id;
  final Widget Function(BuildContext context, Map<String, dynamic> data, Future<void> Function() reload)? header;
  const BoqEditor({super.key, required this.isProject, required this.id, this.header});

  @override
  State<BoqEditor> createState() => _BoqEditorState();
}

class _Group {
  final String name;
  final List<Map<String, dynamic>> items = [];
  double budget = 0;
  double actual = 0;
  _Group(this.name);
}

class _BoqEditorState extends State<BoqEditor> {
  String? _downloading;

  BoqEndpoints get _ep => BoqEndpoints(widget.isProject, widget.id);

  Future<Map<String, dynamic>> _load() async =>
      Map<String, dynamic>.from(await context.read<ApiClient>().get(_ep.get) as Map);

  List<_Group> _groups(Map<String, dynamic> data) {
    final out = <_Group>[];
    for (final raw in (data['items'] as List? ?? const [])) {
      final it = Map<String, dynamic>.from(raw as Map);
      final name = (it['section'] ?? '').toString().isEmpty ? 'General' : it['section'].toString();
      var g = out.where((x) => x.name == name).firstOrNull;
      if (g == null) {
        g = _Group(name);
        out.add(g);
      }
      g.items.add(it);
      g.budget += toNum(it['amount']);
      g.actual += toNum(it['actual']);
    }
    return out;
  }

  Future<void> _download(String key, String path, String name) async {
    setState(() => _downloading = key);
    await downloadAndOpen(context, context.read<ApiClient>(), path, fallbackName: name);
    if (mounted) setState(() => _downloading = null);
  }

  Future<void> _editLine(Map<String, dynamic>? line, List<_Group> groups, Future<void> Function() reload) async {
    final saved = await showBoqLineSheet(context, ep: _ep, line: line, sections: groups.map((g) => g.name).toList());
    if (saved == true) await reload();
  }

  Future<void> _apply(bool hasLines, Future<void> Function() reload) async {
    final ok = await showApplyTemplateSheet(context,
        projectId: widget.id,
        hasLines: hasLines,
        openLibrary: () => push(context, const AppScaffold(title: 'BOQ library', body: BoqLibraryScreen())));
    if (ok == true) await reload();
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<Map<String, dynamic>>(
      load: _load,
      builder: (context, data, reload) => _body(context, data, reload),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> data, Future<void> Function() reload) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final isProject = widget.isProject;
    final t = Map<String, dynamic>.from(data['totals'] as Map? ?? const {});
    final canEdit = data['can_edit'] == true;
    final groups = _groups(data);
    final lines = toInt(t['items']);
    final budget = toNum(t['budget']);
    final actual = toNum(t['actual']);
    final variance = toNum(t['variance']);
    final usedPct = budget != 0 ? (actual / budget * 100).round() : 0;
    final unlinked = toNum(t['unlinked_actual']);

    Widget action(String key, IconData icon, String label, VoidCallback? onTap, {bool primary = false}) {
      final busy = _downloading == key;
      final iconW = busy
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 16);
      final onPressed = _downloading != null && busy ? null : onTap;
      return primary
          ? FilledButton.icon(onPressed: onPressed, icon: iconW, label: Text(label))
          : OutlinedButton.icon(onPressed: onPressed, icon: iconW, label: Text(label));
    }

    return RefreshList(
      onRefresh: reload,
      children: [
        if (widget.header != null) widget.header!(context, data, reload),
        const SizedBox(height: 4),
        KpiGrid(children: [
          KpiTile(label: 'BOQ value', value: boqInr(budget)),
          if (isProject) ...[
            KpiTile(label: 'Actual cost', value: boqInr(actual)),
            KpiTile(label: 'Balance', value: boqInr(variance), tone: variance < 0 ? Tone.danger : null),
            KpiTile(label: 'Used', value: '$usedPct%', tone: usedPct > 100 ? Tone.danger : Tone.accent),
          ] else ...[
            KpiTile(label: 'Lines', value: '$lines'),
            KpiTile(label: 'Sections', value: '${groups.length}'),
          ],
        ]),
        SectionHeader('$lines lines · ${groups.length} sections'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kGutter),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            if (canEdit) action('line', Icons.add, 'Line', () => _editLine(null, groups, reload), primary: true),
            if (isProject && canEdit) action('apply', Icons.library_books_outlined, 'Apply template', () => _apply(lines > 0, reload)),
            if (canEdit)
              action('import', Icons.upload_file_outlined, 'Import Excel',
                  () => showBoqImportSheet(context, url: _ep.import, hasLines: lines > 0, onSaved: (_) => reload())),
            if (isProject && canEdit && lines > 0)
              action('save', Icons.save_outlined, 'Save as template', () async {
                await showSaveAsTemplateSheet(context, projectId: widget.id);
              }),
            if (isProject) action('pdf', Icons.print_outlined, 'Print', lines == 0 ? null : () => _download('pdf', _ep.pdf, 'boq.pdf')),
            action('export', Icons.file_download_outlined, 'Export Excel',
                lines == 0 ? null : () => _download('export', _ep.export, 'boq.xlsx')),
            action('blank', Icons.download_outlined, 'Blank sheet',
                () => _download('blank', '/boq/excel-template', 'boq-template.xlsx')),
          ]),
        ),
        const SizedBox(height: 12),
        if (lines == 0)
          Surface(
            margin: const EdgeInsets.symmetric(horizontal: kGutter),
            padding: EdgeInsets.zero,
            child: EmptyState(
              icon: Icons.grid_on_outlined,
              title: isProject ? 'No BOQ yet' : 'This template is empty',
              message: !canEdit
                  ? 'The project manager has not added the BOQ yet.'
                  : isProject
                      ? 'Apply a template from the BOQ library, import your BOQ sheet, or add lines one by one.'
                      : 'Import a BOQ sheet or add lines one by one. Every project can then apply it.',
              action: canEdit && isProject
                  ? FilledButton.icon(
                      onPressed: () => _apply(false, reload),
                      icon: const Icon(Icons.library_books_outlined, size: 18),
                      label: const Text('Apply a template'))
                  : null,
            ),
          )
        else ...[
          for (final g in groups) ...[
            RowGroup(
              header: _SectionRow(group: g, isProject: isProject),
              children: [
                for (final it in g.items)
                  _LineRow(
                    item: it,
                    isProject: isProject,
                    onTap: canEdit ? () => _editLine(it, groups, reload) : null,
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          RowGroup(children: [
            TotalBand('Grand total', boqInr(budget)),
            if (isProject) TotalBand('Actual cost', boqInr(actual), valueColor: actual > budget ? p.danger : null),
          ]),
        ],
        if (isProject && unlinked > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 0),
            child: Text(
                '${boqInr(unlinked)} of project cost is not tagged to a BOQ line yet, so it is not in the Actual column.',
                style: tt.bodySmall),
          ),
        if (canEdit && lines > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 0),
            child: Text('Tap a line to edit or delete it.', style: tt.bodySmall?.copyWith(color: p.fgSubtle)),
          ),
      ],
    );
  }
}

class _SectionRow extends StatelessWidget {
  final _Group group;
  final bool isProject;
  const _SectionRow({required this.group, required this.isProject});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    return Container(
      color: p.muted,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Expanded(child: Text(group.name, style: tt.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(boqInr(group.budget), style: tabular(tt.titleSmall).copyWith(fontWeight: FontWeight.w700)),
          if (isProject)
            Text('Actual ${boqInr(group.actual)}', style: tabular(tt.bodySmall).copyWith(color: p.fgMuted)),
        ]),
      ]),
    );
  }
}

class _LineRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isProject;
  final VoidCallback? onTap;
  const _LineRow({required this.item, required this.isProject, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final code = (item['item_code'] ?? '').toString();
    final unit = (item['unit'] ?? '').toString();
    final usedRaw = item['used_pct'];
    final pct = toNum(usedRaw);
    final over = pct > 100;
    final act = toNum(item['actual']);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(
                    TextSpan(children: [
                      if (code.isNotEmpty)
                        WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(padding: const EdgeInsets.only(right: 6), child: CodeTag(code))),
                      TextSpan(text: '${item['description']}'),
                    ]),
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text('${qty(item['quantity'])}${unit.isEmpty ? '' : ' $unit'} × ${boqInr2(item['rate'])}',
                      style: tabular(tt.bodySmall)),
                ]),
              ),
              const SizedBox(width: 12),
              Text(boqInr(item['amount']),
                  textAlign: TextAlign.right, style: tabular(tt.titleSmall).copyWith(fontWeight: FontWeight.w700)),
            ]),
            if (isProject) ...[
              const SizedBox(height: 8),
              Row(children: [
                Text('Actual ${act != 0 ? boqInr(act) : '—'}',
                    style: tabular(tt.bodySmall).copyWith(color: over ? p.danger : null)),
                const SizedBox(width: 10),
                Expanded(child: LevelBar(pct / 100, tone: over ? Tone.danger : null)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text(usedRaw == null ? '—' : '${pct.round()}%',
                      textAlign: TextAlign.right, style: tabular(tt.bodySmall)),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
