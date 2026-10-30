import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../auth/user.dart';
import '../boq/boq_tab.dart';
import '../change_orders/change_orders_tab.dart';
import '../finance/project_balance_sheet_tab.dart';
import '../finance/project_finance_screen.dart';
import '../labour/employees_tab.dart';
import '../labour/subcontractors_tab.dart';
import '../procurement/procurement_screen.dart';
import '../shell/routes.dart';
import 'phases_tab.dart';
import 'project_common.dart';
import 'project_form_sheet.dart';
import 'tracking_tab.dart';

/// Every tab key the web accepts in `?tab=`.
const _allTabs = ['overview', 'boq', 'phases', 'tracking', 'variations', 'employees', 'subcontractors', 'balancesheet'];

/// Who may see subcontractor money (mirrors the API; web SUB_ROLES).
const _subRoles = ['Admin', 'ProjectManager', 'Accountant', 'ProcurementOfficer'];

const _tabLabels = {
  'overview': 'Overview',
  'boq': 'BOQ',
  'phases': 'Phases',
  'tracking': 'Tracking',
  'variations': 'Change orders',
  'employees': 'Employees',
  'subcontractors': 'Subcontractors',
  'balancesheet': 'Balance sheet',
};

/// One project (web ProjectDetailPage.jsx): header with status, issues flag, location / client / company,
/// overall completion, Finance / Procurement / Edit actions, and the project tabs.
class ProjectDetailScreen extends StatefulWidget {
  final int projectId;
  final String? initialTab;
  const ProjectDetailScreen({super.key, required this.projectId, this.initialTab});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  late final ApiClient _api = context.read<ApiClient>();
  Map<String, dynamic>? _project;
  Map<int, (double, int)> _coByPhase = {};
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final role = context.read<AuthProvider>().user?.role;
    try {
      final d = await _api.get('/projects/${widget.projectId}');
      if (!mounted) return;
      setState(() {
        _project = Map<String, dynamic>.from(d as Map);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return;
    }
    if (role != 'Vendor') await _loadChangeOrders();
  }

  /// Approved change orders summed per phase (web `coByPhase`): approved_cost, else estimated_cost.
  Future<void> _loadChangeOrders() async {
    try {
      final d = await _api.get('/projects/${widget.projectId}/change-orders');
      final m = <int, (double, int)>{};
      for (final c in asMapList(d, 'change_orders')) {
        final phaseId = c['phase_id'];
        if (c['status'] == 'Approved' && phaseId is int) {
          final amt = toNum(c['approved_cost'] ?? c['estimated_cost']);
          final prev = m[phaseId] ?? (0.0, 0);
          m[phaseId] = (prev.$1 + amt, prev.$2 + 1);
        }
      }
      if (mounted) setState(() => _coByPhase = m);
    } catch (_) {
      // The variation chips are a nicety; the phases still show.
    }
  }

  List<String> _tabsFor(AppUser? user) {
    final role = user?.role;
    final isStaff = role != 'Client' && role != 'Vendor';
    return [
      'overview',
      if (isStaff) 'boq',
      'phases',
      'tracking',
      if (role != 'Vendor') 'variations',
      if (role != 'Client' && role != 'Vendor') ...[
        'employees',
        if (_subRoles.contains(role)) 'subcontractors',
        'balancesheet',
      ],
    ];
  }

  Future<void> _edit() async {
    final saved = await showProjectForm(context, project: _project);
    if (saved != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final pr = _project;
    if (pr == null) {
      return AppScaffold(
        title: 'Project',
        body: _error == null
            ? const LoadingView()
            : Center(
                child: ErrorRetry(message: 'Project not found or failed to load.\n${errorText(_error)}', onRetry: _load)),
      );
    }

    final isAdmin = user?.role == 'Admin';
    final canWrite = (user?.canWrite ?? false) &&
        (isAdmin || pr['site_engineer_id'] == user?.id || pr['project_manager_id'] == user?.id);
    final tabs = _tabsFor(user);
    final wanted = _allTabs.contains(widget.initialTab) ? widget.initialTab! : 'overview';
    final initialIndex = tabs.indexOf(wanted).clamp(0, tabs.length - 1);
    final phases = asMapList(pr['phases'] ?? const []);

    return DefaultTabController(
      length: tabs.length,
      initialIndex: initialIndex,
      child: AppScaffold(
        title: dash(pr['name']),
        subtitle: pr['client_name'] == null ? null : 'Client: ${pr['client_name']}',
        // The tab bar lives in the app bar so it stays visible; a pinned sliver tab bar inside the
        // NestedScrollView would let each tab's list slide underneath it.
        bottom: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in tabs) Tab(text: _tabLabels[t])],
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(child: _header(context, pr, user, canWrite)),
          ],
          body: TabBarView(children: [
            for (final t in tabs) _tabBody(t, pr, phases, canWrite, isAdmin),
          ]),
        ),
      ),
    );
  }

  Widget _tabBody(String t, Map<String, dynamic> pr, List<Map<String, dynamic>> phases, bool canWrite, bool isAdmin) {
    final id = widget.projectId;
    switch (t) {
      case 'overview':
        return _OverviewTab(project: pr, onRefresh: _load);
      case 'boq':
        return BoqTab(projectId: id);
      case 'phases':
        return PhasesTab(projectId: id, phases: phases, canWrite: canWrite, coByPhase: _coByPhase, onChanged: _load);
      case 'tracking':
        return TrackingTab(projectId: id, phases: phases, canWrite: canWrite, isAdmin: isAdmin, onProjectChanged: _load);
      case 'variations':
        return ChangeOrdersTab(projectId: id, phases: phases);
      case 'employees':
        return EmployeesTab(projectId: id);
      case 'subcontractors':
        return SubcontractorsTab(projectId: id);
      case 'balancesheet':
        return ProjectBalanceSheetTab(projectId: id);
    }
    return const SizedBox.shrink();
  }

  Widget _header(BuildContext context, Map<String, dynamic> pr, AppUser? user, bool canWrite) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final role = user?.role;
    final pct = toNum(pr['percent_complete']);
    final company = pr['company_name'] == null
        ? ''
        : ' · ${pr['company_name']}${pr['branch_name'] != null ? ' / ${pr['branch_name']}' : ''}';
    final showActions = canWrite || ['Accountant', 'ProcurementOfficer'].contains(role);

    return Padding(
      padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          StatusChip(pr['status'] as String?),
          if (pr['has_active_issues'] == true)
            const StatusChip('Active Issues', tone: Tone.danger),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.location_on_outlined, size: 14, color: p.fgMuted)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '${(pr['location'] ?? '').toString().isEmpty ? 'Location not set' : pr['location']} · Client: ${dash(pr['client_name'])}$company',
              style: tt.bodySmall,
            ),
          ),
        ]),
        if (showActions) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (canWrite || role == 'Accountant')
              OutlinedButton.icon(
                onPressed: () async {
                  await push(context, ProjectFinanceScreen(projectId: widget.projectId));
                  if (mounted) _load();
                },
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                label: const Text('Finance'),
              ),
            OutlinedButton.icon(
              onPressed: () async {
                await push(context, ProcurementScreen(projectId: widget.projectId));
                if (mounted) _load();
              },
              icon: const Icon(Icons.shopping_cart_outlined, size: 18),
              label: const Text('Procurement'),
            ),
            if (canWrite)
              OutlinedButton.icon(
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit Project'),
              ),
          ]),
        ],
        const SizedBox(height: 12),
        Surface(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Expanded(child: Eyebrow('Overall Completion')),
              Text('${pct.round()}%', style: tabular(tt.headlineSmall)),
            ]),
            const SizedBox(height: 10),
            LevelBar(pct / 100, tone: progressTone(pct), height: 8),
          ]),
        ),
      ]),
    );
  }
}

