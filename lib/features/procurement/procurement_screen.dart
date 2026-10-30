import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../quotations/material_requests_section.dart';
import '../quotations/project_purchase_orders.dart';
import '../quotations/quotations_section.dart';
import '../shell/routes.dart';
import 'commitment_detail_screen.dart';
import 'proc_common.dart';

/// Web: pages/ProcurementDashboardPage.jsx (route /admin/projects/:id/procurement).
/// One scrolling page, in the web's order: material requests, KPI cards (Total / Open POs / Pending act as
/// filters on the commitments list, Budget Variance opens the cost-code breakdown), commitments,
/// quotations, purchase orders.
class ProcurementScreen extends StatefulWidget {
  final int projectId;
  const ProcurementScreen({super.key, required this.projectId});

  @override
  State<ProcurementScreen> createState() => _ProcurementScreenState();
}

/// Which KPI filter is on (web search params).
enum _Filter { none, openPos, pending }

class _ProcurementScreenState extends State<ProcurementScreen> {
  _Filter _filter = _Filter.none;
  int _gen = 0; // bumps on pull-to-refresh / return from a commitment so every block reloads
  String? _projectName;

  @override
  void initState() {
    super.initState();
    _loadProject();
  }

  Future<void> _loadProject() async {
    try {
      final p = await context.read<ApiClient>().get('/projects/${widget.projectId}');
      if (mounted) setState(() => _projectName = (p as Map)['name'] as String?);
    } catch (_) {}
  }

  Map<String, dynamic> get _params => switch (_filter) {
        _Filter.openPos => {'type': 'po', 'status': 'open'},
        _Filter.pending => {'pending_approval': 'true'},
        _Filter.none => <String, dynamic>{},
      };

  Future<void> _refresh() async {
    setState(() => _gen++);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  void _setFilter(_Filter f) => setState(() => _filter = (_filter == f ? _Filter.none : f));

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final role = context.watch<AuthProvider>().user?.role;
    final pid = widget.projectId;
    final tt = Theme.of(context).textTheme;
    final p = context.pal;

    return AppScaffold(
      title: 'Commitments',
      subtitle: _projectName == null ? 'Procurement' : 'Procurement · $_projectName',
      body: RefreshList(
        onRefresh: _refresh,
        children: [
          if (['Admin', 'ProjectManager', 'Accountant', 'ProcurementOfficer'].contains(role))
            Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () => openWebPath(context, '/admin/projects/$pid?tab=subcontractors'),
                  child: const Text('Manage subcontractors →'),
                ),
              ),
            ),
          KeyedSubtree(key: ValueKey('mr$_gen'), child: MaterialRequestsSection(projectId: pid)),
          const SizedBox(height: 8),

          // ── KPI cards
          InlineAsync<Map<String, dynamic>>(
            depKey: _gen,
            load: () async => Map<String, dynamic>.from(await api.get('/projects/$pid/procurement/dashboard-summary') as Map),
            builder: (context, s, _) {
              final negVariance = toNum(s['budget_variance']) < 0;
              final dueCount = toInt(s['payments_due_count']);
              final expiring = toInt(s['expiring_insurance']);
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                KpiGrid(children: [
                  _StatCard(
                    label: 'Total Committed',
                    value: fmtSigned(s['total_committed']),
                    icon: Icons.account_balance_wallet_outlined,
                    active: _filter == _Filter.none,
                    onTap: () => setState(() => _filter = _Filter.none),
                  ),
                  _StatCard(
                    label: 'Open POs',
                    value: '${toInt(s['open_pos'])}',
                    icon: Icons.inventory_outlined,
                    variant: Tone.info,
                    active: _filter == _Filter.openPos,
                    onTap: () => _setFilter(_Filter.openPos),
                  ),
                  _StatCard(
                    label: 'Pending Approvals',
                    value: '${toInt(s['pending_approvals'])}',
                    icon: Icons.hourglass_empty,
                    variant: Tone.danger,
                    active: _filter == _Filter.pending,
                    onTap: () => _setFilter(_Filter.pending),
                  ),
                  _StatCard(
                    label: 'Payments Due${dueCount > 0 ? ' ($dueCount)' : ''}',
                    value: fmtSigned(s['payments_due']),
                    icon: Icons.currency_rupee,
                    variant: toNum(s['payments_due']) > 0 ? Tone.danger : Tone.info,
                  ),
                  _StatCard(
                    label: 'Budget Variance',
                    value: fmtSigned(s['budget_variance']),
                    icon: Icons.balance_outlined,
                    variant: negVariance ? Tone.danger : Tone.info,
                    onTap: () => _showBreakdown(context, api, pid),
                  ),
                ]),
                if (expiring > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: p.toneFill(Tone.warning),
                        border: Border.all(color: p.toneBorder(Tone.warning)),
                        borderRadius: BorderRadius.circular(Radii.control),
                      ),
                      child: Row(children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: p.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$expiring vendor${expiring > 1 ? 's' : ''} with expiring or expired insurance on this project',
                            style: tt.bodySmall?.copyWith(color: p.warning),
                          ),
                        ),
                      ]),
                    ),
                  ),
              ]);
            },
          ),

          // ── Commitments
          SectionHeader(
            'Commitments',
            trailing: _filter == _Filter.none
                ? null
                : TextButton(
                    onPressed: () => setState(() => _filter = _Filter.none),
                    child: Text(_filter == _Filter.openPos ? 'Open POs · Clear' : 'Pending · Clear'),
                  ),
          ),
          InlineAsync<List<Map<String, dynamic>>>(
            depKey: '$_gen-${_filter.name}',
            load: () async {
              final d = await api.get('/projects/$pid/procurement/commitments', params: _params);
              return asMaps((d as Map)['items']);
            },
            builder: (context, items, _) {
              if (items.isEmpty) {
                return const Surface(
                  margin: EdgeInsets.symmetric(horizontal: kGutter),
                  child: EmptyState(icon: Icons.receipt_long_outlined, title: 'No commitments found.'),
                );
              }
              return RowGroup(children: [
                for (final c in items)
                  _CommitmentRow(
                    c: c,
                    onTap: () async {
                      await push(
                          context,
                          CommitmentDetailScreen(
                              projectId: pid, type: c['type'] as String, commitmentId: toInt(c['id'])));
                      if (mounted) setState(() => _gen++);
                    },
                  ),
              ]);
            },
          ),
          const SizedBox(height: 8),
          KeyedSubtree(key: ValueKey('q$_gen'), child: QuotationsSection(projectId: pid)),
          KeyedSubtree(key: ValueKey('po$_gen'), child: ProjectPurchaseOrders(projectId: pid)),
        ],
      ),
    );
  }
}

