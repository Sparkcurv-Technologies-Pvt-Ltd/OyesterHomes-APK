import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../org/org_provider.dart';
import '../projects/project_common.dart';
import '../projects/project_tile.dart';
import '../shell/routes.dart';
import 'admin_control_centre.dart';
import 'dashboard_charts.dart';

const _statusOrder = ['Planning', 'Ongoing', 'OnHold', 'Completed', 'Cancelled'];
const _barColors = <String, Color>{
  'Planning': Color(0xFF0EA5E9),
  'Ongoing': Color(0xFFF59E0B),
  'OnHold': Color(0xFF8B5CF6),
  'Completed': Color(0xFF10B981),
  'Cancelled': Color(0xFFEF4444),
};
const _stageColors = [Color(0xFFD1A658), Color(0xFFF59E0B), Color(0xFF10B981), Color(0xFF8B5CF6), Color(0xFF64748B), Color(0xFF0EA5E9)];
const _statusLabel = {'OnHold': 'On hold'};
const _green = Color(0xFF10B981), _amber = Color(0xFFF59E0B), _red = Color(0xFFEF4444);

String _pctSigned(double v) => '${v > 0 ? '+' : ''}${v.round()}%';

class _DashData {
  final Map<String, dynamic>? stats;
  final Map<String, dynamic> charts;
  final List<Map<String, dynamic>> recent;
  final Map<String, dynamic>? overview;
  const _DashData(this.stats, this.charts, this.recent, this.overview);
}

