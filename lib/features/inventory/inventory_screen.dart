import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../org/org_provider.dart';

part 'inv_common.dart';
part 'inv_forms.dart';
part 'inv_registers.dart';
part 'inv_manage.dart';

// Port of the web's InventoryPage.jsx (frontend/src/features/projectPlanning/pages/InventoryPage.jsx)
// on backend routers/inventory.py. Same tabs, same endpoints and payloads, same supervisor gate.
// Mobile: the Stock tab carries one-tap Receive / Issue / Transfer actions that open the cart forms
// as bottom sheets; the Receive and Issue / Transfer tabs show the same forms full height.

const _tabs = ['Stock', 'Receive', 'Issue / Transfer', 'Issue log', 'Transfers', 'Approvals', 'Materials & Locations'];

/// `?tab=` keys the backend puts in notification links (web TAB_FROM_URL), plus keys for the other tabs.
const _tabFromUrl = {
  'approvals': 'Approvals',
  'issue-log': 'Issue log',
  'transfers': 'Transfers',
  'stock': 'Stock',
  'receive': 'Receive',
  'issue': 'Issue / Transfer',
  'materials': 'Materials & Locations',
};
const _supervisorTabs = ['Approvals', 'Materials & Locations'];

/// Inventory: stock on hand, goods receipts, issues and transfers (carts), the issue log, the transfer
/// register, approvals and the material / warehouse catalog. Keep this class name and constructor.
class InventoryScreen extends StatefulWidget {
  final String? initialTab;
  const InventoryScreen({super.key, this.initialTab});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  _InvData? _data;
  Object? _error;
  String? _orgKey;
  int _gen = 0;

  /// Bumped on every write so the issue log and transfer register reload too (web invalidates their queries).
  int _rev = 0;

