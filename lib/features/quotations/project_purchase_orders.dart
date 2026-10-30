import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../shell/routes.dart';
import '_shared.dart';
import 'purchase_order_screen.dart';

/// Issued and sent purchase orders made from vendor quotations, with what has been paid against each
/// (web ProjectPurchaseOrders.jsx). A non-scrolling Column placed inside the procurement screen's list.
class ProjectPurchaseOrders extends StatefulWidget {
  final int projectId;
  const ProjectPurchaseOrders({super.key, required this.projectId});

  @override
  State<ProjectPurchaseOrders> createState() => _ProjectPurchaseOrdersState();
}

class _ProjectPurchaseOrdersState extends State<ProjectPurchaseOrders> {
  final _loader = GlobalKey<InlineAsyncState<Map<String, dynamic>>>();

  String _money(dynamic v) => inr((toNum(v) * 100).round() / 100);

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const SectionHeader('Purchase orders to vendors'),
      InlineAsync<Map<String, dynamic>>(
        key: _loader,
        load: () async => asMap(await api.get('/projects/${widget.projectId}/vendor-purchase-orders')) ?? {},
        builder: (context, data, reload) {
          final rows = asMaps(data['purchase_orders']);
          final totals = asMap(data['totals']);
          if (rows.isEmpty) return const InlineNote('No issued purchase orders on this project.');
          return RowGroup(
            footer: totals == null
                ? null
                : Container(
                    color: p.muted,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Column(children: [
                      KeyValueRow('Total', _money(totals['grand_total']), padding: const EdgeInsets.symmetric(vertical: 3)),
                      KeyValueRow('Paid', _money(totals['paid']), padding: const EdgeInsets.symmetric(vertical: 3)),
                      KeyValueRow('Balance due', _money(totals['balance_due']),
                          strong: true, valueColor: p.danger, padding: const EdgeInsets.symmetric(vertical: 3)),
                    ]),
                  ),
            children: [
              for (final po in rows)
                RowTile(
                  chevron: true,
                  onTap: () async {
                    await push(context, PurchaseOrderScreen(projectId: widget.projectId, quotationId: po['quotation_id'] as int));
                    reload();
                  },
                  title: dash(po['po_number']),
                  subtitleWidget: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(dash(po['vendor_name']), style: tt.bodySmall),
                    const SizedBox(height: 5),
                    POStatusChip(po['status'] as String?),
                  ]),
                  trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    Text(_money(po['grand_total']), style: tabular(tt.titleSmall)),
                    const SizedBox(height: 2),
                    Text('Paid ${_money(po['paid'])}', style: tabular(tt.bodySmall)),
                    const SizedBox(height: 2),
                    Text('Due ${_money(po['balance_due'])}',
                        style: tabular(tt.bodySmall).copyWith(color: p.danger, fontWeight: FontWeight.w600)),
                  ]),
                ),
            ],
          );
        },
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 0),
        child: Text('Payments made to vendors against these orders count as vendor payments in the balance sheet.',
            style: tt.bodySmall),
      ),
    ]);
  }
}
