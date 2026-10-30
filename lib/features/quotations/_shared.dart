import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';

// Private helpers for the quotations / purchase-order / material-request screens.

/// Payment methods the backend accepts (PAY_METHODS in quotation_purchase_orders.py).
const kPayMethods = ['BankTransfer', 'Cash', 'Cheque', 'UPI'];

/// Loader for widgets that sit inside someone else's scrolling list: never scrolls itself, so the
/// error state is a plain ErrorRetry (AsyncView's error state is a ListView, which needs a bounded height).
class InlineAsync<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  const InlineAsync({super.key, required this.load, required this.builder});

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
    if (_has) return widget.builder(context, _data as T, reload);
    if (_error != null) return ErrorRetry(message: errorText(_error), onRetry: reload);
    return const LoadingView();
  }
}

List<Map<String, dynamic>> asMaps(dynamic v) =>
    v is List ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];

Map<String, dynamic>? asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;

/// QuotationStatusBadge: draft / sent / accepted / rejected / expired.
class QuotationStatusChip extends StatelessWidget {
  final String? status;
  final bool dense;
  const QuotationStatusChip(this.status, {super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      'sent' => Tone.info,
      'accepted' => Tone.success,
      'rejected' => Tone.danger,
      'expired' => Tone.warning,
      _ => Tone.neutral,
    };
    return StatusChip(status, label: status ?? 'draft', tone: tone, dense: dense);
  }
}

/// QuotationPOChip: PO Pending / PO Created / PO Sent / PO Cancelled from the quotation's `purchase_order` summary.
class QuotationPOChip extends StatelessWidget {
  final Map<String, dynamic>? po;
  const QuotationPOChip(this.po, {super.key});

  @override
  Widget build(BuildContext context) {
    var label = 'PO Pending';
    var tone = Tone.neutral;
    if (po != null) {
      if (po!['status'] == 'CANCELLED') {
        label = 'PO Cancelled';
        tone = Tone.danger;
      } else if (po!['status'] == 'SENT') {
        label = 'PO Sent';
        tone = Tone.info;
      } else {
        label = 'PO Created';
        tone = Tone.warning;
      }
    }
    return StatusChip(label, label: label, tone: tone, dense: true);
  }
}

/// PO StatusBadge: DRAFT / ISSUED / SENT / CANCELLED.
class POStatusChip extends StatelessWidget {
  final String? status;
  const POStatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      'ISSUED' => Tone.warning,
      'SENT' => Tone.info,
      'CANCELLED' => Tone.danger,
      _ => Tone.neutral,
    };
    return StatusChip(status, label: status ?? 'DRAFT', tone: tone);
  }
}

/// Small outlined action button sized for touch (≥ 48dp tall hit area via the theme's tap target).
class SmallAction extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool filled;
  final Color? color;
  const SmallAction({super.key, required this.label, this.icon, this.onPressed, this.filled = false, this.color});

  @override
  Widget build(BuildContext context) {
    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
      Text(label),
    ]);
    if (filled) {
      return FilledButton(
        style: color == null ? null : FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
        onPressed: onPressed,
        child: child,
      );
    }
    return OutlinedButton(
      style: color == null ? null : OutlinedButton.styleFrom(foregroundColor: color),
      onPressed: onPressed,
      child: child,
    );
  }
}

/// Confirm dialog with a custom cancel label (the web's "Keep PO" / "Yes, Cancel" dialog).
Future<bool> confirmWithLabels(BuildContext context,
    {required String title, String? message, required String confirmLabel, required String cancelLabel, bool destructive = false}) async {
  final p = context.pal;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelLabel, style: TextStyle(color: p.fgMuted))),
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

/// Dashed-looking muted box for inline empty / info messages inside a section.
class InlineNote extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry margin;
  const InlineNote(this.text, {super.key, this.margin = const EdgeInsets.symmetric(horizontal: kGutter)});

  @override
  Widget build(BuildContext context) => Surface(
        margin: margin,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      );
}

/// Line-item sheet result: product picked from the catalog with quantity (and price when [withPrice]).
/// Returns `{product_id, quantity, unit_price?}`, `{'remove': true}` when the line is removed, or null.
Future<Map<String, dynamic>?> showProductLineSheet(
  BuildContext context, {
  required String title,
  required List<Map<String, dynamic>> products,
  Map<String, dynamic>? line,
  bool withPrice = true,
  bool canRemove = false,
  String productLabel = 'Product',
}) {
  return showAppSheet<Map<String, dynamic>>(context,
      title: title,
      builder: (ctx) => _ProductLineForm(
          products: products, line: line, withPrice: withPrice, canRemove: canRemove, productLabel: productLabel));
}

class _ProductLineForm extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  final Map<String, dynamic>? line;
  final bool withPrice;
  final bool canRemove;
  final String productLabel;
  const _ProductLineForm(
      {required this.products, this.line, required this.withPrice, required this.canRemove, required this.productLabel});

  @override
  State<_ProductLineForm> createState() => _ProductLineFormState();
}

class _ProductLineFormState extends State<_ProductLineForm> {
  final _form = GlobalKey<FormState>();
  int? _productId;
  late final TextEditingController _qty;
  late final TextEditingController _price;

  @override
  void initState() {
    super.initState();
    _productId = widget.line?['product_id'] as int?;
    _qty = TextEditingController(text: inputNum(widget.line?['quantity']));
    _price = TextEditingController(text: inputNum(widget.line?['unit_price']));
  }

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _product =>
      widget.products.where((p) => p['id'] == _productId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final unit = _product?['unit']?.toString() ?? '';
    final amount = toNum(_qty.text) * toNum(_price.text);
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppDropdown<int>(
          label: widget.productLabel,
          requiredField: true,
          value: _productId,
          items: [
            for (final p in widget.products)
              (
                p['id'] as int,
                widget.withPrice
                    ? '${p['name']} (${p['unit'] ?? ''})${p['default_price'] != null ? ' — ${inr(p['default_price'])}' : ''}'
                    : '${p['name']} (${p['unit'] ?? ''})'
              ),
          ],
          onChanged: (v) => setState(() {
            _productId = v;
            if (widget.withPrice) {
              final dp = _product?['default_price'];
              _price.text = dp != null ? inputNum(dp) : '';
            }
          }),
        ),
        kFieldGap,
        AppTextField(
          controller: _qty,
          label: unit.isEmpty ? 'Qty' : 'Qty ($unit)',
          number: true,
          requiredField: true,
          onChanged: (_) => setState(() {}),
          validator: (v) => toNum(v) > 0 ? null : 'Quantity must be greater than 0',
        ),
        if (widget.withPrice) ...[
          kFieldGap,
          AppTextField(
            controller: _price,
            label: 'Unit ₹',
            money: true,
            onChanged: (_) => setState(() {}),
            validator: (v) => toNum(v) < 0 ? 'Unit price cannot be negative' : null,
          ),
          const SizedBox(height: 8),
          KeyValueRow('Line total', toNum(_qty.text) > 0 ? inr(amount) : '—'),
        ],
        const SizedBox(height: 16),
        SubmitButton(
          label: widget.line == null ? 'Add' : 'Update',
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, {
              'product_id': _productId,
              'quantity': toNum(_qty.text),
              if (widget.withPrice) 'unit_price': toNum(_price.text),
            });
          },
        ),
        if (widget.canRemove) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => Navigator.pop(context, {'remove': true}),
            icon: Icon(Icons.delete_outline, color: context.pal.danger),
            label: Text('Remove line', style: TextStyle(color: context.pal.danger)),
          ),
        ],
      ]),
    );
  }
}