  Future<void> _reload() async {
    final api = context.read<ApiClient>();
    final org = context.read<OrgProvider>();
    final gen = ++_gen;
    setState(() => _error = null);
    // A failing project list only leaves names as #id on the web; it does not break the page.
    Future<dynamic> projects(Map<String, dynamic> params) =>
        api.get('/projects', params: params).catchError((_) => <String, dynamic>{'items': []});
    try {
      final r = await Future.wait([
        api.get('/inventory/materials'),
        api.get('/inventory/locations'),
        projects({'limit': 200}),
        projects({'limit': 200, ...org.orgParams}),
        api.get('/inventory/stock'),
        api.get('/inventory/movements'),
      ]);
      if (!mounted || gen != _gen) return;
      List<_Json> items(dynamic v) => _list(v is Map ? v['items'] : v);
      setState(() {
        _data = _InvData(
          materials: _list(r[0]),
          locations: _list(r[1]),
          projects: items(r[2]),
          pickable: items(r[3]),
          stock: _list(r[4]),
          movements: _list(r[5]),
        );
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() => _error = e);
      if (_data != null) showToast(context, errorText(e), error: true);
    }
  }

  /// The web's refreshAll: stock, movements, locations, materials and every register.
  Future<void> _refreshAll() {
    setState(() {
      _rev++;
    });
    return _reload();
  }

  void _openReceive(_InvData d) {
    showAppSheet<void>(
      context,
      title: 'Goods Receipt (GRN)',
      subtitle: 'Receive material into a warehouse',
      builder: (ctx) => _ReceiveForm(
        data: d,
        inSheet: true,
        onDone: () {
          Navigator.pop(ctx);
          _refreshAll();
        },
      ),
    );
  }

  void _openIssueTransfer(_InvData d, String mode) {
    showAppSheet<void>(
      context,
      title: mode == 'Issue' ? 'Issue material' : 'Transfer material',
      subtitle: 'Issue material or transfer between locations',
      builder: (ctx) => _IssueTransferForm(
        data: d,
        inSheet: true,
        initialMode: mode,
        onDone: () {
          Navigator.pop(ctx);
          _refreshAll();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final orgKey = context.watch<OrgProvider>().orgKey;
    if (orgKey != _orgKey) {
      // The project pickers follow the header's company / branch (web useProjectOptions).
      _orgKey = orgKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
    final p = context.pal;
    final isSupervisor = user?.roleIn(['Admin', 'ProjectManager', 'ProcurementOfficer']) ?? false;
    final isAdmin = user?.isAdmin ?? false;
    final visible = isSupervisor ? _tabs : _tabs.where((t) => !_supervisorTabs.contains(t)).toList();
    final want = _tabFromUrl[widget.initialTab];
    final initialIndex = want != null && visible.contains(want) ? visible.indexOf(want) : 0;
    final d = _data;

    final tabCount = <String, int>{
      if (d != null) 'Approvals': d.countBatches((m) => m['status'] == 'Pending'),
      if (d != null) 'Transfers': d.countBatches((m) => m['can_receive'] == true),
    };

    Widget page(String t) {
      final data = d!;
      switch (t) {
        case 'Stock':
          return _StockTab(
            data: data,
            onRefresh: _reload,
            onReceive: () => _openReceive(data),
            onIssue: () => _openIssueTransfer(data, 'Issue'),
            onTransfer: () => _openIssueTransfer(data, 'Transfer'),
          );
        case 'Receive':
          return _FormTab(onRefresh: _reload, child: _ReceiveForm(data: data, onDone: _refreshAll));
        case 'Issue / Transfer':
          return _FormTab(onRefresh: _reload, child: _IssueTransferForm(data: data, onDone: _refreshAll));
        case 'Issue log':
          return _IssueLog(data: data, rev: _rev);
        case 'Transfers':
          return _TransferRegister(data: data, rev: _rev, isAdmin: isAdmin, onDone: _refreshAll);
        case 'Approvals':
          return _ApprovalsList(data: data, onRefresh: _reload, onDone: _refreshAll);
        default:
          return _ManageMaterialsLocations(data: data, onRefresh: _reload, onDone: _refreshAll);
      }
    }

    Widget body;
    if (d == null && _error != null) {
      body = LayoutBuilder(
        builder: (context, c) => RefreshIndicator(
          onRefresh: _reload,
          child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
            SizedBox(
              height: c.maxHeight.isFinite ? c.maxHeight : null,
              child: Center(child: ErrorRetry(message: errorText(_error), onRetry: _reload)),
            ),
          ]),
        ),
      );
    } else if (d == null) {
      body = const LoadingView();
    } else {
      body = TabBarView(children: [for (final t in visible) page(t)]);
    }

    return Scaffold(
      body: DefaultTabController(
        key: ValueKey(visible.length),
        length: visible.length,
        initialIndex: initialIndex,
        child: Column(children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(color: p.card, border: Border(bottom: BorderSide(color: p.border))),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final t in visible) Tab(text: (tabCount[t] ?? 0) > 0 ? '$t (${tabCount[t]})' : t),
              ],
            ),
          ),
          Expanded(child: body),
        ]),
      ),
    );
  }
}

/// A form tab: the cart form, scrollable and pull-to-refresh.
class _FormTab extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  const _FormTab({required this.onRefresh, required this.child});

  @override
  Widget build(BuildContext context) => RefreshList(
        onRefresh: onRefresh,
        padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 96),
        children: [child],
      );
}

// ───────────────────────────────────────────────────────── stock

/// Stock on hand (web StockTable), grouped by material so a material's spread across stores reads at a glance.
class _StockTab extends StatefulWidget {
  final _InvData data;
  final Future<void> Function() onRefresh;
  final VoidCallback onReceive, onIssue, onTransfer;
  const _StockTab({
    required this.data,
    required this.onRefresh,
    required this.onReceive,
    required this.onIssue,
    required this.onTransfer,
  });

  @override
  State<_StockTab> createState() => _StockTabState();
}

class _StockTabState extends State<_StockTab> {
  String _locationId = '';

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final rows = d.stock.where((s) => _locationId.isEmpty || '${s['location_id']}' == _locationId).toList();

