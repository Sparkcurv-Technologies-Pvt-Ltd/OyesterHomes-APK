import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import 'setup_kit.dart';

// Staff attendance month grid (web StaffAttendanceTab.jsx + hrConstants.js). On a phone each person
// gets a month calendar (Mon–Sun columns) instead of one wide row per person.

/// Mirrors BACKDATE_DAYS in routers/hr.py: only today and the past 3 days can be changed.
const _backdateDays = 3;

class _Att {
  final String label;
  final String code;
  final Tone tone;
  const _Att(this.label, this.code, this.tone);
}

/// ATT_META from hrConstants.js.
const _attMeta = <String, _Att>{
  'present': _Att('Present', 'P', Tone.success),
  'absent': _Att('Absent', 'A', Tone.danger),
  'half_day': _Att('Half day', '½', Tone.warning),
  'leave': _Att('Leave', 'L', Tone.info),
  'week_off': _Att('Week off', 'WO', Tone.neutral),
  'holiday': _Att('Holiday', 'H', Tone.accent),
};

const _editableStatuses = ['present', 'absent', 'half_day', 'week_off', 'holiday'];

String _monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

String _shiftMonth(String key, int n) {
  final p = key.split('-').map(int.parse).toList();
  return _monthKey(DateTime(p[0], p[1] + n, 1));
}

String _monthLabel(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateFormat('MMMM yyyy').format(DateTime(p[0], p[1], 1));
}

class StaffAttendanceTab extends StatefulWidget {
  const StaffAttendanceTab({super.key});

  @override
  State<StaffAttendanceTab> createState() => _StaffAttendanceTabState();
}

class _StaffAttendanceTabState extends State<StaffAttendanceTab> {
  final _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  String _month = _monthKey(DateTime.now());
  String _markDate = todayIso();
  bool _busy = false;

  Future<void> _refresh() async => _view.currentState?.reload();

  String _earliest(String? serverToday) {
    final d = toDate(serverToday ?? todayIso())!;
    return isoDay(DateTime(d.year, d.month, d.day - _backdateDays));
  }

  Future<void> _markAll() async {
    setState(() => _busy = true);
    final api = context.read<ApiClient>();
    try {
      final r = await api.post('/staff-attendance/mark-all', data: {'date': _markDate}) as Map;
      final n = toInt(r['marked']);
      if (mounted) {
        showToast(context, n > 0 ? 'Marked $n present for ${fmtDate(_markDate)}' : 'Everyone is already marked for that day');
      }
      _refresh();
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _openCell(Map<String, dynamic> person, String date, Map<String, dynamic>? rec) async {
    final d = toDate(date)!;
    final ok = await showAppSheet<bool>(
      context,
      title: (person['name'] ?? '').toString(),
      subtitle: '${DateFormat('EEEE').format(d)}, ${fmtDate(date)}',
      builder: (_) => _CellEditor(person: person, date: date, record: rec),
    );
    if (ok == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final tt = Theme.of(context).textTheme;
    return AsyncView<Map<String, dynamic>>(
      key: _view,
      depKey: _month,
      load: () async {
        final data = Map<String, dynamic>.from(await api.get('/staff-attendance', params: {'month': _month}) as Map);
        // Use the server's date (IST) so "today" never counts as a future date.
        final today = data['today']?.toString();
        if (today != null && _markDate.compareTo(today) > 0 && mounted) setState(() => _markDate = today);
        return data;
      },
      builder: (context, data, reload) {
        final serverToday = data['today']?.toString();
        final earliest = _earliest(serverToday);
        final staff = asMaps(data['staff']);
        final days = asMaps(data['days']);
        return RefreshList(
          onRefresh: reload,
          padding: const EdgeInsets.only(top: 4, bottom: 96),
          children: [
            // Month switcher + Excel.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kGutter - 4),
              child: Row(children: [
                IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => setState(() => _month = _shiftMonth(_month, -1)),
                    icon: const Icon(Icons.chevron_left)),
                Expanded(child: Text(_monthLabel(_month), textAlign: TextAlign.center, style: tt.titleMedium)),
                IconButton(
                    tooltip: 'Next month',
                    onPressed: () => setState(() => _month = _shiftMonth(_month, 1)),
                    icon: const Icon(Icons.chevron_right)),
                TextButton.icon(
                  onPressed: () => downloadAndOpen(context, api, '/staff-attendance/export',
                      params: {'month': _month}, fallbackName: 'staff-attendance-$_month.xlsx'),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Excel'),
                ),
              ]),
            ),
            // Mark everyone unmarked as present for a day.
            Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: DateField(
                    label: 'Day',
                    value: _markDate,
                    requiredField: true,
                    firstDate: toDate(earliest),
                    lastDate: toDate(serverToday ?? todayIso()),
                    onChanged: (v) => setState(() => _markDate = v ?? _markDate),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _markAll,
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.done_all, size: 18),
                    label: const Text('Mark unmarked\npresent', textAlign: TextAlign.center),
                  ),
                ),
              ]),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: kGutter), child: _Legend()),
            const SizedBox(height: 12),
            if (staff.isEmpty)
              const EmptyState(
                icon: Icons.groups_outlined,
                title: 'No staff yet.',
                message:
                    'Attendance covers Site Engineers, Accountants and Procurement Officers — add them in the Team tab.',
              )
            else
              for (final p in staff)
                _PersonMonth(
                  person: p,
                  days: days,
                  today: serverToday,
                  earliest: earliest,
                  onTap: (date, rec) => _openCell(p, date, rec),
                ),
            const HelpText(
              'Deduct = absent + ½ × half days + unpaid leave days. Payroll deducts these automatically '
              '(base salary ÷ days in the pay period × deduct days).',
              padding: EdgeInsets.fromLTRB(kGutter, 4, kGutter, 0),
            ),
          ],
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 12, runSpacing: 6, children: [
        for (final m in _attMeta.values)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 24,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.toneFill(m.tone), borderRadius: BorderRadius.circular(4)),
              child: Text(m.code, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.tone(m.tone))),
            ),
            const SizedBox(width: 5),
            Text(m.label, style: tt.bodySmall),
          ]),
      ]),
      const SizedBox(height: 6),
      Text('Tap a day to edit (today and the past $_backdateDays days) · Sundays are weekly off', style: tt.bodySmall),
    ]);
  }
}

