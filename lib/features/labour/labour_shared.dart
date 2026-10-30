import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';

// Private helpers for the labour module (employees, attendance, subcontractors). Not shared outside this folder.

/// API list → typed maps.
List<Map<String, dynamic>> asMaps(dynamic v) =>
    (v as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

Map<String, dynamic>? asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;

/// The web's `fmtDateRange`: "01/10/2026 – 29/10/2026", one date when both are the same day.
String fmtDateRange(dynamic a, dynamic b) {
  if ((a == null || '$a'.isEmpty) && (b == null || '$b'.isEmpty)) return '—';
  final x = fmtDate(a, empty: '…');
  final y = fmtDate(b, empty: '…');
  return x == y ? x : '$x – $y';
}

/// ₹ with no decimals (ContractorWork.jsx `inr`: maximumFractionDigits 0).
String inr0(dynamic v) => inr(toNum(v).roundToDouble());

String daysAgoIso(int n) => isoDay(DateTime.now().subtract(Duration(days: n)));

String monthStartIso() {
  final d = DateTime.now();
  return isoDay(DateTime(d.year, d.month, 1));
}

/// "₹800/day", "₹20,000/monthly" (web: `${fmt(e.daily_wage)}/${e.wage_type === "daily" ? "day" : e.wage_type}`).
String wageText(Map<String, dynamic> e) {
  if (e['daily_wage'] == null) return '—';
  final t = e['wage_type'];
  return '${inr(e['daily_wage'])}/${t == 'daily' ? 'day' : (t ?? '')}';
}

/// Field-worker day statuses (value, letter, label) as DailyAttendanceCard.jsx OPTIONS.
const kDayStatuses = <(String, String, String)>[
  ('present', 'P', 'Present'),
  ('half_day', '½', 'Half Day'),
  ('absent', 'A', 'Absent'),
  ('leave', 'L', 'Leave'),
];

/// Contractor crew marks (ContractorWork.jsx MARKS).
const kCrewMarks = <(String, String, String)>[
  ('present', 'P', 'Present'),
  ('half_day', '½', 'Half day'),
  ('absent', 'A', 'Absent'),
];

/// FieldAttendanceSummary.jsx FIELD_STATUSES labels.
const kFieldStatuses = <(String, String)>[
  ('present', 'Present'),
  ('half_day', 'Half day'),
  ('absent', 'Absent'),
  ('leave', 'Leave'),
];

/// Tone for an attendance value ("half_day" → the kit's "halfday").
Tone dayTone(String? status) => statusTone((status ?? '').replaceAll('_', ''));

String dayLabel(String? status) {
  for (final (v, _, l) in kDayStatuses) {
    if (v == status) return l;
  }
  return 'Not marked';
}

/// The web's `formatApiErrorDetail` for a raw DioException (used where we need the response body too).
String dioDetail(DioException e) {
  final r = e.response;
  if (r == null) return 'Could not reach the server. Check your connection.';
  final data = r.data;
  if (data is Map && data['detail'] != null) {
    final d = data['detail'];
    if (d is String) return d;
    if (d is Map && d['message'] is String) return d['message'];
    if (d is Map && d['msg'] is String) return d['msg'];
    if (d is List) return d.map((x) => x is Map ? (x['msg'] ?? x.toString()) : x.toString()).join(' ');
    return d.toString();
  }
  return 'Something went wrong. Please try again.';
}

// ───────────────────────────────────────────────────────── widgets

/// Large segmented attendance choices for one worker: letter on top, label below, coloured by status when chosen.
/// Built for one thumb in the sun: 56dp tall, the whole width.
class StatusSegments extends StatelessWidget {
  final List<(String, String, String)> options;
  final String? value;

  /// The option being saved (shows a spinner) and/or waiting for a photo.
  final String? pending;
  final bool busy;
  final ValueChanged<String>? onTap;
  final double height;
  const StatusSegments({
    super.key,
    required this.options,
    required this.value,
    this.pending,
    this.busy = false,
    this.onTap,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(children: [
      for (var i = 0; i < options.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(child: _segment(context, p, options[i])),
      ],
    ]);
  }

  Widget _segment(BuildContext context, AppPalette p, (String, String, String) o) {
    final (v, letter, label) = o;
    final t = dayTone(v);
    final selected = value == v;
    final isPending = pending == v;
    final fg = selected ? (p.dark ? Slate.s950 : Colors.white) : (isPending ? p.accentText : p.tone(t));
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? p.tone(t) : p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          side: BorderSide(color: selected ? p.tone(t) : (isPending ? p.accent : p.toneBorder(t)), width: selected || isPending ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy || onTap == null ? null : () => onTap!(v),
          child: SizedBox(
            height: height,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (isPending && busy)
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
              else
                Text(letter, style: TextStyle(fontFamily: 'Inter', fontSize: 19, fontWeight: FontWeight.w800, color: fg, height: 1.1)),
              const SizedBox(height: 2),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Small label-over-figure cell used in row figures and payment summaries.
class Fig extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final CrossAxisAlignment align;
  final bool large;
  const Fig(this.label, this.value, {super.key, this.color, this.align = CrossAxisAlignment.start, this.large = false});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: align, mainAxisSize: MainAxisSize.min, children: [
      Eyebrow(label),
      const SizedBox(height: 3),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(value,
            maxLines: 1,
            style: tabular(large ? tt.titleMedium : tt.bodyMedium).copyWith(fontWeight: FontWeight.w700, color: color)),
      ),
    ]);
  }
}

/// Three figures in a muted band (the payment dialogs' Earned / Paid / Due header).
class FigBand extends StatelessWidget {
  final List<Widget> children;
  const FigBand({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: p.muted,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Row(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ]),
    );
  }
}

/// Inline error inside a bottom sheet (toasts sit behind an open sheet).
class SheetError extends StatelessWidget {
  final String? message;
  const SheetError(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    final p = context.pal;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.toneFill(Tone.danger),
        border: Border.all(color: p.toneBorder(Tone.danger)),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline, size: 18, color: p.danger),
        const SizedBox(width: 8),
        Expanded(child: Text(message!, style: TextStyle(color: p.danger, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// Muted helper paragraph (the web's `text-xs text-slate-500` notes).
class Note extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;
  const Note(this.text, {super.key, this.padding = const EdgeInsets.symmetric(horizontal: kGutter, vertical: 8)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}

/// Like the kit's AsyncView but safe inside a scrolling list: no nested scroll view, small spinner, keeps the
/// old data on screen while it reloads for a new [depKey]. [quiet] renders nothing on error (sections the
/// user's role may not be allowed to read, as the web's queries that fail silently).
class InlineAsync<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final Object? depKey;
  final bool quiet;
  const InlineAsync({super.key, required this.load, required this.builder, this.depKey, this.quiet = false});

  @override
  State<InlineAsync<T>> createState() => _InlineAsyncState<T>();
}

class _InlineAsyncState<T> extends State<InlineAsync<T>> {
  T? _data;
  bool _has = false;
  Object? _error;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant InlineAsync<T> old) {
    super.didUpdateWidget(old);
    if (old.depKey != widget.depKey) _reload();
  }

  Future<void> _reload() async {
    final gen = ++_gen;
    try {
      final d = await widget.load();
      if (!mounted || gen != _gen) return;
      setState(() {
        _data = d;
        _has = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_has) return widget.builder(context, _data as T, _reload);
    if (_error != null) {
      return widget.quiet ? const SizedBox.shrink() : ErrorRetry(message: errorText(_error), onRetry: _reload);
    }
    if (widget.quiet) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
    );
  }
}
