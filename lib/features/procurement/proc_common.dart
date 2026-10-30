import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';

// Helpers shared by the procurement screens (private to this folder).

/// Tones of the web's CommitmentStatusBadge (unknown words fall back to Draft's neutral).
const _procTones = <String, Tone>{
  'Draft': Tone.neutral,
  'PendingApproval': Tone.warning,
  'Approved': Tone.success,
  'PartiallyReceived': Tone.info,
  'Executed': Tone.success,
  'Closed': Tone.neutral,
  'Cancelled': Tone.danger,
  'Terminated': Tone.danger,
  'Pending': Tone.warning,
  'Rejected': Tone.danger,
  'InTransit': Tone.info,
  'Returned': Tone.danger,
  'Void': Tone.neutral,
  'Submitted': Tone.info,
  'UnderReview': Tone.warning,
  'Paid': Tone.success,
  'Received': Tone.info,
  'Verified': Tone.success,
  'Open': Tone.info,
  'Awarded': Tone.success,
  'Sent': Tone.info,
  'Partial': Tone.warning,
  'Overdue': Tone.danger,
};

/// The web's CommitmentStatusBadge.
class ProcStatus extends StatelessWidget {
  final String? status;
  final bool dense;
  const ProcStatus(this.status, {super.key, this.dense = false});

  @override
  Widget build(BuildContext context) =>
      StatusChip(status, tone: _procTones[status] ?? Tone.neutral, dense: dense);
}

/// Web `fmtCr`: "−₹1,200" for negatives (true minus sign), "₹1,200" otherwise.
String fmtSigned(dynamic n) {
  final v = toNum(n);
  return '${v < 0 ? '−' : ''}${inr(v.abs())}';
}

/// List helper: the API's JSON array as maps.
List<Map<String, dynamic>> asMaps(dynamic v) =>
    (v as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

/// Red inline error above a sheet's submit button (toasts sit under an open sheet).
class SheetError extends StatelessWidget {
  final String? message;
  const SheetError(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) return const SizedBox.shrink();
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.toneFill(Tone.danger),
          border: Border.all(color: p.toneBorder(Tone.danger)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(Icons.error_outline, size: 16, color: p.danger),
          const SizedBox(width: 8),
          Expanded(child: Text(message!, style: TextStyle(color: p.danger, fontSize: 13))),
        ]),
      ),
    );
  }
}

/// Small outlined action button used inside cards (Approve, Reject, Submit...).
class SmallAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Tone? tone;
  final IconData? icon;
  final bool filled;
  const SmallAction({super.key, required this.label, this.onPressed, this.tone, this.icon, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = tone == null ? null : p.tone(tone!);
    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
      Text(label),
    ]);
    if (filled) {
      return FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          backgroundColor: c,
          foregroundColor: c == null ? null : Colors.white,
        ),
        onPressed: onPressed,
        child: child,
      );
    }
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: c,
        side: c == null ? null : BorderSide(color: c.withValues(alpha: 0.5)),
      ),
      onPressed: onPressed,
      child: child,
    );
  }
}

/// Loader for a block inside an already-scrolling list (AsyncView's error view scrolls itself, so it can't nest).
/// Reloads when [depKey] changes; [builder] gets the data and a reload callback.
class InlineAsync<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final Object? depKey;
  const InlineAsync({super.key, required this.load, required this.builder, this.depKey});

  @override
  State<InlineAsync<T>> createState() => InlineAsyncState<T>();
}

class InlineAsyncState<T> extends State<InlineAsync<T>> {
  T? _data;
  bool _has = false;
  Object? _error;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void didUpdateWidget(covariant InlineAsync<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.depKey != widget.depKey) reload();
  }

  Future<void> reload() async {
    final gen = ++_gen;
    if (mounted) setState(() => _error = null);
    try {
      final d = await widget.load();
      if (!mounted || gen != _gen) return;
      setState(() {
        _data = d;
        _has = true;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && !_has) return ErrorRetry(message: errorText(_error), onRetry: reload);
    if (!_has) return const LoadingView();
    return widget.builder(context, _data as T, reload);
  }
}
