import 'package:intl/intl.dart';

/// The API sends money and quantities as numbers or, for Decimal columns, as strings. Read both.
double toNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

/// Nullable variant: null / empty / unparseable stays null.
double? toNumOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int toInt(dynamic v) => toNum(v).round();

final _inr = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 2);
final _inr0 = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0);
final _qty = NumberFormat('#,##,##0.###', 'en_IN');

/// ₹ with Indian grouping, like the web's `fmtMoney` (`toLocaleString("en-IN")`): decimals only when present.
String inr(dynamic value, {bool forceDecimals = false}) {
  final v = toNum(value);
  final whole = v == v.roundToDouble();
  final s = (forceDecimals || !whole) ? _inr.format(v) : _inr0.format(v);
  return '₹$s';
}

/// ₹ in lakhs / crores for tight KPI tiles (₹1.25 Cr, ₹48.6 L, ₹12,400 below a lakh).
String inrCompact(dynamic value) {
  final v = toNum(value);
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  if (a >= 1e7) return '$sign₹${(a / 1e7).toStringAsFixed(a >= 1e9 ? 0 : 2)} Cr';
  if (a >= 1e5) return '$sign₹${(a / 1e5).toStringAsFixed(1)} L';
  return inr(v);
}

/// Quantity with Indian grouping and up to 3 decimals ("1,250.5").
String qty(dynamic value) => _qty.format(toNum(value));

/// Plain number for an input field: no trailing ".0".
String inputNum(dynamic value) {
  final v = toNumOrNull(value);
  if (v == null) return '';
  return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

final _isoDay = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// A calendar date ("YYYY-MM-DD") is that day, never shifted through a timezone (web lib/date.js).
DateTime? toDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString();
  if (s.isEmpty) return null;
  final m = _isoDay.firstMatch(s);
  if (m != null) return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  // Timestamps without an offset are UTC on this backend.
  final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(s);
  final d = DateTime.tryParse(hasZone ? s : '${s}Z');
  return d?.toLocal();
}

String _pad(int n) => n.toString().padLeft(2, '0');

/// "15/10/2026", as every date on the web. [empty] when there is no date.
String fmtDate(dynamic v, {String empty = '—'}) {
  final d = toDate(v);
  return d == null ? empty : '${_pad(d.day)}/${_pad(d.month)}/${d.year}';
}

final _time = DateFormat('h:mm a');

/// "15/10/2026, 2:30 pm".
String fmtDateTime(dynamic v, {String empty = '—'}) {
  final d = toDate(v);
  return d == null ? empty : '${fmtDate(d)}, ${_time.format(d).toLowerCase()}';
}

/// "YYYY-MM-DD" for the API.
String isoDay(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

String todayIso() => isoDay(DateTime.now());

/// "Oct 2026" style month label, and "2026-10" API month keys.
String fmtMonth(dynamic v) {
  final d = toDate(v is String && v.length == 7 ? '$v-01' : v);
  return d == null ? '—' : DateFormat('MMM yyyy').format(d);
}

String timeAgo(dynamic v) {
  final d = toDate(v);
  if (d == null) return '';
  final s = DateTime.now().difference(d).inSeconds;
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60}m ago';
  if (s < 86400) return '${s ~/ 3600}h ago';
  return '${s ~/ 86400}d ago';
}

/// "PendingApproval" → "Pending Approval" (the web's `status.replace(/([A-Z])/g, " $1")`).
String humanize(String? s) {
  if (s == null || s.isEmpty) return '—';
  return s.replaceAllMapped(RegExp(r'(?<=[a-z0-9])([A-Z])'), (m) => ' ${m[1]}').replaceAll('_', ' ').trim();
}

String initials(String? name) => (name ?? '')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => w[0].toUpperCase())
    .join();

String fileSize(dynamic bytes) {
  final b = toNum(bytes);
  if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1024).ceil().clamp(1, 1 << 30)} KB';
}

/// "—" for null / empty strings.
String dash(dynamic v) => (v == null || v.toString().trim().isEmpty) ? '—' : v.toString();