/// Command Center (web DashboardPage.jsx). The Admin gets the control centre (AdminControlCentre.jsx)
/// in place of the four KPI cards; everyone gets the portfolio charts and recent projects.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _view = GlobalKey<AsyncViewState<_DashData>>();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // The web refetches the Admin overview every minute.
    if (context.read<AuthProvider>().user?.role == 'Admin') {
      _timer = Timer.periodic(const Duration(seconds: 60), (_) => _view.currentState?.reload());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<_DashData> _load(bool isAdmin, Map<String, dynamic> orgParams) async {
    final api = context.read<ApiClient>();
    Future<Map<String, dynamic>?> soft(String path, [Map<String, dynamic>? params]) async {
      try {
        return Map<String, dynamic>.from(await api.get(path, params: params) as Map);
      } catch (_) {
        return null;
      }
    }

    final res = await Future.wait<dynamic>([
      soft('/stats', orgParams),
      api.get('/projects/dashboard-charts', params: orgParams),
      soft('/projects', {...orgParams, 'limit': 5}),
      isAdmin ? api.get('/dashboard/overview', params: orgParams) : Future.value(null),
    ]);
    return _DashData(
      res[0] as Map<String, dynamic>?,
      Map<String, dynamic>.from(res[1] as Map),
      asMapList(res[2]),
      res[3] == null ? null : Map<String, dynamic>.from(res[3] as Map),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final org = context.watch<OrgProvider>();
    final isAdmin = user?.role == 'Admin';
    final params = org.orgParams;
    return Scaffold(
      body: AsyncView<_DashData>(
        key: _view,
        depKey: '${org.orgKey}|${user?.id}',
        load: () => _load(isAdmin, params),
        builder: (context, d, reload) => RefreshList(
          onRefresh: reload,
          children: _content(context, d, user?.name, isAdmin, reload),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, _DashData d, String? name, bool isAdmin, Future<void> Function() reload) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final first = (name ?? '').trim().split(RegExp(r'\s+')).first;
    final stats = d.stats;
    final byStatus = (stats?['by_status'] as Map?) ?? const {};
    final charts = d.charts;
    final pp = (charts['portfolio_progress'] as Map?) ?? const {};
    final ms = (charts['milestones'] as Map?) ?? const {};

    final statusBars = [
      for (final s in _statusOrder) ChartDatum(s, toNum(byStatus[s]), _barColors[s]!, label: _statusLabel[s] ?? s),
    ];
    final stages = asMapList(charts['stages'] ?? const []);
    final stageBars = [
      for (var i = 0; i < stages.length; i++)
        ChartDatum(stages[i]['stage'].toString(), toNum(stages[i]['count']), _stageColors[i % _stageColors.length]),
    ];
    final variance = asMapList(charts['schedule_variance'] ?? const []);
    final varianceBars = [
      for (final v in variance)
        ChartDatum('${v['id']}', toNum(v['variance']), toNum(v['variance']) >= 0 ? _green : _red, label: v['name']?.toString()),
    ];
    final msDonut = [
      ChartDatum('Completed', toNum(ms['completed']), _green),
      ChartDatum('Pending', toNum(ms['pending']), _amber),
      ChartDatum('Overdue', toNum(ms['overdue']), _red),
    ];
    final upcoming = asMapList(ms['upcoming'] ?? const []).take(4).toList();

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Eyebrow('Command Center', color: p.accentText),
          const SizedBox(height: 4),
          Text('Welcome back, $first', style: tt.headlineMedium),
        ]),
      ),
      if (isAdmin && d.overview != null)
        AdminControlCentre(overview: d.overview!, onRefresh: reload)
      else if (!isAdmin) ...[
        KpiGrid(children: [
          KpiTile(label: 'Total Projects', value: '${stats?['total_projects'] ?? 0}', icon: Icons.apartment_outlined),
          KpiTile(label: 'Ongoing', value: '${byStatus['Ongoing'] ?? 0}', icon: Icons.check_circle_outline),
          KpiTile(label: 'Completed', value: '${byStatus['Completed'] ?? 0}', icon: Icons.check_circle_outline),
          KpiTile(
            label: 'With Issues',
            value: '${stats?['projects_with_issues'] ?? 0}',
            icon: Icons.warning_amber_rounded,
            tone: toInt(stats?['projects_with_issues']) > 0 ? Tone.danger : null,
          ),
          KpiTile(label: 'Total Budget', value: stats == null ? '—' : inr(stats['total_budget']), icon: Icons.currency_rupee),
        ]),
        const SizedBox(height: 12),
      ],

      // 1. Overall portfolio progress
      _Card(
        title: 'Overall Portfolio Progress',
        child: Column(children: [
          const SizedBox(height: 8),
          HalfGauge(
            value: toNum(pp['avg_pct']),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${pp['avg_pct'] ?? 0}%', style: tabular(tt.headlineLarge).copyWith(color: p.accentText, fontSize: 34)),
              const Eyebrow('Avg Completion'),
            ]),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: p.border),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _Figure(value: '${pp['total'] ?? 0}', label: 'Projects')),
            Expanded(child: _Figure(value: '${pp['completed'] ?? 0}', label: 'Completed', color: p.success)),
          ]),
        ]),
      ),

      // 3. Project status breakdown
      _Card(title: 'Projects by Status', child: HBarChart(data: statusBars)),

      // 6. Projects by stage
      _Card(
        title: 'Projects by Stage',
        child: stageBars.isEmpty
            ? const _NoData()
            : VBarChart(data: stageBars, height: 220, integer: true),
      ),

      // 2. Gantt / timeline
      _Card(title: 'Project Timeline (Gantt)', child: GanttChart(timeline: asMapList(charts['timeline'] ?? const []), colors: _barColors)),

      // 5. Milestone completion tracker
      _Card(
        title: 'Milestone Tracker',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            DonutChart(
              data: msDonut,
              size: 110,
              center: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${ms['total'] ?? 0}', style: tabular(tt.titleLarge).copyWith(fontWeight: FontWeight.w700)),
                Text('TOTAL', style: tt.labelSmall?.copyWith(fontSize: 9)),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final m in msDonut)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: m.color, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 8),
                      Text('${m.value.round()} ${m.label}', style: tabular(tt.bodySmall)),
                    ]),
                  ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Divider(height: 1, color: p.border),
          const SizedBox(height: 8),
          if (upcoming.isEmpty)
            Text('No upcoming milestones.', style: tt.bodySmall)
          else
            for (final m in upcoming)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(Icons.flag_outlined, size: 14, color: m['overdue'] == true ? p.danger : p.warning),
                  const SizedBox(width: 6),
                  Expanded(child: Text(dash(m['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall)),
                  const SizedBox(width: 6),
                  Text(fmtDate(m['due_date']),
                      style: tabular(tt.bodySmall).copyWith(color: m['overdue'] == true ? p.danger : null)),
                ]),
              ),
        ]),
      ),

      // 4. Schedule variance
      _Card(
        title: 'Schedule Variance (Actual − Expected %)',
        child: varianceBars.isEmpty
            ? const _NoData()
            : VBarChart(data: varianceBars, height: 220, signed: true, format: _pctSigned),
      ),

      SectionHeader(
        'Recent Projects',
        padding: const EdgeInsets.fromLTRB(kGutter, 8, 8, 4),
        trailing: TextButton(
          style: TextButton.styleFrom(foregroundColor: p.accentText),
          onPressed: () => openWebPath(context, '/admin/projects'),
          child: const Text('VIEW ALL →'),
        ),
      ),
      if (d.recent.isEmpty)
        const EmptyState(icon: Icons.apartment_outlined, title: 'No projects found.')
      else
        for (final pr in d.recent)
          Padding(padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10), child: ProjectTile(project: pr)),
    ];
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Surface(
        margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Eyebrow(title),
          const SizedBox(height: 14),
          child,
        ]),
      );
}

class _Figure extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;
  const _Figure({required this.value, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(children: [
      Text(value, style: tabular(tt.titleLarge).copyWith(fontWeight: FontWeight.w700, color: color)),
      Eyebrow(label),
    ]);
  }
}

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(child: Text('No data yet.', style: Theme.of(context).textTheme.bodySmall)),
      );
}
