import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../network/api_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

// Shared building blocks. Every screen uses these so the app reads as one system:
// Surface (bordered card, the web's `.surface`), Eyebrow (the web's `.section-eyebrow`),
// StatusChip (all the web's *StatusBadge components), KpiTile, AsyncView (loading / error / empty),
// showAppSheet (the web's Dialogs become bottom sheets), form fields, toasts and confirms.

/// Screen side gutter.
const kGutter = 16.0;

// ───────────────────────────────────────────────────────── surfaces & text

/// The web's `.surface`: card fill, 1px border, 10px radius, no shadow. Tappable when [onTap] is set.
class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Color? borderColor;

  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.onLongPress,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final radius = BorderRadius.circular(Radii.card);
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: color ?? p.card,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: borderColor ?? p.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Small uppercase label with wide tracking (web `.section-eyebrow` / `text-[10px] uppercase tracking-[0.2em]`).
class Eyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  const Eyebrow(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
}

/// Eyebrow-style section heading with an optional trailing action (e.g. "+ Add phase").
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionHeader(this.title, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(kGutter, 20, kGutter, 8)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(child: Eyebrow(title)),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Label above value, the web's InfoCell / key-value pairs.
class InfoTile extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? valueWidget;
  final bool figure;
  const InfoTile({super.key, required this.label, this.value, this.valueWidget, this.figure = false});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Eyebrow(label),
      const SizedBox(height: 5),
      valueWidget ?? Text(dash(value), style: figure ? tabular(tt.titleMedium) : tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
    ]);
  }
}

/// A row of "label ........ value" (right-aligned, tabular) used inside surfaces and totals.
class KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool strong;
  final EdgeInsetsGeometry padding;
  const KeyValueRow(this.label, this.value,
      {super.key, this.valueColor, this.strong = false, this.padding = const EdgeInsets.symmetric(vertical: 6)});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    return Padding(
      padding: padding,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(label, style: strong ? tt.titleSmall : tt.bodyMedium?.copyWith(color: p.fgMuted))),
        const SizedBox(width: 12),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.right,
              style: tabular(strong ? tt.titleMedium : tt.bodyMedium)
                  .copyWith(color: valueColor, fontWeight: strong ? FontWeight.w700 : FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────── status chips

/// Tone for every status word the web colours (ProjectStatusBadge, FlagBadge, CommitmentStatusBadge,
/// ChangeOrderStatusBadge, phase states, attendance). Unknown words are neutral.
Tone statusTone(String? status) {
  switch ((status ?? '').replaceAll(' ', '').toLowerCase()) {
    case 'completed':
    case 'approved':
    case 'executed':
    case 'paid':
    case 'verified':
    case 'awarded':
    case 'ontrack':
    case 'present':
    case 'active':
    case 'delivered':
    case 'received':
    case 'fullyreceived':
    case 'released':
    case 'success':
    case 'accepted':
    case 'won':
    case 'instock':
      return Tone.success;
    case 'ongoing':
    case 'inprogress':
    case 'pending':
    case 'pendingapproval':
    case 'pendingclientreview':
    case 'underreview':
    case 'partial':
    case 'partiallypaid':
    case 'delayed':
    case 'halfday':
    case 'requested':
    case 'awaitingapproval':
    case 'lowstock':
      return Tone.warning;
    case 'cancelled':
    case 'terminated':
    case 'rejected':
    case 'returned':
    case 'overdue':
    case 'blocked':
    case 'absent':
    case 'failed':
    case 'disabled':
    case 'outofstock':
    case 'shortclosed':
    case 'lost':
      return Tone.danger;
    case 'planning':
    case 'partiallyreceived':
    case 'intransit':
    case 'submitted':
    case 'sent':
    case 'revisionrequested':
    case 'issued':
    case 'leave':
    case 'open':
      return Tone.info;
    case 'onhold':
      return Tone.orange;
    default:
      return Tone.neutral;
  }
}

/// Rounded uppercase status badge. [label] defaults to the humanized status ("Pending Approval").
class StatusChip extends StatelessWidget {
  final String? status;
  final String? label;
  final Tone? tone;
  final bool dense;
  const StatusChip(this.status, {super.key, this.label, this.tone, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final t = tone ?? statusTone(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(
        color: p.toneFill(t),
        border: Border.all(color: p.toneBorder(t)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        (label ?? humanize(status)).toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            TextStyle(fontFamily: 'Inter', fontSize: dense ? 9.5 : 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: p.tone(t)),
      ),
    );
  }
}

/// Small bordered code tag in mono (company code, PO number, gear key).
class CodeTag extends StatelessWidget {
  final String text;
  const CodeTag(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(4)),
      child: Text(text,
          style: TextStyle(fontFamily: monoFamily, fontSize: 10, letterSpacing: 0.8, color: p.fgMuted, fontWeight: FontWeight.w500)),
    );
  }
}

// ───────────────────────────────────────────────────────── figures

/// KPI tile (web DashboardStatCard): eyebrow label, big tabular figure, optional sub line.
/// Colour only when the figure carries state ([tone]).
class KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Tone? tone;
  final IconData? icon;
  final VoidCallback? onTap;
  const KpiTile({super.key, required this.label, required this.value, this.sub, this.tone, this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    return Surface(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Eyebrow(label)),
          if (icon != null) Icon(icon, size: 15, color: p.fgSubtle),
        ]),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              maxLines: 1,
              style: tabular(tt.headlineSmall).copyWith(color: tone == null ? p.fg : p.tone(tone!), fontWeight: FontWeight.w700)),
        ),
        if (sub != null) ...[
          const SizedBox(height: 3),
          Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
        ],
      ]),
    );
  }
}

