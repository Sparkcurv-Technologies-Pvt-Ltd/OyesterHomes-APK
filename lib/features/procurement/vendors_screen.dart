import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../shell/routes.dart';
import 'bid_comparison_screen.dart';
import 'proc_common.dart';
import 'vendor_forms.dart';

/// Web: pages/VendorsPage.jsx ("Vendors & Quotes") + components/ProductListTable.jsx.
/// The web stacks three sections (Vendor Directory, Products — Global Catalog, Bid Packages); here they are tabs.
class VendorsScreen extends StatefulWidget {
  const VendorsScreen({super.key});

  @override
  State<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends State<VendorsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)..addListener(_onTab);
  final _vendorsKey = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();
  final _productsKey = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();
  final _packagesKey = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();
  String _vendorSearch = '';
  String _productSearch = '';

  void _onTab() {
    if (!_tabs.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _editVendor(Map<String, dynamic>? v) async {
    final res = await showVendorForm(context, vendor: v);
    if (res != null) _vendorsKey.currentState?.reload();
  }

  Future<void> _editProduct(Map<String, dynamic>? p) async {
    final res = await showProductForm(context, product: p);
    if (res != null) _productsKey.currentState?.reload();
  }

  Future<void> _deleteProduct(Map<String, dynamic> p) async {
    final api = context.read<ApiClient>();
    final ok = await confirmDialog(context,
        title: 'Delete product "${p['name']}"?', confirmLabel: 'Delete', destructive: true);
    if (!ok || !mounted) return;
    final done = await runAction(context, () => api.delete('/products/${p['id']}'), success: 'Product deleted');
    if (done) _productsKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final role = user?.role;
    final canAdd = ['Admin', 'ProjectManager', 'SiteEngineer'].contains(role);
    final canManageProducts = ['Admin', 'ProjectManager', 'SiteEngineer', 'Accountant', 'ProcurementOfficer'].contains(role);
    final api = context.read<ApiClient>();

    Widget? fab;
    if (_tabs.index == 0 && canAdd) {
      fab = FloatingActionButton.extended(
        heroTag: 'add-vendor',
        onPressed: () => _editVendor(null),
        icon: const Icon(Icons.add),
        label: const Text('Add Vendor'),
      );
    } else if (_tabs.index == 1 && canManageProducts) {
      fab = FloatingActionButton.extended(
        heroTag: 'add-product',
        onPressed: () => _editProduct(null),
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      );
    }

    return Scaffold(
      floatingActionButton: fab,
      body: Column(children: [
        Material(
          color: context.pal.card,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [Tab(text: 'Vendor Directory'), Tab(text: 'Products'), Tab(text: 'Bid Packages')],
          ),
        ),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            // ── Vendor directory
            AsyncView<List<Map<String, dynamic>>>(
              key: _vendorsKey,
              load: () async => asMaps(await api.get('/vendors')),
              builder: (context, vendors, reload) {
                final q = _vendorSearch.toLowerCase();
                final shown = q.isEmpty
                    ? vendors
                    : vendors
                        .where((v) => '${v['name']} ${v['trade'] ?? ''} ${v['contact_name'] ?? ''}'.toLowerCase().contains(q))
                        .toList();
                return RefreshList(onRefresh: reload, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 4),
                    child: SearchField(hint: 'Search vendors', onChanged: (v) => setState(() => _vendorSearch = v)),
                  ),
                  const SectionHeader('Vendor Directory'),
                  if (shown.isEmpty)
                    const EmptyState(icon: Icons.local_shipping_outlined, title: 'No vendors yet.')
                  else
                    RowGroup(children: [
                      for (final v in shown) _VendorRow(v: v, onTap: canAdd ? () => _editVendor(v) : null),
                    ]),
                ]);
              },
            ),
            // ── Products — global catalog
            AsyncView<List<Map<String, dynamic>>>(
              key: _productsKey,
              load: () async => asMaps(await api.get('/products')),
              builder: (context, products, reload) {
                final q = _productSearch.toLowerCase();
                final shown = q.isEmpty
                    ? products
                    : products.where((p) => '${p['name']} ${p['category'] ?? ''}'.toLowerCase().contains(q)).toList();
                return RefreshList(onRefresh: reload, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 4),
                    child: SearchField(hint: 'Search products', onChanged: (v) => setState(() => _productSearch = v)),
                  ),
                  const SectionHeader('Products — Global Catalog'),
                  if (shown.isEmpty)
                    const EmptyState(
                        icon: Icons.inventory_2_outlined, title: 'No products in the catalog yet. Add one to start quoting.')
                  else
                    RowGroup(children: [
                      for (final p in shown)
                        _ProductRow(
                          p: p,
                          onTap: canManageProducts ? () => _editProduct(p) : null,
                          onDelete: canManageProducts ? () => _deleteProduct(p) : null,
                        ),
                    ]),
                ]);
              },
            ),
            // ── Bid packages
            AsyncView<List<Map<String, dynamic>>>(
              key: _packagesKey,
              load: () async => asMaps(await api.get('/bid-packages')),
              builder: (context, packages, reload) => RefreshList(onRefresh: reload, children: [
                const SectionHeader('Bid Packages — Quote Comparison'),
                if (packages.isEmpty)
                  const EmptyState(
                      icon: Icons.balance_outlined,
                      title: "No bid packages yet. Create them from a project's Procurement dashboard.")
                else
                  for (final bp in packages)
                    _BidPackageCard(
                      bp: bp,
                      onTap: () async {
                        await push(context, BidComparisonScreen(bidPackageId: toInt(bp['id'])));
                        _packagesKey.currentState?.reload();
                      },
                    ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _VendorRow extends StatelessWidget {
  final Map<String, dynamic> v;
  final VoidCallback? onTap;
  const _VendorRow({required this.v, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final expiring = v['insurance_expiring'] == true;
    final insTone = expiring ? p.danger : p.success;
    final contact = [v['contact_name'], v['email'], v['phone']]
        .where((e) => e != null && e.toString().isNotEmpty)
        .join(' · ');
    return RowTile(
      onTap: onTap,
      chevron: onTap != null,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: p.muted, border: Border.all(color: p.border), borderRadius: BorderRadius.circular(6)),
        child: Icon(Icons.local_shipping_outlined, size: 16, color: p.accentText),
      ),
      title: (v['name'] ?? '').toString(),
      subtitleWidget: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${v['vendor_type'] ?? ''}${v['prequalified'] == true ? ' · Prequalified' : ''} · ${dash(v['trade'])}',
            style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (contact.isNotEmpty) Text(contact, style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Row(children: [
          Icon(expiring ? Icons.gpp_maybe_outlined : Icons.verified_user_outlined, size: 14, color: insTone),
          const SizedBox(width: 4),
          Text(fmtDate(v['insurance_expiry'], empty: 'None'), style: tabular(tt.bodySmall).copyWith(color: insTone)),
          const SizedBox(width: 12),
          Icon(Icons.star_rounded, size: 14, color: p.accentText),
          const SizedBox(width: 3),
          Text(v['rating'] == null ? '—' : inputNum(v['rating']), style: tabular(tt.bodySmall)),
        ]),
      ]),
      trailing: ProcStatus(v['status'] as String?, dense: true),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final Map<String, dynamic> p;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  const _ProductRow({required this.p, this.onTap, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final tt = Theme.of(context).textTheme;
    final desc = (p['description'] ?? '').toString();
    return RowTile(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration:
            BoxDecoration(color: pal.muted, border: Border.all(color: pal.border), borderRadius: BorderRadius.circular(6)),
        child: Icon(Icons.inventory_2_outlined, size: 16, color: pal.accentText),
      ),
      title: (p['name'] ?? '').toString(),
      subtitleWidget: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (desc.isNotEmpty) Text(desc, style: tt.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
        Text('${p['unit'] ?? ''} · ${dash(p['category'])}', style: tt.bodySmall),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(p['default_price'] == null ? '—' : inr(p['default_price']),
            style: tabular(tt.titleSmall).copyWith(fontWeight: FontWeight.w700)),
        if (onDelete != null)
          IconButton(
            tooltip: 'Delete product',
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, size: 20, color: pal.danger),
          )
        else
          const SizedBox(width: 10),
      ]),
    );
  }
}

class _BidPackageCard extends StatelessWidget {
  final Map<String, dynamic> bp;
  final VoidCallback onTap;
  const _BidPackageCard({required this.bp, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final bids = toInt(bp['bid_count']);
    final lines = toInt(bp['line_item_count']);
    return Surface(
      margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.balance_outlined, size: 18, color: p.accentText),
          const Spacer(),
          ProcStatus(bp['status'] as String?, dense: true),
        ]),
        const SizedBox(height: 10),
        Text((bp['title'] ?? '').toString(), style: tt.titleMedium),
        const SizedBox(height: 3),
        Text('${bp['project_name'] ?? ''} · ${dash(bp['cost_code'])}', style: tt.bodySmall),
        const SizedBox(height: 10),
        Row(children: [
          Text('$bids bid${bids == 1 ? '' : 's'}', style: tabular(tt.bodySmall)),
          const SizedBox(width: 14),
          Text('$lines line item${lines == 1 ? '' : 's'}', style: tabular(tt.bodySmall)),
          const Spacer(),
          Text('Due ${fmtDate(bp['bid_due_date'])}', style: tabular(tt.bodySmall)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Eyebrow('Compare Quotes', color: p.accentText),
          const SizedBox(width: 4),
          Icon(Icons.arrow_forward, size: 14, color: p.accentText),
        ]),
      ]),
    );
  }
}