class _PersonMonth extends StatelessWidget {
  final Map<String, dynamic> person;
  final List<Map<String, dynamic>> days;
  final String? today;
  final String earliest;
  final void Function(String date, Map<String, dynamic>? rec) onTap;
  const _PersonMonth(
      {required this.person, required this.days, required this.today, required this.earliest, required this.onTap});

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final records = Map<String, dynamic>.from(person['records'] as Map? ?? const {});
    final s = Map<String, dynamic>.from(person['summary'] as Map? ?? const {});
    final lead = days.isEmpty ? 0 : _weekdays.indexOf(days.first['weekday'].toString()).clamp(0, 6);
    String v(dynamic x) => toNum(x) == 0 ? '–' : qty(x);
    final deduct = toNum(s['deduction_days']);

    return Surface(
      margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((person['name'] ?? '').toString(), style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(roleWords(person['role']?.toString()), style: tt.bodySmall),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Eyebrow('Deduct'),
            Text(v(s['deduction_days']),
                style: tabular(tt.titleSmall).copyWith(color: deduct > 0 ? p.danger : null, fontWeight: FontWeight.w700)),
          ]),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          for (final (k, label) in const [
            ('present', 'P'),
            ('absent', 'A'),
            ('half_day', '½'),
            ('leave', 'L'),
            ('unmarked', '?'),
          ])
            Expanded(
              child: Tooltip(
                message: _attMeta[k]?.label ?? 'Unmarked working days',
                child: Column(children: [
                  Text(label, style: tt.labelSmall),
                  Text(v(s[k]), style: tabular(tt.bodyMedium)),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, c) {
          const gap = 4.0;
          final size = ((c.maxWidth - gap * 6) / 7).floorToDouble();
          return Column(children: [
            Row(children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                SizedBox(
                    width: size,
                    child: Text(_weekdays[i][0], textAlign: TextAlign.center, style: tt.bodySmall?.copyWith(fontSize: 10))),
              ],
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: gap, runSpacing: gap, children: [
              for (var i = 0; i < lead; i++) SizedBox(width: size, height: size),
              for (final d in days)
                _DayCell(
                  size: size,
                  day: d,
                  record: records[d['date']] == null ? null : Map<String, dynamic>.from(records[d['date']] as Map),
                  isToday: d['date'] == today,
                  locked: d['date'].toString().compareTo(earliest) < 0,
                  onTap: (rec) => onTap(d['date'].toString(), rec),
                ),
            ]),
          ]);
        }),
      ]),
    );
  }
}

class _DayCell extends StatelessWidget {
  final double size;
  final Map<String, dynamic> day;
  final Map<String, dynamic>? record;
  final bool isToday;
  final bool locked;
  final ValueChanged<Map<String, dynamic>?> onTap;
  const _DayCell(
      {required this.size, required this.day, required this.record, required this.isToday, required this.locked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final rec = record;
    final sunday = day['is_sunday'] == true;
    final future = day['is_future'] == true;
    final frozen = future || locked;
    final meta = rec != null ? _attMeta[rec['status']] : (sunday ? _attMeta['week_off'] : null);
    final code = rec != null
        ? (rec['status'] == 'leave' && rec['is_half'] == true ? 'L½' : (meta?.code ?? '?'))
        : (sunday ? '·' : '');
    final tone = rec != null ? meta?.tone : null;
    final title = rec != null
        ? '${meta?.label ?? rec['status']}${rec['leave_type'] != null ? ' (${rec['leave_type']})' : ''}'
            '${rec['check_in'] != null ? ' · in ${rec['check_in']}' : ''}${rec['check_out'] != null ? ' · out ${rec['check_out']}' : ''}'
            '${(rec['note'] ?? '').toString().isNotEmpty ? ' · ${rec['note']}' : ''}'
        : (future ? '' : 'Not marked');
    final tip = !future && locked ? '${title.isNotEmpty ? '$title · ' : ''}Locked (older than $_backdateDays days)' : title;

    final cell = Opacity(
      opacity: rec == null && frozen ? 0.35 : 1,
      child: Material(
        color: tone != null ? p.toneFill(tone) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: isToday
              ? BorderSide(color: p.accent, width: 1.5)
              : (rec == null && !frozen && !sunday ? BorderSide(color: p.inputBorder) : BorderSide.none),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: frozen ? null : () => onTap(rec),
          child: SizedBox(
            width: size,
            height: size,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${day['day']}', style: tabular(TextStyle(fontSize: 9, color: p.fgSubtle))),
              Text(code,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: tone != null ? p.tone(tone) : p.fgSubtle)),
            ]),
          ),
        ),
      ),
    );
    return tip.isEmpty ? cell : Tooltip(message: tip, child: cell);
  }
}