/// Two-column grid of KPI tiles that keeps tiles the same height per row.
class KpiGrid extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  final EdgeInsetsGeometry padding;
  const KpiGrid({super.key, required this.children, this.columns = 2, this.padding = const EdgeInsets.symmetric(horizontal: kGutter)});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final slice = children.sublist(i, (i + columns).clamp(0, children.length));
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var j = 0; j < columns; j++) ...[
            if (j > 0) const SizedBox(width: 10),
            Expanded(child: j < slice.length ? slice[j] : const SizedBox()),
          ],
        ]),
      ));
      if (i + columns < children.length) rows.add(const SizedBox(height: 10));
    }
    return Padding(padding: padding, child: Column(children: rows));
  }
}

/// Thin rounded progress bar (web `.level-bar`). [value] is 0..1. [tone] overrides the colour.
class LevelBar extends StatelessWidget {
  final double value;
  final Tone? tone;
  final double height;
  const LevelBar(this.value, {super.key, this.tone, this.height = 6});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value.isNaN ? 0 : value.clamp(0, 1),
        minHeight: height,
        backgroundColor: p.muted,
        color: tone == null ? p.accent : p.tone(tone!),
      ),
    );
  }
}

/// Money, right-aligned and tabular.
class MoneyText extends StatelessWidget {
  final dynamic amount;
  final TextStyle? style;
  final Color? color;
  final bool compact;
  const MoneyText(this.amount, {super.key, this.style, this.color, this.compact = false});

  @override
  Widget build(BuildContext context) => Text(compact ? inrCompact(amount) : inr(amount),
      textAlign: TextAlign.right, style: tabular(style ?? Theme.of(context).textTheme.titleSmall).copyWith(color: color));
}

// ───────────────────────────────────────────────────────── states

class LoadingView extends StatelessWidget {
  final String? label;
  const LoadingView({super.key, this.label});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
            if (label != null) ...[const SizedBox(height: 12), Text(label!, style: Theme.of(context).textTheme.bodySmall)],
          ]),
        ),
      );
}

/// Dashed-border empty box (web: `border border-dashed ... text-center`).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const EmptyState({super.key, this.icon = Icons.inbox_outlined, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 34, color: p.fgSubtle),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: tt.titleSmall),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(message!, textAlign: TextAlign.center, style: tt.bodySmall),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

class ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorRetry({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final offline = message.startsWith('Could not reach');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(offline ? Icons.cloud_off_outlined : Icons.error_outline, size: 34, color: p.danger),
        const SizedBox(height: 12),
        Text(offline ? 'You are offline or the server is unreachable' : 'Could not load this',
            textAlign: TextAlign.center, style: tt.titleSmall),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center, style: tt.bodySmall),
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 18), label: const Text('Try again')),
      ]),
    );
  }
}

