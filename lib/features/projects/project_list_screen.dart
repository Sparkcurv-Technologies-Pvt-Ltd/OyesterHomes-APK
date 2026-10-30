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
import '../shell/routes.dart';
import 'project_common.dart';
import 'project_detail_screen.dart';
import 'project_form_sheet.dart';
import 'project_tile.dart';

const _pageSize = 10;

/// Projects (web ProjectListPage.jsx + ProjectTable.jsx): KPI cards that double as filters, search,
/// client / status / engineer filters, paged list, budget breakdown, and "New Project" for the Admin.
class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // Filters (the web keeps these in the URL).
  String _search = '';
  String? _status;
  int? _clientId;
  int? _engineerId;
  bool _hasIssues = false;
  int _offset = 0;

  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _data;
  Object? _error;
  bool _loading = true;
  int _gen = 0;
  String? _orgKey;

  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _engineers = [];

  late final ApiClient _api = context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    if (user?.canWrite == true) _loadPickers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final key = Provider.of<OrgProvider>(context).orgKey;
    if (key != _orgKey) {
      _orgKey = key;
      _offset = 0;
      Future.microtask(_reload);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPickers() async {
    try {
      final r = await Future.wait([_api.get('/clients'), _api.get('/users', params: {'role': 'SiteEngineer'})]);
      if (!mounted) return;
      setState(() {
        _clients = asMapList(r[0]);
        _engineers = asMapList(r[1]);
      });
    } catch (_) {
      // Pickers are optional; the list still works without them.
    }
  }

  Future<void> _reload() => Future.wait([_loadList(), _loadSummary()]);

  Future<void> _loadSummary() async {
    try {
      final org = context.read<OrgProvider>();
      final s = await _api.get('/projects/dashboard-summary', params: {...org.orgParams});
      if (mounted) setState(() => _summary = Map<String, dynamic>.from(s as Map));
    } catch (_) {
      // KPIs show "—" when the summary fails.
    }
  }

  Future<void> _loadList() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    final org = context.read<OrgProvider>();
    try {
      final d = await _api.get('/projects', params: {
        ...org.orgParams,
        'limit': _pageSize,
        'offset': _offset,
        'client_id': _clientId,
        'status': _status,
        'site_engineer_id': _engineerId,
        'search': _search,
        if (_hasIssues) 'has_issues': 'true',
      });
      if (!mounted || gen != _gen) return;
      setState(() {
        _data = Map<String, dynamic>.from(d as Map);
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

  void _apply(VoidCallback change) {
    setState(() {
      change();
      _offset = 0;
    });
    _loadList();
  }

  // KPI card toggles, as the web's clickTotal / clickOngoing / clickCompleted / clickIssues.
  bool get _totalActive => _status == null && !_hasIssues && _clientId == null && _engineerId == null && _search.isEmpty;
  bool get _ongoingActive => _status == 'Ongoing' && !_hasIssues;

  void _clickTotal() {
    _searchCtrl.clear();
    _apply(() {
      _search = '';
      _status = null;
      _hasIssues = false;
      _clientId = null;
      _engineerId = null;
    });
  }

  void _clickStatus(String s) => _apply(() {
        _hasIssues = false;
        _status = _status == s ? null : s;
      });

  void _clickIssues() => _apply(() {
        _status = null;
        _hasIssues = !_hasIssues;
      });

  Future<void> _newProject() async {
    final saved = await showProjectForm(context);
    if (saved != null && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final isAdmin = user?.role == 'Admin';
    final s = _summary;
    final items = asMapList(_data);
    final total = toInt(_data?['total']);

    return Scaffold(
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              heroTag: 'new-project',
              onPressed: _newProject,
              icon: const Icon(Icons.add),
              label: const Text('New Project'),
            )
          : null,
      body: RefreshList(
        onRefresh: _reload,
        children: [
          KpiGrid(children: [
            FilterStatCard(
                label: 'Total Projects',
                value: '${s?['total_projects'] ?? '—'}',
                icon: Icons.apartment_outlined,
                active: _totalActive,
                onTap: _clickTotal),
            FilterStatCard(
                label: 'Ongoing',
                value: '${s?['ongoing'] ?? '—'}',
                icon: Icons.show_chart,
                tone: Tone.success,
                active: _ongoingActive,
                onTap: () => _clickStatus('Ongoing')),
            FilterStatCard(
                label: 'Completed',
                value: '${s?['completed'] ?? '—'}',
                icon: Icons.show_chart,
                tone: Tone.info,
                active: _status == 'Completed',
                onTap: () => _clickStatus('Completed')),
            FilterStatCard(
                label: 'With Issues',
                value: '${s?['with_issues'] ?? '—'}',
                icon: Icons.warning_amber_rounded,
                tone: Tone.danger,
                active: _hasIssues,
                onTap: _clickIssues),
            FilterStatCard(
                label: 'Total Budget',
                value: s == null ? '—' : inr(s['total_budget']),
                icon: Icons.currency_rupee,
                tone: Tone.info,
                onTap: () => _showBudget(context)),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 8),
            child: SearchField(
              controller: _searchCtrl,
              hint: 'Search projects…',
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () => _apply(() => _search = v.trim()));
              },
            ),
          ),
          _filters(context, user?.role),
          const SizedBox(height: 8),
          ..._listPart(context, items, total),
        ],
      ),
    );
  }

  Widget _filters(BuildContext context, String? role) {
    final notClient = role != 'Client';
    Widget box(Widget w) => SizedBox(width: 170, child: w);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: kGutter),
      child: Row(children: [
        if (notClient) ...[
          box(AppDropdown<int?>(
            label: 'Client',
            value: _clientId,
            hint: 'All Clients',
            items: [(null, 'All Clients'), for (final c in _clients) (c['id'] as int, (c['name'] ?? '').toString())],
            onChanged: (v) => _apply(() => _clientId = v),
          )),
          const SizedBox(width: 8),
        ],
        box(AppDropdown<String?>(
          label: 'Status',
          value: _status,
          hint: 'All Statuses',
          items: [(null, 'All Statuses'), for (final st in projectStatuses) (st, st)],
          onChanged: (v) => _apply(() => _status = v),
        )),
        if (notClient) ...[
          const SizedBox(width: 8),
          box(AppDropdown<int?>(
            label: 'Engineer',
            value: _engineerId,
            hint: 'All Engineers',
            items: [(null, 'All Engineers'), for (final e in _engineers) (e['id'] as int, (e['name'] ?? '').toString())],
            onChanged: (v) => _apply(() => _engineerId = v),
          )),
        ],
      ]),
    );
  }

  List<Widget> _listPart(BuildContext context, List<Map<String, dynamic>> items, int total) {
    if (_data == null && _loading) return const [LoadingView()];
    if (_error != null) {
      return [ErrorRetry(message: 'Failed to load projects. Please try again.\n${errorText(_error)}', onRetry: _loadList)];
    }
    if (items.isEmpty) {
      return [const EmptyState(icon: Icons.apartment_outlined, title: 'No projects found.')];
    }
    final tt = Theme.of(context).textTheme;
    return [
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      for (final pr in items)
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
          child: ProjectTile(
            project: pr,
            onTap: () async {
              await push(context, ProjectDetailScreen(projectId: toInt(pr['id'])));
              if (mounted) _reload();
            },
          ),
        ),
      if (total > _pageSize)
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 8),
          child: Row(children: [
            Expanded(
              child: Text('Showing ${_offset + 1}–${(_offset + _pageSize).clamp(0, total)} of $total',
                  style: tabular(tt.bodySmall)),
            ),
            OutlinedButton(
              onPressed: _offset == 0
                  ? null
                  : () {
                      setState(() => _offset = (_offset - _pageSize).clamp(0, 1 << 30));
                      _loadList();
                    },
              child: const Text('Prev'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _offset + _pageSize >= total
                  ? null
                  : () {
                      setState(() => _offset += _pageSize);
                      _loadList();
                    },
              child: const Text('Next'),
            ),
          ]),
        ),
    ];
  }

  /// Web "Budget Breakdown" dialog: every project in the slice with its client and budget.
  Future<void> _showBudget(BuildContext context) {
    final org = context.read<OrgProvider>();
    final summary = _summary;
    return showAppSheet<void>(
      context,
      title: 'Budget Breakdown',
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.6,
        child: AsyncView<List<Map<String, dynamic>>>(
          load: () async => asMapList(await _api.get('/projects', params: {'limit': 200, ...org.orgParams})),
          builder: (ctx, list, reload) {
            final p = ctx.pal;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: list.isEmpty
                    ? const EmptyState(title: 'No projects found.')
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: p.border),
                        itemBuilder: (_, i) {
                          final pr = list[i];
                          return RowTile(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            title: dash(pr['name']),
                            subtitle: dash(pr['client_name']),
                            trailing: Text(fmtBudget(pr['budget']),
                                style: tabular(Theme.of(ctx).textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w600)),
                          );
                        },
                      ),
              ),
              Divider(height: 1, color: p.border),
              TotalBand('Total', summary == null ? '—' : inr(summary['total_budget']), valueColor: p.accentText),
            ]);
          },
        ),
      ),
    );
  }
}
