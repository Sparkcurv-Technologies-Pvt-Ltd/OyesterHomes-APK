import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../procurement/vendor_forms.dart';
import '../shell/routes.dart';
import '_shared.dart';
import 'purchase_order_screen.dart';
import 'quotation_detail_screen.dart';

/// Vendor quotations on a project (web QuotationsSection.jsx + MakeQuotationModal.jsx).
/// A non-scrolling Column: the procurement screen places it inside its own list.
class QuotationsSection extends StatefulWidget {
  final int projectId;
  const QuotationsSection({super.key, required this.projectId});

  @override
  State<QuotationsSection> createState() => _QuotationsSectionState();
}

class _QuotationsSectionState extends State<QuotationsSection> {
  final _loader = GlobalKey<InlineAsyncState<List<Map<String, dynamic>>>>();

  Future<void> _reload() async => _loader.currentState?.reload();

  Future<void> _openDetail(int quotationId) async {
    await push(context, QuotationDetailScreen(projectId: widget.projectId, quotationId: quotationId));
    _reload();
  }

  Future<void> _openPO(int quotationId) async {
    await push(context, PurchaseOrderScreen(projectId: widget.projectId, quotationId: quotationId));
    _reload();
  }

  Future<void> _make() async {
    final created = await showAppSheet<Map<String, dynamic>>(context,
        title: 'Make Quotation',
        subtitle: 'Pick a vendor, then add product line items from the global catalog.',
        builder: (ctx) => _MakeQuotationForm(projectId: widget.projectId));
    if (created == null || !mounted) return;
    _reload();
    _openDetail(created['id'] as int);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final canCreate = user?.roleIn(['Admin', 'ProcurementOfficer', 'ProjectManager', 'SiteEngineer', 'Accountant']) ?? false;
    final canCreatePO = user?.roleIn(['Admin', 'ProjectManager', 'ProcurementOfficer', 'Accountant']) ?? false;
    final api = context.read<ApiClient>();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SectionHeader('Vendor Quotations',
          trailing: canCreate
              ? FilledButton.icon(onPressed: _make, icon: const Icon(Icons.add, size: 18), label: const Text('Make Quotation'))
              : null),
      InlineAsync<List<Map<String, dynamic>>>(
        key: _loader,
        load: () async => asMaps(await api.get('/projects/${widget.projectId}/quotations')),
        builder: (context, rows, reload) {
          if (rows.isEmpty) return const InlineNote('No quotations yet. Make one from the global product catalog.');
          return RowGroup(children: [
            for (final q in rows) _QuotationRow(q: q, canCreatePO: canCreatePO, onOpen: _openDetail, onPO: _openPO),
          ]);
        },
      ),
    ]);
  }
}