/// Loads data once (and again when [depKey] changes), then hands it to [builder] with a `reload`.
/// Shows a spinner on first load and ErrorRetry on failure; keeps old data visible while reloading.
///
/// Wrap scrollable content in [RefreshList] (or your own RefreshIndicator calling `reload`) for pull-to-refresh.
class AsyncView<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final Object? depKey;
  final Widget? loading;
  const AsyncView({super.key, required this.load, required this.builder, this.depKey, this.loading});

  @override
  State<AsyncView<T>> createState() => AsyncViewState<T>();
}

class AsyncViewState<T> extends State<AsyncView<T>> {
  T? _data;
  bool _has = false;
  Object? _error;
  bool _loading = true;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void didUpdateWidget(covariant AsyncView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.depKey != widget.depKey) {
      _has = false;
      reload();
    }
  }

  Future<void> reload() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (!mounted || gen != _gen) return;
      setState(() {
        _data = d;
        _has = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_has) return widget.builder(context, _data as T, reload);
    if (_error != null) {
      return LayoutBuilder(
        // Inside an outer scroll view (sections embedded in a list) the height is unbounded:
        // show the retry box as-is instead of nesting another scrollable.
        builder: (context, c) => !c.maxHeight.isFinite
            ? ErrorRetry(message: errorText(_error), onRetry: reload)
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                  SizedBox(
                    height: c.maxHeight.isFinite ? c.maxHeight : null,
                    child: Center(child: ErrorRetry(message: errorText(_error), onRetry: reload)),
                  ),
                ]),
              ),
      );
    }
    return _loading ? (widget.loading ?? const LoadingView()) : const SizedBox();
  }
}

/// Readable text for any thrown error.
String errorText(Object? e) => e is ApiException ? e.message : (e?.toString() ?? 'Something went wrong');

/// Pull-to-refresh list with the standard gutter and room for a FAB at the bottom.
class RefreshList extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;
  const RefreshList({
    super.key,
    required this.onRefresh,
    required this.children,
    this.padding = const EdgeInsets.only(top: 8, bottom: 96),
    this.controller,
  });

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          controller: controller,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          children: children,
        ),
      );
}

// ───────────────────────────────────────────────────────── feedback

/// Toast (the web uses sonner). [error] colours it as a failure.
void showToast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final p = context.pal;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline,
            size: 18, color: error ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7)),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      duration: Duration(milliseconds: error ? 4500 : 2600),
      backgroundColor: error ? (p.dark ? const Color(0xFF3B1418) : const Color(0xFF7F1D1D)) : null,
    ));
}

/// Runs [action], toasts [success] or the API error. Returns true on success.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) showToast(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showToast(context, errorText(e), error: true);
    return false;
  }
}

/// Yes/no dialog (the web's `window.confirm`). [destructive] paints the confirm button red.
Future<bool> confirmDialog(BuildContext context,
    {required String title, String? message, String confirmLabel = 'Confirm', bool destructive = false}) async {
  final p = context.pal;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: p.fgMuted))),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Single text prompt (reasons for reject / cancel, the web's `window.prompt`). Null when cancelled.
Future<String?> promptText(BuildContext context,
    {required String title, String? label, String? initial, String confirmLabel = 'OK', bool required = false, int maxLines = 3}) async {
  final c = TextEditingController(text: initial);
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: 1,
          maxLines: maxLines,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label),
          onChanged: (_) => set(() {}),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: required && c.text.trim().isEmpty ? null : () => Navigator.pop(ctx, c.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  return res;
}

// ───────────────────────────────────────────────────────── sheets & forms

/// Opens a form as a scrollable bottom sheet that rises above the keyboard (the web's Dialogs).
/// [builder] gets the sheet's context; pop it with a result to return one.
Future<T?> showAppSheet<T>(BuildContext context,
    {required String title, String? subtitle, required Widget Function(BuildContext ctx) builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final tt = Theme.of(ctx).textTheme;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.92),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: tt.headlineSmall),
              if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle, style: tt.bodySmall)],
              const SizedBox(height: 18),
              builder(ctx),
            ]),
          ),
        ),
      );
    },
  );
}

/// Primary submit button for sheets/forms with a busy spinner. Full width.
class SubmitButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool destructive;
  const SubmitButton({super.key, required this.label, this.busy = false, this.onPressed, this.icon, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        style: destructive ? FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white) : null,
        onPressed: busy ? null : onPressed,
        child: busy
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: p.onPrimaryBtn))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                Text(label),
              ]),
      ),
    );
  }
}

