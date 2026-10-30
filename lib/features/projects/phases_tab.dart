import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import 'project_common.dart';

const _phaseStatuses = ['NotStarted', 'InProgress', 'Completed', 'Delayed', 'Blocked'];

/// Web PHASE_COLORS: NotStarted slate, InProgress amber, Completed emerald, Delayed amber, Blocked red.
Tone _phaseTone(String? s) => switch (s) {
      'InProgress' => Tone.accent,
      'Completed' => Tone.success,
      'Delayed' => Tone.warning,
      'Blocked' => Tone.danger,
      _ => Tone.neutral,
    };

/// Phases tab (web PhaseTimeline.jsx + PhaseCrew.jsx + PhaseFormModal.jsx). The web's horizontal timeline
/// becomes a vertical one: a numbered rail with one card per phase.
class PhasesTab extends StatelessWidget {
  final int projectId;
  final List<Map<String, dynamic>> phases;
  final bool canWrite;

  /// phase_id → (approved change-order amount, count), as the web's `coByPhase`.
  final Map<int, (double, int)> coByPhase;
  final Future<void> Function() onChanged;

  const PhasesTab({
    super.key,
    required this.projectId,
    required this.phases,
    required this.canWrite,
    required this.coByPhase,
    required this.onChanged,
  });

  int get _nextOrder => phases.fold<int>(0, (m, p) => toInt(p['sequence_order']) > m ? toInt(p['sequence_order']) : m) + 1;

  Future<void> _openForm(BuildContext context, Map<String, dynamic>? phase) async {
    final changed = await showPhaseForm(context, projectId: projectId, phase: phase, nextOrder: _nextOrder);
    if (changed == true) await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshList(
      onRefresh: onChanged,
      children: [
        SectionHeader(
          'Phase Timeline · ${phases.length} phases',
          padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 8),
          trailing: canWrite
              ? FilledButton.icon(
                  onPressed: () => _openForm(context, null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Phase'),
                )
              : null,
        ),
        if (phases.isEmpty)
          const EmptyState(icon: Icons.timeline_outlined, title: 'No phases defined yet.')
        else
          for (var i = 0; i < phases.length; i++)
            _PhaseStep(
              phase: phases[i],
              last: i == phases.length - 1,
              canWrite: canWrite,
              co: coByPhase[phases[i]['id']],
              onEdit: () => _openForm(context, phases[i]),
            ),
      ],
    );
  }
}

class _PhaseStep extends StatelessWidget {
  final Map<String, dynamic> phase;
  final bool last;
  final bool canWrite;
  final (double, int)? co;
  final VoidCallback onEdit;
  const _PhaseStep({required this.phase, required this.last, required this.canWrite, required this.co, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final ph = phase;
    final status = ph['status'] as String?;
    final tone = _phaseTone(status);
    final pct = toNum(ph['percent_complete']);
    final done = status == 'Completed';
    final notes = asMapList(ph['notes'] ?? const []);
    final markerColor = tone == Tone.neutral ? p.fgSubtle : p.tone(tone);

    return Stack(children: [
      // The rail: a line down to the next phase, behind the numbered square.
      if (!last) Positioned(left: 27.5, top: 32, bottom: 0, child: Container(width: 1, color: p.border)),
      Positioned(
            left: 12,
            top: 0,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tone == Tone.neutral ? p.muted : markerColor,
                border: Border.all(color: markerColor, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: done
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : Text('${toInt(ph['sequence_order'])}',
                      style: tabular(tt.titleSmall).copyWith(
                          color: tone == Tone.neutral ? p.fgMuted : Colors.white, fontWeight: FontWeight.w700)),
            ),
      ),
      Padding(
          padding: const EdgeInsets.only(left: 56),
          child: Surface(
            margin: const EdgeInsets.only(right: kGutter, bottom: 12),
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(dash(ph['name']), style: tt.titleMedium)),
                if (canWrite)
                  IconButton(
                    tooltip: 'Edit phase',
                    icon: Icon(Icons.edit_outlined, size: 18, color: p.fgMuted),
                    onPressed: onEdit,
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  StatusChip(status, tone: tone, dense: true),
                  const SizedBox(height: 6),
                  Text('${fmtDate(ph['planned_start'])} → ${fmtDate(ph['planned_end'])}', style: tabular(tt.bodySmall)),
                  const SizedBox(height: 8),
                  ProgressLine(pct,
                      tone: status == 'Delayed' ? Tone.danger : (done ? Tone.success : null), useProjectTone: false),
                  if (co != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.toneFill(Tone.accent),
                        border: Border.all(color: p.toneBorder(Tone.accent)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '+ ${inr(co!.$1)} · ${co!.$2} variation${co!.$2 != 1 ? 's' : ''}'.toUpperCase(),
                        style: tabular(TextStyle(
                            fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: p.accentText)),
                      ),
                    ),
                  ],
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final n in notes)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                        decoration: BoxDecoration(
                          color: p.muted,
                          border: Border(left: BorderSide(color: p.info, width: 2)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(dash(n['text']), style: tt.bodySmall?.copyWith(color: p.fg)),
                          const SizedBox(height: 2),
                          Text('${fmtDate(n['date'])}${n['by'] != null ? ' · ${n['by']}' : ''}',
                              style: tt.bodySmall?.copyWith(fontSize: 11)),
                        ]),
                      ),
                  ],
                  if (canWrite) _PhaseCrew(key: ValueKey(ph['id']), phaseId: toInt(ph['id'])),
                ]),
              ),
            ]),
          ),
      ),
    ]);
  }
}

