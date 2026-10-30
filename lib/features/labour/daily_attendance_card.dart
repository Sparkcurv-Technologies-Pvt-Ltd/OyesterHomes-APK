import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import 'labour_shared.dart';

/// DailyAttendanceCard.jsx: one worker's day. Big P / ½ / A / L choices; once marked at work, the site engineer
/// can type what they did (the web's VoiceInput: here a plain field, the keyboard's mic does dictation) and,
/// when the project has contractor work, put the worker on a contract (NMR).
class DailyAttendanceCard extends StatefulWidget {
  final Map<String, dynamic> employee;
  final String? status;
  final Map<String, dynamic>? record;
  final List<Map<String, dynamic>> contracts;
  final Future<void> Function(Map<String, dynamic> employee, String status) onMark;
  final Future<void> Function(Map<String, dynamic> employee, Map<String, dynamic> patch)? onDetails;
  final bool readOnly;

  const DailyAttendanceCard({
    super.key,
    required this.employee,
    required this.status,
    required this.onMark,
    this.record,
    this.contracts = const [],
    this.onDetails,
    this.readOnly = false,
  });

  @override
  State<DailyAttendanceCard> createState() => _DailyAttendanceCardState();
}

class _DailyAttendanceCardState extends State<DailyAttendanceCard> {
  final _work = TextEditingController();
  final _focus = FocusNode();
  String? _pending;

  String get _savedNote => (widget.record?['notes'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _work.text = _savedNote;
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant DailyAttendanceCard old) {
    super.didUpdateWidget(old);
    final before = (old.record?['notes'] ?? '').toString();
    if (before != _savedNote && !_focus.hasFocus) _work.text = _savedNote;
  }

  @override
  void dispose() {
    _focus.dispose();
    _work.dispose();
    super.dispose();
  }

  void _commit() {
    final text = _work.text.trim();
    if (text != _savedNote) widget.onDetails?.call(widget.employee, {'notes': text});
  }

  Future<void> _mark(String v) async {
    setState(() => _pending = v);
    try {
      await widget.onMark(widget.employee, v);
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final e = widget.employee;
    final status = widget.status;
    final atWork = status == 'present' || status == 'half_day';
    final notes = _savedNote;
    return Surface(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((e['name'] ?? '').toString(), style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(dash(e['role_title']), style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (widget.readOnly) StatusChip(status, label: dayLabel(status), tone: status == null ? Tone.neutral : dayTone(status)),
        ]),
        if (!widget.readOnly) ...[
          const SizedBox(height: 10),
          StatusSegments(
            options: kDayStatuses,
            value: status,
            pending: _pending,
            busy: _pending != null,
            onTap: _mark,
          ),
        ],
        if (atWork && widget.onDetails != null && !widget.readOnly) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _work,
            focusNode: _focus,
            minLines: 1,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _focus.unfocus(),
            decoration: const InputDecoration(
              hintText: 'Work done today',
              prefixIcon: Icon(Icons.edit_note, size: 20),
            ),
          ),
          if (widget.contracts.isNotEmpty) ...[
            const SizedBox(height: 10),
            AppDropdown<int?>(
              label: "Put on a contractor's work (NMR)",
              value: widget.record?['subcontract_id'] as int?,
              items: [
                (null, 'Own work'),
                for (final c in widget.contracts)
                  (c['subcontract_id'] as int?, 'NMR for ${c['vendor_name'] ?? c['number'] ?? ''}'),
              ],
              onChanged: (v) => widget.onDetails!(e, {'subcontract_id': v}),
            ),
          ],
        ],
        if (widget.readOnly && notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(notes, style: tt.bodySmall?.copyWith(color: p.fgMuted)),
        ],
      ]),
    );
  }
}