/// Vertical spacing between form fields.
const kFieldGap = SizedBox(height: 14);

/// Text field with its label in the border (material outlined). Pass [money] for ₹ amounts.
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final String? helper;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? minLines;
  final bool money;
  final bool number;
  final bool requiredField;
  final bool enabled;
  final bool obscure;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final Widget? prefixIcon;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization? capitalization;
  final String? initialValue;
  final bool autofocus;

  const AppTextField({
    super.key,
    this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.money = false,
    this.number = false,
    this.requiredField = false,
    this.enabled = true,
    this.obscure = false,
    this.validator,
    this.onChanged,
    this.suffix,
    this.prefixIcon,
    this.textInputAction,
    this.onSubmitted,
    this.capitalization,
    this.initialValue,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final numeric = money || number;
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      enabled: enabled,
      obscureText: obscure,
      autofocus: autofocus,
      keyboardType: keyboardType ??
          (numeric ? const TextInputType.numberWithOptions(decimal: true) : (maxLines > 1 ? TextInputType.multiline : TextInputType.text)),
      inputFormatters: numeric ? [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*'))] : null,
      textCapitalization: capitalization ?? (numeric ? TextCapitalization.none : TextCapitalization.sentences),
      maxLines: obscure ? 1 : maxLines,
      minLines: minLines,
      textInputAction: textInputAction ?? (maxLines > 1 ? TextInputAction.newline : TextInputAction.next),
      onFieldSubmitted: onSubmitted,
      onChanged: onChanged,
      style: numeric ? tabular(Theme.of(context).textTheme.bodyLarge) : null,
      validator: validator ?? (requiredField ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null : null),
      decoration: InputDecoration(
        labelText: requiredField ? '$label *' : label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
        prefixText: money ? '₹ ' : null,
        prefixIcon: prefixIcon,
        suffixIcon: suffix,
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}

/// Dropdown with an outlined label. [items] are (value, label) pairs. Use null value for "none".
class AppDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<(T, String)> items;
  final ValueChanged<T?>? onChanged;
  final bool requiredField;
  final String? hint;
  final String? helper;
  const AppDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.requiredField = false,
    this.hint,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final has = items.any((e) => e.$1 == value);
    return DropdownButtonFormField<T>(
      value: has ? value : null,
      isExpanded: true,
      menuMaxHeight: 420,
      borderRadius: BorderRadius.circular(Radii.card),
      dropdownColor: context.pal.card,
      decoration: InputDecoration(labelText: requiredField ? '$label *' : label, hintText: hint, helperText: helper),
      validator: requiredField ? (v) => v == null ? '$label is required' : null : null,
      items: [
        for (final (v, l) in items) DropdownMenuItem<T>(value: v, child: Text(l, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }
}

/// Date picker field; [value] and the callback use API "YYYY-MM-DD" strings, display is dd/mm/yyyy.
class DateField extends StatelessWidget {
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool requiredField;
  final bool clearable;
  final DateTime? firstDate;
  final DateTime? lastDate;
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.requiredField = false,
    this.clearable = true,
    this.firstDate,
    this.lastDate,
  });

  @override
  Widget build(BuildContext context) {
    final has = value != null && value!.isNotEmpty;
    return FormField<String>(
      initialValue: value,
      validator: requiredField ? (_) => has ? null : '$label is required' : null,
      builder: (state) => InkWell(
        borderRadius: BorderRadius.circular(Radii.control),
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: toDate(value) ?? now,
            firstDate: firstDate ?? DateTime(now.year - 10),
            lastDate: lastDate ?? DateTime(now.year + 10),
          );
          if (picked != null) {
            onChanged(isoDay(picked));
            state.didChange(isoDay(picked));
          }
        },
        child: InputDecorator(
          isEmpty: !has,
          decoration: InputDecoration(
            labelText: requiredField ? '$label *' : label,
            errorText: state.errorText,
            suffixIcon: has && clearable && !requiredField
                ? IconButton(
                    tooltip: 'Clear date',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      onChanged(null);
                      state.didChange(null);
                    })
                : const Icon(Icons.calendar_today_outlined, size: 18),
          ),
          child: Text(has ? fmtDate(value) : '', style: tabular(Theme.of(context).textTheme.bodyLarge)),
        ),
      ),
    );
  }
}