    // group by material, materials in catalog (name) order
    final groups = <int, List<_Json>>{};
    for (final s in rows) {
      groups.putIfAbsent(s['material_id'] as int, () => []).add(s);
    }
    final order = groups.keys.toList()
      ..sort((a, b) => d.materialName(a).toLowerCase().compareTo(d.materialName(b).toLowerCase()));
    double value(_Json s) => toNum(s['quantity']) * toNum(s['avg_unit_cost']);
    final total = rows.fold<double>(0, (a, s) => a + value(s));

    return RefreshList(onRefresh: widget.onRefresh, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 4),
        child: Row(children: [
          Expanded(child: _BigAction(icon: Icons.add_box_outlined, label: 'Receive', onTap: widget.onReceive)),
          const SizedBox(width: 10),
          Expanded(child: _BigAction(icon: Icons.outbox_outlined, label: 'Issue', onTap: widget.onIssue)),
          const SizedBox(width: 10),
          Expanded(child: _BigAction(icon: Icons.swap_horiz, label: 'Transfer', onTap: widget.onTransfer)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 12),
        child: _GroupedDropdown(
          label: 'Warehouse',
          value: _locationId,
          noneLabel: 'All',
          groups: _locationGroups(d),
          onChanged: (v) => setState(() => _locationId = v),
        ),
      ),
      if (rows.isNotEmpty)
        KpiGrid(children: [
          KpiTile(label: 'Stock value', value: inr(total, forceDecimals: true)),
          KpiTile(label: 'Materials', value: '${groups.length}', sub: '${rows.length} stock line${rows.length == 1 ? '' : 's'}'),
        ]),
      if (rows.isEmpty)
        EmptyState(
          icon: Icons.inventory_2_outlined,
          title: _locationId.isNotEmpty
              ? 'Nothing in stock at this location.'
              : 'No stock on hand yet. Receive material to get started.',
        ),
      for (final mid in order) ...[
        const SizedBox(height: 12),
        Builder(builder: (context) {
          final lines = groups[mid]!;
          final m = d.material(mid);
          final unit = (m?['unit'] ?? '').toString();
          final qtyTotal = lines.fold<double>(0, (a, s) => a + toNum(s['quantity']));
          final valTotal = lines.fold<double>(0, (a, s) => a + value(s));
          return RowGroup(
            header: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.materialName(mid), style: tt.titleSmall),
                    const SizedBox(height: 2),
                    Text('${dash(m?['category'])} · $unit', style: tt.bodySmall),
                  ]),
                ),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${qty(qtyTotal)} $unit', style: tabular(tt.titleMedium).copyWith(fontWeight: FontWeight.w700)),
                  Text(inr(valTotal, forceDecimals: true), style: tabular(tt.bodySmall)),
                ]),
              ]),
            ),
            children: [
              for (final s in lines)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text(d.locationName(s['location_id']), style: tt.bodyMedium, maxLines: 2)),
                      const SizedBox(width: 8),
                      Text('${qty(s['quantity'])} $unit',
                          style: tabular(tt.bodyMedium).copyWith(
                              fontWeight: FontWeight.w600, color: toNum(s['quantity']) <= 0 ? p.danger : null)),
                    ]),
                    if (lines.length > 1 && qtyTotal > 0) ...[
                      const SizedBox(height: 6),
                      LevelBar(toNum(s['quantity']) / qtyTotal),
                    ],
                    const SizedBox(height: 4),
                    Row(children: [
                      if (toNum(s['quantity']) <= 0) ...[
                        const StatusChip('OutOfStock', label: 'Out of stock', dense: true),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text('Avg ${inr(s['avg_unit_cost'], forceDecimals: true)} / $unit',
                            style: tabular(tt.bodySmall)),
                      ),
                      Text(inr(value(s), forceDecimals: true), style: tabular(tt.bodySmall).copyWith(color: p.fg)),
                    ]),
                  ]),
                ),
            ],
          );
        }),
      ],
    ]);
  }
}

/// Large one-tap action (Receive / Issue / Transfer) for use on site.
class _BigAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BigAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Surface(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 26, color: p.accentText),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}
