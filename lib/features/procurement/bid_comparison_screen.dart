import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import 'proc_common.dart';

/// Web: pages/BidComparisonPage.jsx + components/BestValueBadge.jsx
/// (route /admin/procurement/bid-packages/:id/comparison).
/// On a phone the comparison table becomes: one card of bid totals per vendor (with the award buttons),
/// then one card per line item listing each vendor's price, the best one marked.
class BidComparisonScreen extends StatefulWidget {
  final int bidPackageId;
  const BidComparisonScreen({super.key, required this.bidPackageId});

  @override
  State<BidComparisonScreen> createState() => _BidComparisonScreenState();
}

class _BidComparisonScreenState extends State<BidComparisonScreen> {
  final _key = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  Map<String, dynamic>? _data;

  Future<Map<String, dynamic>> _load() async {
    final d = Map<String, dynamic>.from(
        await context.read<ApiClient>().get('/bid-packages/${widget.bidPackageId}/comparison') as Map);
    if (mounted) setState(() => _data = d);
    return d;
  }

  Future<void> _award(Map<String, dynamic> data, Map<String, dynamic> v, String type) async {
    final api = context.read<ApiClient>();
    final ok = await confirmDialog(context,
        title: 'Award bid',
        message:
            'Award "${data['title']}" to ${v['vendor_name']} as ${type == 'po' ? 'a Purchase Order' : 'a Subcontract'}?',
        confirmLabel: 'Award');
    if (!ok || !mounted) return;
    final done = await runAction(
      context,
      () => api.post('/bid-packages/${widget.bidPackageId}/award', data: {'bid_id': v['bid_id'], 'commitment_type': type}),
      success: 'Awarded to ${v['vendor_name']}',
    );
    if (done) _key.currentState?.reload();
  }

  Future<void> _addLineItem() async {
    final api = context.read<ApiClient>();
    final added = await showAppSheet<bool>(
      context,
      title: 'Line Item',
      subtitle: 'Add a line item vendors can quote against.',
      builder: (ctx) => _LineItemForm(api: api, bidPackageId: widget.bidPackageId),
    );
    if (added == true) {
      if (mounted) showToast(context, 'Line item added');
      _key.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final isAdmin = user?.isAdmin ?? false;
    final canEdit = ['Admin', 'ProjectManager', 'SiteEngineer', 'ProcurementOfficer'].contains(user?.role);
    final data = _data;
    return AppScaffold(
      title: data == null ? 'Quote Comparison' : (data['title'] ?? '—').toString(),
      subtitle: 'Quote Comparison',
      fab: canEdit && data != null && data['status'] != 'Awarded'
          ? FloatingActionButton.extended(
              onPressed: _addLineItem,
              icon: const Icon(Icons.add),
              label: const Text('Line Item'),
            )
          : null,
      body: AsyncView<Map<String, dynamic>>(
        key: _key,
        load: _load,
        builder: (context, data, reload) {
          final vendors = asMaps(data['vendors']);
          final lines = asMaps(data['line_items']);
          final tt = Theme.of(context).textTheme;
          final positive = vendors.map((v) => toNum(v['total'])).where((t) => t > 0);
          final bestTotal = positive.isEmpty ? null : positive.reduce((a, b) => a < b ? a : b);
          final canAward = isAdmin && data['status'] != 'Awarded';
          return RefreshList(onRefresh: reload, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 4),
              child: Row(children: [
                ProcStatus(data['status'] as String?),
                const SizedBox(width: 10),
                Text('Bids due ${fmtDate(data['bid_due_date'])}', style: tabular(tt.bodySmall)),
              ]),
            ),
            if (vendors.isEmpty)
              const EmptyState(icon: Icons.balance_outlined, title: 'No bids submitted yet for this package.')
            else ...[
              const SectionHeader('Bid Total'),
              RowGroup(children: [
                for (final v in vendors)
                  _VendorTotal(
                    v: v,
                    best: bestTotal != null && toNum(v['total']) == bestTotal,
                    canAward: canAward && v['status'] != 'Awarded',
                    onAward: (type) => _award(data, v, type),
                  ),
              ]),
              SectionHeader('Line Items (${lines.length})'),
              if (lines.isEmpty)
                const EmptyState(icon: Icons.list_alt_outlined, title: 'No line items yet.')
              else
                for (final li in lines) _LineCard(li: li, vendors: vendors),
            ],
          ]);
        },
      ),
    );
  }
}