/// Segmented single choice (the web's RadioRow, e.g. payment type / mode).
class ChoiceRow<T> extends StatelessWidget {
  final String? label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  const ChoiceRow({super.key, this.label, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label != null) ...[Eyebrow(label!), const SizedBox(height: 8)],
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (v, l) in options)
          ChoiceChip(
            label: Text(l),
            selected: v == value,
            onSelected: (_) => onChanged(v),
            labelStyle: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: v == value ? FontWeight.w700 : FontWeight.w600,
                color: v == value ? p.onPrimaryBtn : p.fgMuted),
          ),
      ]),
    ]);
  }
}

/// Horizontally scrolling filter chips (status filters, tabs inside a tab).
class FilterBar<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry padding;
  const FilterBar(
      {super.key,
      required this.value,
      required this.options,
      required this.onChanged,
      this.padding = const EdgeInsets.symmetric(horizontal: kGutter, vertical: 8)});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(children: [
        for (final (v, l) in options) ...[
          ChoiceChip(
            label: Text(l),
            selected: v == value,
            onSelected: (_) => onChanged(v),
            labelStyle: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: v == value ? FontWeight.w700 : FontWeight.w600,
                color: v == value ? p.onPrimaryBtn : p.fgMuted),
          ),
          const SizedBox(width: 8),
        ],
      ]),
    );
  }
}

/// Search box for list screens.
class SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  const SearchField({super.key, this.hint = 'Search', required this.onChanged, this.controller});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, size: 20),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      );
}

/// Switch row for boolean form fields.
class SwitchRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const SwitchRow({super.key, required this.label, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle!),
        value: value,
        onChanged: onChanged,
      );
}

// ───────────────────────────────────────────────────────── layout helpers

/// A list row inside a Surface: title, optional subtitle lines, trailing widget (figure / chip), chevron when tappable.
class RowTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final bool chevron;
  const RowTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.chevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: padding,
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: tt.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (subtitleWidget != null) ...[const SizedBox(height: 3), subtitleWidget!],
                if (subtitle != null && subtitleWidget == null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: tt.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            if (chevron) ...[const SizedBox(width: 4), Icon(Icons.chevron_right, size: 20, color: p.fgSubtle)],
          ]),
        ),
      ),
    );
  }
}

/// A Surface holding rows separated by hairlines (the web's data tables, as a mobile list).
class RowGroup extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final Widget? header;
  final Widget? footer;
  const RowGroup(
      {super.key, required this.children, this.margin = const EdgeInsets.symmetric(horizontal: kGutter), this.header, this.footer});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Surface(
      margin: margin,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (header != null) ...[header!, Divider(height: 1, color: p.border)],
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 14, endIndent: 14, color: p.border),
          children[i],
        ],
        if (footer != null) ...[Divider(height: 1, color: p.border), footer!],
      ]),
    );
  }
}

/// Totals band at the bottom of a list (muted fill, strong figure).
class TotalBand extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const TotalBand(this.label, this.value, {super.key, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    return Container(
      color: p.muted,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Expanded(child: Eyebrow(label)),
        Text(value, style: tabular(tt.titleMedium).copyWith(fontWeight: FontWeight.w700, color: valueColor)),
      ]),
    );
  }
}

/// Avatar circle with initials (account button, people rows).
class InitialsAvatar extends StatelessWidget {
  final String? name;
  final double size;
  const InitialsAvatar(this.name, {super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.accent.withValues(alpha: 0.15),
        border: Border.all(color: p.accent.withValues(alpha: 0.4)),
      ),
      child: Text(initials(name).isEmpty ? '?' : initials(name),
          style: TextStyle(fontFamily: 'Inter', fontSize: size * 0.33, fontWeight: FontWeight.w700, color: p.accentText)),
    );
  }
}

/// Standard pushed-screen scaffold: title (+ optional subtitle) in the app bar.
class AppScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget body;
  final Widget? fab;
  final PreferredSizeWidget? bottom;
  final Widget? bottomBar;
  const AppScaffold(
      {super.key, required this.title, this.subtitle, this.actions, required this.body, this.fab, this.bottom, this.bottomBar});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
        ]),
        actions: actions,
        bottom: bottom,
      ),
      body: SafeArea(top: false, child: body),
      floatingActionButton: fab,
      bottomNavigationBar: bottomBar,
    );
  }
}