class _QuotationRow extends StatelessWidget {
  final Map<String, dynamic> q;
  final bool canCreatePO;
  final void Function(int) onOpen;
  final void Function(int) onPO;
  const _QuotationRow({required this.q, required this.canCreatePO, required this.onOpen, required this.onPO});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final po = asMap(q['purchase_order']);
    final id = q['id'] as int;
    final hasLivePO = po != null && po['status'] != 'CANCELLED';
    return RowTile(
      onTap: () => onOpen(id),
      chevron: true,
      leading: Icon(Icons.description_outlined, size: 20, color: p.accentText),
      title: dash(q['quotation_number']),
      subtitleWidget: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${dash(q['vendor_name'])} · ${fmtDate(q['quotation_date'])}', style: tt.bodySmall),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          QuotationStatusChip(q['status'] as String?, dense: true),
          QuotationPOChip(po),
        ]),
        if (canCreatePO) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => onPO(id),
              icon: const Icon(Icons.fact_check_outlined, size: 16),
              label: Text(hasLivePO ? 'Open PO' : 'Purchase Order'),
            ),
          ),
        ],
      ]),
      trailing: Text(inr(q['quotation_total']), style: tabular(tt.titleSmall).copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

/// MakeQuotationModal: vendor, valid until, product line items → POST /projects/{id}/quotations.
class _MakeQuotationForm extends StatefulWidget {
  final int projectId;
  const _MakeQuotationForm({required this.projectId});

  @override
  State<_MakeQuotationForm> createState() => _MakeQuotationFormState();
}

class _MakeQuotationFormState extends State<_MakeQuotationForm> {
  List<Map<String, dynamic>>? _vendors;
  List<Map<String, dynamic>>? _products;
  Object? _error;
  int? _vendorId;
  String? _validUntil;
  final List<Map<String, dynamic>> _rows = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait([api.get('/vendors'), api.get('/products')]);
      if (!mounted) return;
      setState(() {
        _vendors = asMaps(res[0]);
        _products = asMaps(res[1]);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Map<String, dynamic>? _product(int? id) => (_products ?? []).where((p) => p['id'] == id).firstOrNull;

  double get _total => _rows.fold(0.0, (s, r) {
        final q = toNum(r['quantity']);
        final up = toNum(r['unit_price']);
        return s + (q > 0 && up >= 0 ? q * up : 0);
      });

  Future<void> _editRow([int? index]) async {
    final res = await showProductLineSheet(context,
        title: index == null ? 'Add Line Item' : 'Edit Line Item',
        products: _products ?? [],
        line: index == null ? null : _rows[index],
        canRemove: index != null);
    if (res == null || !mounted) return;
    setState(() {
      if (res['remove'] == true) {
        _rows.removeAt(index!);
      } else if (index == null) {
        _rows.add(res);
      } else {
        _rows[index] = res;
      }
    });
  }

  Future<void> _newVendor() async {
    final v = await showVendorForm(context);
    if (v == null || !mounted) return;
    await _load();
    if (mounted && v['id'] is int) setState(() => _vendorId = v['id'] as int);
  }

  Future<void> _newProduct() async {
    final p = await showProductForm(context);
    if (p == null || !mounted) return;
    await _load();
  }

  Future<void> _submit() async {
    if (_vendorId == null) {
      showToast(context, 'Select a vendor', error: true);
      return;
    }
    final items = _rows
        .where((r) => r['product_id'] != null && toNum(r['quantity']) > 0)
        .map((r) => {
              'product_id': r['product_id'],
              'quantity': toNum(r['quantity']),
              'unit_price': toNum(r['unit_price']),
              'notes': null,
            })
        .toList();
    if (items.isEmpty) {
      showToast(context, 'Add at least one line item with product and quantity', error: true);
      return;
    }
    setState(() => _saving = true);
    final api = context.read<ApiClient>();
    try {
      final res = await api.post('/projects/${widget.projectId}/quotations',
          data: {'vendor_id': _vendorId, 'valid_until': _validUntil, 'line_items': items});
      if (!mounted) return;
      final q = Map<String, dynamic>.from(res as Map);
      showToast(context, 'Quotation ${q['quotation_number']} created');
      Navigator.pop(context, q);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(message: errorText(_error), onRetry: _load);
    if (_vendors == null || _products == null) return const LoadingView();
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppDropdown<int>(
        label: 'Vendor',
        requiredField: true,
        hint: 'Select vendor…',
        value: _vendorId,
        items: [for (final v in _vendors!) (v['id'] as int, '${v['name']} — ${v['trade'] ?? v['vendor_type'] ?? ''}')],
        onChanged: (v) {
          if (v != null) setState(() => _vendorId = v);
        },
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(onPressed: _newVendor, child: Text('+ New vendor', style: TextStyle(color: p.accentText))),
      ),
      DateField(label: 'Valid Until', value: _validUntil, onChanged: (v) => setState(() => _validUntil = v)),
      const SizedBox(height: 18),
      const Eyebrow('Line items'),
      const SizedBox(height: 8),
      if (_products!.isEmpty)
        const InlineNote('No products in the catalog yet — use + New product below.', margin: EdgeInsets.zero)
      else if (_rows.isEmpty)
        const InlineNote('No line items yet.', margin: EdgeInsets.zero)
      else
        RowGroup(margin: EdgeInsets.zero, children: [
          for (var i = 0; i < _rows.length; i++)
            RowTile(
              onTap: () => _editRow(i),
              title: dash(_product(_rows[i]['product_id'] as int?)?['name']),
              subtitle:
                  '${qty(_rows[i]['quantity'])} ${_product(_rows[i]['product_id'] as int?)?['unit'] ?? ''} × ${inr(_rows[i]['unit_price'])}',
              trailing: Text(
                toNum(_rows[i]['quantity']) > 0 ? inr(toNum(_rows[i]['quantity']) * toNum(_rows[i]['unit_price'])) : '—',
                style: tabular(tt.titleSmall),
              ),
            ),
        ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
              onPressed: () => _editRow(), icon: const Icon(Icons.add, size: 18), label: const Text('Add Line Item')),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(onPressed: _newProduct, icon: const Icon(Icons.add, size: 18), label: const Text('New product')),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Text('Total', style: tt.bodyMedium),
        const Spacer(),
        Text(inr(_total), style: tabular(tt.headlineSmall).copyWith(color: p.accentText)),
      ]),
      const SizedBox(height: 14),
      SubmitButton(label: 'Create Quotation', busy: _saving, onPressed: _submit),
    ]);
  }
}