/// The web's BestValueBadge.
class BestValueBadge extends StatelessWidget {
  const BestValueBadge({super.key});

  @override
  Widget build(BuildContext context) => const StatusChip('best', label: 'Best', tone: Tone.success, dense: true);
}

class _VendorTotal extends StatelessWidget {
  final Map<String, dynamic> v;
  final bool best;
  final bool canAward;
  final void Function(String type) onAward;
  const _VendorTotal({required this.v, required this.best, required this.canAward, required this.onAward});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final awarded = v['status'] == 'Awarded';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((v['vendor_name'] ?? '—').toString(), style: tt.titleSmall),
              const SizedBox(height: 4),
              ProcStatus(v['status'] as String?, dense: true),
            ]),
          ),
          Text(inr(v['total']),
              style: tabular(tt.titleLarge).copyWith(fontWeight: FontWeight.w700, color: best ? p.success : p.fg)),
        ]),
        if (canAward) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: SmallAction(label: 'Award PO', tone: Tone.accent, onPressed: () => onAward('po'))),
            const SizedBox(width: 8),
            Expanded(child: SmallAction(label: 'Award Sub', onPressed: () => onAward('subcontract'))),
          ]),
        ],
        if (awarded) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.military_tech_outlined, size: 15, color: p.success),
            const SizedBox(width: 4),
            Eyebrow('Awarded', color: p.success),
          ]),
        ],
      ]),
    );
  }
}

class _LineCard extends StatelessWidget {
  final Map<String, dynamic> li;
  final List<Map<String, dynamic>> vendors;
  const _LineCard({required this.li, required this.vendors});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final quotes = asMaps(li['quotes']);
    return Surface(
      margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((li['item_description'] ?? '').toString(), style: tt.titleSmall),
            const SizedBox(height: 2),
            Text('${qty(li['quantity_required'])} ${li['unit'] ?? ''} · ${dash(li['cost_code'])}',
                style: tabular(tt.bodySmall)),
          ]),
        ),
        for (final v in vendors) ...[
          Divider(height: 1, color: p.border),
          Builder(builder: (context) {
            Map<String, dynamic>? q;
            for (final x in quotes) {
              if (x['bid_id'] == v['bid_id']) q = x;
            }
            final isBest = q?['is_best'] == true;
            return Container(
              color: isBest ? p.toneFill(Tone.success) : null,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Text((v['vendor_name'] ?? '—').toString(),
                      style: tt.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (q == null)
                  Text('No quote', style: tt.bodySmall?.copyWith(color: p.fgSubtle))
                else
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (isBest) ...[const BestValueBadge(), const SizedBox(width: 6)],
                      Text(inr(q['unit_price']),
                          style: tabular(tt.titleSmall)
                              .copyWith(fontWeight: FontWeight.w700, color: isBest ? p.success : p.fg)),
                    ]),
                    Text(
                      'Total ${inr(q['line_total'])}${q['lead_time_days'] != null ? ' · ${q['lead_time_days']}d lead' : ''}',
                      style: tabular(tt.bodySmall),
                    ),
                  ]),
              ]),
            );
          }),
        ],
      ]),
    );
  }
}

class _LineItemForm extends StatefulWidget {
  final ApiClient api;
  final int bidPackageId;
  const _LineItemForm({required this.api, required this.bidPackageId});

  @override
  State<_LineItemForm> createState() => _LineItemFormState();
}

class _LineItemFormState extends State<_LineItemForm> {
  final _desc = TextEditingController();
  final _unit = TextEditingController();
  final _qty = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _desc.dispose();
    _unit.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.post('/bid-packages/${widget.bidPackageId}/line-items', data: {
        'item_description': _desc.text,
        'unit': _unit.text.isEmpty ? null : _unit.text,
        'quantity_required': _qty.text.isNotEmpty ? toNum(_qty.text) : 0,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorText(e));
        showToast(context, errorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTextField(
          controller: _desc, label: 'Line item description', autofocus: true, onChanged: (_) => setState(() {})),
      kFieldGap,
      Row(children: [
        Expanded(child: AppTextField(controller: _unit, label: 'Unit')),
        const SizedBox(width: 12),
        Expanded(child: AppTextField(controller: _qty, label: 'Qty', number: true)),
      ]),
      const SizedBox(height: 20),
      SheetError(_error),
      SubmitButton(
        label: 'Line Item',
        icon: Icons.add,
        busy: _saving,
        onPressed: _desc.text.isEmpty ? null : _submit,
      ),
    ]);
  }
}