/// The web's "Cost Code Variance" dialog.
Future<void> _showBreakdown(BuildContext context, ApiClient api, int pid) => showAppSheet<void>(
      context,
      title: 'Cost Code Variance',
      builder: (ctx) => InlineAsync<List<Map<String, dynamic>>>(
        load: () async => asMaps(await api.get('/projects/$pid/procurement/budget-breakdown')),
        builder: (ctx, rows, _) {
          final p = ctx.pal;
          final tt = Theme.of(ctx).textTheme;
          if (rows.isEmpty) return const EmptyState(icon: Icons.balance_outlined, title: 'No cost codes yet.');
          return RowGroup(margin: EdgeInsets.zero, children: [
            for (final b in rows)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text((b['cost_code'] ?? '').toString(), style: tt.titleSmall)),
                    Text(fmtSigned(b['variance']),
                        style: tabular(tt.titleSmall).copyWith(
                            fontWeight: FontWeight.w700, color: toNum(b['variance']) < 0 ? p.danger : p.success)),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(child: Text('Allocated ${fmtSigned(b['allocated'])}', style: tabular(tt.bodySmall))),
                    Text('Committed ${fmtSigned(b['committed'])}', style: tabular(tt.bodySmall)),
                  ]),
                ]),
              ),
          ]);
        },
      ),
    );

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Tone? variant; // null = the web's "default"
  final bool active;
  final VoidCallback? onTap;
  const _StatCard({required this.label, required this.value, required this.icon, this.variant, this.active = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final c = variant == null ? p.fg : p.tone(variant!);
    return Surface(
      onTap: onTap,
      borderColor: active ? c : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (variant == Tone.danger) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: p.danger, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Expanded(child: Eyebrow(label)),
          Icon(icon, size: 15, color: variant == null ? p.fgMuted : c),
        ]),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              maxLines: 1,
              style: tabular(tt.headlineSmall).copyWith(fontWeight: FontWeight.w700, color: active ? c : p.fg)),
        ),
        if (active && onTap != null) ...[
          const SizedBox(height: 4),
          Text('Filter active — tap to clear', style: tt.bodySmall?.copyWith(fontSize: 10)),
        ],
      ]),
    );
  }
}

class _CommitmentRow extends StatelessWidget {
  final Map<String, dynamic> c;
  final VoidCallback onTap;
  const _CommitmentRow({required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final cos = toNum(c['change_orders_total']);
    return RowTile(
      onTap: onTap,
      chevron: true,
      title: (c['vendor_name'] ?? '—').toString(),
      subtitleWidget: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${c['number'] ?? ''} · ${c['type'] == 'po' ? 'PO' : 'Subcontract'} · ${dash(c['cost_code'])}',
            style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Original ${fmtSigned(c['original_amount'])}'),
            const TextSpan(text: ' · COs '),
            TextSpan(text: cos != 0 ? fmtSigned(cos) : '—', style: TextStyle(color: cos != 0 ? p.accentText : null)),
          ]),
          style: tabular(tt.bodySmall),
        ),
        const SizedBox(height: 4),
        Row(children: [
          ProcStatus(c['status'] as String?, dense: true),
          if (c['pending_approval'] == true) ...[
            const SizedBox(width: 6),
            Tooltip(message: 'Pending approval', child: Icon(Icons.hourglass_empty, size: 15, color: p.warning)),
          ],
          if (c['over_budget'] == true) ...[
            const SizedBox(width: 6),
            Tooltip(message: 'Over budget', child: Icon(Icons.warning_amber_rounded, size: 15, color: p.danger)),
          ],
        ]),
      ]),
      trailing: Text(fmtSigned(c['committed_amount']), style: tabular(tt.titleSmall).copyWith(fontWeight: FontWeight.w700)),
    );
  }
}