/// Web PhaseCrew.jsx: who of the payroll crew works this phase; assign / remove.
class _PhaseCrew extends StatefulWidget {
  final int phaseId;
  const _PhaseCrew({super.key, required this.phaseId});

  @override
  State<_PhaseCrew> createState() => _PhaseCrewState();
}

class _PhaseCrewState extends State<_PhaseCrew> {
  List<Map<String, dynamic>> _crew = [];
  bool _busy = false;
  late final ApiClient _api = context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.get('/phases/${widget.phaseId}/employees');
      if (mounted) setState(() => _crew = asMapList(d));
    } catch (_) {
      // The crew line simply stays empty.
    }
  }

  Future<void> _assign() async {
    final picked = await showAppSheet<int>(
      context,
      title: 'Assign to phase',
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.5,
        child: AsyncView<List<Map<String, dynamic>>>(
          load: () async => asMapList(await _api.get('/phases/${widget.phaseId}/available-employees')),
          builder: (ctx, list, _) => list.isEmpty
              ? const EmptyState(icon: Icons.groups_outlined, title: 'No available employees — all assigned')
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: ctx.pal.border),
                  itemBuilder: (_, i) {
                    final e = list[i];
                    return RowTile(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      leading: InitialsAvatar(e['name']?.toString()),
                      title: dash(e['name']),
                      subtitle: e['role_title']?.toString(),
                      onTap: () => Navigator.pop(ctx, toInt(e['id'])),
                    );
                  },
                ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    await runAction(context, () => _api.post('/phases/${widget.phaseId}/employees', data: {'employee_id': picked}),
        success: 'Employee assigned to phase');
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove(int empId) async {
    setState(() => _busy = true);
    await runAction(context, () => _api.delete('/phases/${widget.phaseId}/employees/$empId'), success: 'Removed from phase');
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.groups_outlined, size: 13, color: p.fgMuted),
          const SizedBox(width: 5),
          Eyebrow('Crew · ${_crew.length}'),
          if (_busy) ...[const SizedBox(width: 8), const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6))],
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in _crew)
            TagChip(
              '${c['name']}${c['role_title'] != null ? ' · ${c['role_title']}' : ''}',
              onRemove: _busy ? null : () => _remove(toInt(c['employee_id'])),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 14),
            label: const Text('Assign'),
            onPressed: _busy ? null : _assign,
          ),
        ]),
      ]),
    );
  }
}

/// Web PhaseFormModal.jsx. Returns true when something was saved or removed.
Future<bool?> showPhaseForm(BuildContext context,
    {required int projectId, Map<String, dynamic>? phase, required int nextOrder}) {
  return showAppSheet<bool>(
    context,
    title: phase != null ? 'Edit Phase' : 'Add Phase',
    builder: (ctx) => _PhaseForm(projectId: projectId, phase: phase, nextOrder: nextOrder),
  );
}

class _PhaseForm extends StatefulWidget {
  final int projectId;
  final Map<String, dynamic>? phase;
  final int nextOrder;
  const _PhaseForm({required this.projectId, this.phase, required this.nextOrder});

  @override
  State<_PhaseForm> createState() => _PhaseFormState();
}