/// Overview tab: the web's InfoCells and the sub-contractors card.
class _OverviewTab extends StatelessWidget {
  final Map<String, dynamic> project;
  final Future<void> Function() onRefresh;
  const _OverviewTab({required this.project, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final pr = project;
    Widget cell(IconData icon, String label, String? value, {bool figure = false}) => Surface(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 13, color: context.pal.fgSubtle),
              const SizedBox(width: 6),
              Expanded(child: Eyebrow(label)),
            ]),
            const SizedBox(height: 8),
            Text(dash(value),
                style: figure
                    ? tabular(Theme.of(context).textTheme.titleMedium)
                    : Theme.of(context).textTheme.titleSmall),
          ]),
        );

    final subs = asMapList(pr['subcontractors'] ?? const []);
    return RefreshList(
      onRefresh: onRefresh,
      padding: const EdgeInsets.only(top: 12, bottom: 96),
      children: [
        KpiGrid(children: [
          cell(Icons.currency_rupee, 'Budget', fmtBudget(pr['budget']), figure: true),
          cell(Icons.people_outline, 'Client', pr['client_name']?.toString()),
          cell(Icons.person_outline, 'Project Manager', pr['project_manager_name']?.toString()),
          cell(Icons.person_outline, 'Site Engineer', pr['site_engineer_name']?.toString()),
          cell(Icons.calendar_today_outlined, 'Planned Start', fmtDate(pr['start_date_planned'], empty: ''), figure: true),
          cell(Icons.calendar_today_outlined, 'Planned End', fmtDate(pr['end_date_planned'], empty: ''), figure: true),
          cell(Icons.calendar_today_outlined, 'Actual Start', fmtDate(pr['start_date_actual'], empty: ''), figure: true),
        ]),
        const SizedBox(height: 16),
        _SubcontractorsCard(subs: subs),
      ],
    );
  }
}

class _SubcontractorsCard extends StatelessWidget {
  final List<Map<String, dynamic>> subs;
  const _SubcontractorsCard({required this.subs});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final total = subs.fold<double>(0, (s, x) => s + toNum(x['allocated_amount']));
    return RowGroup(
      header: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Eyebrow('Sub-Contractors'),
          const SizedBox(height: 4),
          Text.rich(TextSpan(children: [
            TextSpan(text: '${subs.length} allocated', style: tt.titleMedium),
            if (subs.isNotEmpty) TextSpan(text: '  · ${inr(total)} total', style: tabular(tt.bodySmall)),
          ])),
        ]),
      ),
      children: subs.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('None allocated yet. Use "Edit Project" to add sub-contractors, budgets and materials.',
                    textAlign: TextAlign.center, style: tt.bodySmall),
              ),
            ]
          : [
              for (final s in subs)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(dash(s['type']), style: tt.titleSmall),
                          Text(dash(s['name']), style: tt.bodySmall),
                        ]),
                      ),
                      Text(inr(s['allocated_amount']), style: tabular(tt.titleSmall)),
                    ]),
                    if (((s['materials'] as List?) ?? const []).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final m in (s['materials'] as List)) TagChip(m.toString()),
                      ]),
                    ],
                    if ((s['notes'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(s['notes'].toString(), style: tt.bodySmall?.copyWith(color: p.fgMuted)),
                    ],
                  ]),
                ),
            ],
    );
  }
}