class _CellEditor extends StatefulWidget {
  final Map<String, dynamic> person;
  final String date;
  final Map<String, dynamic>? record;
  const _CellEditor({required this.person, required this.date, required this.record});

  @override
  State<_CellEditor> createState() => _CellEditorState();
}

class _CellEditorState extends State<_CellEditor> {
  late final Map<String, dynamic>? rec = widget.record;
  late String _status = rec?['status'] != null && rec!['status'] != 'leave' ? rec!['status'].toString() : 'present';
  late String _checkIn = (rec?['check_in'] ?? '').toString();
  late String _checkOut = (rec?['check_out'] ?? '').toString();
  late final _note = TextEditingController(text: (rec?['note'] ?? '').toString());
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() call, String ok) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await call();
      if (!mounted) return;
      showToast(context, ok);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorText(e);
      });
      showToast(context, errorText(e), error: true);
    }
  }

  Future<void> _save() {
    final api = context.read<ApiClient>();
    return _run(
        () => api.put('/staff-attendance', data: {
              'user_id': widget.person['id'],
              'date': widget.date,
              'status': _status,
              'check_in': _checkIn,
              'check_out': _checkOut,
              'note': _note.text,
            }),
        'Attendance saved');
  }

  Future<void> _clear() {
    final api = context.read<ApiClient>();
    return _run(() => api.delete('/staff-attendance', params: {'user_id': widget.person['id'], 'date': widget.date}),
        'Cleared');
  }

  Future<void> _pickTime(bool checkIn) async {
    final cur = checkIn ? _checkIn : _checkOut;
    final parts = cur.split(':');
    final initial = parts.length >= 2
        ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0)
        : TimeOfDay(hour: checkIn ? 9 : 18, minute: 0);
    final t = await showTimePicker(context: context, initialTime: initial);
    if (t == null) return;
    final v = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() => checkIn ? _checkIn = v : _checkOut = v);
  }

  Widget _timeField(String label, String value, bool checkIn) => InkWell(
        borderRadius: BorderRadius.circular(Radii.control),
        onTap: () => _pickTime(checkIn),
        child: InputDecorator(
          isEmpty: value.isEmpty,
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: value.isEmpty
                ? const Icon(Icons.schedule, size: 18)
                : IconButton(
                    tooltip: 'Clear time',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => checkIn ? _checkIn = '' : _checkOut = ''),
                  ),
          ),
          child: Text(value, style: tabular(Theme.of(context).textTheme.bodyLarge)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    if (rec?['source'] == 'leave') {
      final r = rec!;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.lock_outline, size: 16, color: p.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(style: tt.bodyMedium, children: [
              const TextSpan(text: 'Approved '),
              TextSpan(text: '${r['leave_type']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' leave${r['is_half'] == true ? ' (half day)' : ''}.'),
            ])),
          ),
        ]),
        const SizedBox(height: 8),
        Text('To change this day, cancel the leave in the Leave Requests tab.', style: tt.bodySmall),
        if (r['check_in'] != null) ...[
          const SizedBox(height: 6),
          Text('Checked in ${r['check_in']}${r['check_out'] != null ? ' · out ${r['check_out']}' : ''}', style: tt.bodySmall),
        ],
        const SizedBox(height: 12),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ChoiceRow<String>(
        value: _status,
        options: [for (final s in _editableStatuses) (s, _attMeta[s]!.label)],
        onChanged: (s) => setState(() => _status = s),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _timeField('Check in', _checkIn, true)),
        const SizedBox(width: 12),
        Expanded(child: _timeField('Check out', _checkOut, false)),
      ]),
      kFieldGap,
      AppTextField(controller: _note, label: 'Note (optional)', textInputAction: TextInputAction.done),
      if (rec?['source'] == 'self') ...[
        const SizedBox(height: 8),
        Text('Self check-in by ${widget.person['name']}. Saving will mark it as edited by Admin.', style: tt.bodySmall),
      ],
      const SizedBox(height: 18),
      SheetError(_error),
      SubmitButton(label: 'Save', busy: _busy, onPressed: _save),
      if (rec != null) ...[
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: TextButton(
            onPressed: _busy ? null : _clear,
            style: TextButton.styleFrom(foregroundColor: p.danger),
            child: const Text('Clear'),
          ),
        ),
      ],
    ]);
  }
}