class _PhaseFormState extends State<_PhaseForm> {
  final _name = TextEditingController();
  final _order = TextEditingController();
  final _pct = TextEditingController();
  final _desc = TextEditingController();
  String? _start;
  String? _end;
  String _status = 'NotStarted';
  Map<String, String> _errors = {};
  bool _busy = false;
  late final ApiClient _api = context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    final ph = widget.phase;
    if (ph != null) {
      _name.text = (ph['name'] ?? '').toString();
      _order.text = inputNum(ph['sequence_order']);
      _start = ph['planned_start'] as String?;
      _end = ph['planned_end'] as String?;
      _status = (ph['status'] ?? 'NotStarted') as String;
      _pct.text = inputNum(ph['percent_complete'] ?? 0);
    } else {
      _order.text = '${widget.nextOrder}';
      _pct.text = '0';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _order.dispose();
    _pct.dispose();
    _desc.dispose();
    super.dispose();
  }

  bool _validate() {
    final e = <String, String>{};
    if (_name.text.trim().isEmpty) e['name'] = 'Phase name is required';
    if (_order.text.trim().isEmpty || toNum(_order.text) < 1) e['sequence_order'] = 'Order must be ≥ 1';
    final pct = toNum(_pct.text);
    if (pct < 0 || pct > 100) e['percent_complete'] = 'Must be 0–100';
    if ((_start ?? '').isNotEmpty && (_end ?? '').isNotEmpty && _end!.compareTo(_start!) < 0) {
      e['planned_end'] = 'End must be after start';
    }
    setState(() => _errors = e);
    return e.isEmpty;
  }

  num _intish(String s) {
    final v = toNum(s);
    return v == v.roundToDouble() ? v.toInt() : v;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    final desc = _desc.text.trim();
    final payload = {
      'name': _name.text.trim(),
      'sequence_order': _intish(_order.text),
      'planned_start': (_start ?? '').isEmpty ? null : _start,
      'planned_end': (_end ?? '').isEmpty ? null : _end,
      'status': _status,
      'percent_complete': _intish(_pct.text),
      if (desc.isNotEmpty) 'description': desc,
    };
    setState(() => _busy = true);
    final edit = widget.phase != null;
    final ok = await runAction(context, () async {
      if (edit) {
        await _api.put('/phases/${widget.phase!['id']}', data: payload);
      } else {
        await _api.post('/projects/${widget.projectId}/phases', data: payload);
      }
    }, success: edit ? 'Phase updated' : 'Phase added');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  Future<void> _remove() async {
    final yes = await confirmDialog(context,
        title: 'Delete this phase?', message: dash(widget.phase!['name']), confirmLabel: 'Delete', destructive: true);
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    final ok = await runAction(context, () => _api.delete('/phases/${widget.phase!['id']}'), success: 'Phase removed');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    Widget err(String k) => _errors[k] == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(_errors[k]!, style: tt.bodySmall?.copyWith(color: p.danger)),
          );
    final completed = _status == 'Completed';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 2,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppTextField(controller: _name, label: 'Phase Name', requiredField: true),
            err('name'),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppTextField(controller: _order, label: 'Order', requiredField: true, number: true, keyboardType: TextInputType.number),
            err('sequence_order'),
          ]),
        ),
      ]),
      kFieldGap,
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: DateField(label: 'Planned Start', value: _start, onChanged: (v) => setState(() => _start = v))),
        const SizedBox(width: 10),
        Expanded(child: DateField(label: 'Planned End', value: _end, onChanged: (v) => setState(() => _end = v))),
      ]),
      err('planned_end'),
      kFieldGap,
      AppDropdown<String>(
        label: 'Status',
        value: _status,
        items: [for (final s in _phaseStatuses) (s, s)],
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _status = v;
            if (v == 'Completed') _pct.text = '100';
          });
        },
      ),
      kFieldGap,
      AppTextField(
        controller: _pct,
        label: '% Complete',
        number: true,
        keyboardType: TextInputType.number,
        enabled: !completed,
        helper: completed ? 'Auto-set to 100% for completed phases' : null,
      ),
      err('percent_complete'),
      kFieldGap,
      AppTextField(
        controller: _desc,
        label: 'Description',
        maxLines: 3,
        hint: "Add a description note — it will be recorded below the phase with today's date and alerted",
      ),
      const SizedBox(height: 20),
      SubmitButton(label: widget.phase != null ? 'Save' : 'Add Phase', busy: _busy, onPressed: _submit),
      if (widget.phase != null) ...[
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: p.danger, side: BorderSide(color: p.danger.withValues(alpha: 0.5))),
            onPressed: _busy ? null : _remove,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
          ),
        ),
      ],
    ]);
  }
}
