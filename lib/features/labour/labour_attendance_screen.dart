import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../auth/user.dart';
import '../org/org_provider.dart';
import '../shell/routes.dart';
import 'contractor_work.dart';
import 'daily_attendance_card.dart';
import 'employee_forms.dart';
import 'labour_shared.dart';

/// Field Operations → Daily Attendance (web SiteEngineerPortalPage.jsx with FieldAttendanceSummary.jsx and
/// CategoryManagerModal.jsx): pick a project and day, mark every field worker, mark contractor crews with photos,
/// review attendance records and the organisation's employee register. Clients see it read-only.
/// Top-level page: Scaffold without an AppBar (the shell draws it). Reloads when the company / branch changes.
class LabourAttendanceScreen extends StatefulWidget {
  const LabourAttendanceScreen({super.key});

  @override
  State<LabourAttendanceScreen> createState() => _LabourAttendanceScreenState();
}

class _LabourAttendanceScreenState extends State<LabourAttendanceScreen> {
  final _body = GlobalKey<_PortalBodyState>();

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrgProvider>();
    final user = context.watch<AuthProvider>().user;
    final isClient = user?.role == 'Client';
    return Scaffold(
      floatingActionButton: isClient
          ? null
          : FloatingActionButton.extended(
              heroTag: 'se-add-employee',
              onPressed: () => _body.currentState?.addEmployee(),
              icon: const Icon(Icons.add),
              label: const Text('Add Employee'),
            ),
      body: AsyncView<List<Map<String, dynamic>>>(
        depKey: org.orgKey,
        load: () async {
          final d = await context.read<ApiClient>().get('/projects', params: {'limit': 200, ...org.orgParams});
          return asMaps(d is Map ? d['items'] : d);
        },
        builder: (ctx, projects, reload) => _PortalBody(key: _body, projects: projects, reloadProjects: reload),
      ),
    );
  }
}

class _PortalBody extends StatefulWidget {
  final List<Map<String, dynamic>> projects;
  final Future<void> Function() reloadProjects;
  const _PortalBody({super.key, required this.projects, required this.reloadProjects});

  @override
  State<_PortalBody> createState() => _PortalBodyState();
}

class _PortalBodyState extends State<_PortalBody> {
  int? _pid;
  String _day = todayIso();
  List<Map<String, dynamic>>? _employees;
  List<Map<String, dynamic>> _attendance = [];
  List<Map<String, dynamic>>? _allEmployees;
  Map<String, dynamic>? _crews;
  bool _loading = false;
  Object? _error;
  int _tick = 0;
  int _gen = 0;

  AppUser? get _user => context.read<AuthProvider>().user;
  bool get _isClient => _user?.role == 'Client';

  @override
  void initState() {
    super.initState();
    _pickProject();
    _loading = true;
    Future.microtask(_loadAll);
  }

  @override
  void didUpdateWidget(covariant _PortalBody old) {
    super.didUpdateWidget(old);
    // Move to the first project when the header's company / branch no longer has this one.
    if (!widget.projects.any((p) => p['id'] == _pid)) {
      _pickProject();
      Future.microtask(_loadAll);
    }
  }

  void _pickProject() {
    if (_pid == null || !widget.projects.any((p) => p['id'] == _pid)) {
      _pid = widget.projects.isEmpty ? null : widget.projects.first['id'] as int;
    }
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    final gen = ++_gen;
    final api = context.read<ApiClient>();
    final pid = _pid;
    final day = _day;
    final isClient = _isClient;
    setState(() {
      _loading = true;
      _error = null;
    });
    Future<T?> soft<T>(Future<T> f) async {
      try {
        return await f;
      } catch (_) {
        return null; // sections this role may not read stay hidden, as on the web
      }
    }

    try {
      final res = await Future.wait<dynamic>([
        pid == null ? Future.value(const []) : api.get('/projects/$pid/employees'),
        pid == null ? Future.value(const []) : api.get('/projects/$pid/attendance', params: {'date_from': day, 'date_to': day}),
        isClient ? Future.value(null) : soft(api.get('/employees')),
        isClient || pid == null ? Future.value(null) : soft(api.get('/projects/$pid/contractor-attendance')),
      ]);
      if (!mounted || gen != _gen) return;
      setState(() {
        _employees = asMaps(res[0]);
        _attendance = asMaps(res[1]);
        _allEmployees = res[2] == null ? null : asMaps(res[2]);
        _crews = asMap(res[3]);
        _loading = false;
        _tick++;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _reloadCrews() async {
    final pid = _pid;
    if (pid == null || _isClient) return;
    try {
      final d = await context.read<ApiClient>().get('/projects/$pid/contractor-attendance');
      if (mounted && pid == _pid) setState(() => _crews = asMap(d));
    } catch (_) {}
  }

  Future<void> _reloadDay() async {
    final pid = _pid;
    if (pid == null) return;
    try {
      final d = await context.read<ApiClient>().get('/projects/$pid/attendance', params: {'date_from': _day, 'date_to': _day});
      if (mounted && pid == _pid) {
        setState(() {
          _attendance = asMaps(d);
          _tick++;
        });
      }
    } catch (_) {}
  }

  Future<void> addEmployee() async {
    if (await showEmployeeForm(context, projectId: _pid)) _loadAll(); // on the picked project, so they can be marked
  }

  Map<int, Map<String, dynamic>> get _records => {for (final a in _attendance) a['employee_id'] as int: a};

  Future<void> _mark(Map<String, dynamic> e, String status) async {
    final pid = _pid!;
    final day = _day;
    final prev = List<Map<String, dynamic>>.from(_attendance);
    setState(() {
      // Show it straight away; put it back if the server refuses.
      final i = _attendance.indexWhere((a) => a['employee_id'] == e['id']);
      if (i >= 0) {
        _attendance[i] = {..._attendance[i], 'status': status};
      } else {
        _attendance.add({'employee_id': e['id'], 'attendance_date': day, 'status': status});
      }
    });
    try {
      await context.read<ApiClient>().post('/projects/$pid/attendance', data: {'employee_id': e['id'], 'attendance_date': day, 'status': status});
      if (mounted) showToast(context, '${e['name']}: ${status.replaceFirst('_', ' ')}');
      await _reloadDay();
    } catch (err) {
      if (!mounted) return;
      setState(() => _attendance = prev);
      showToast(context, errorText(err), error: true);
    }
  }

  /// Work note / NMR contract for a worker already marked that day (only the sent fields change on the server).
  Future<void> _saveDetails(Map<String, dynamic> e, Map<String, dynamic> patch) async {
    final pid = _pid!;
    try {
      await context.read<ApiClient>().post('/projects/$pid/attendance',
          data: {'employee_id': e['id'], 'attendance_date': _day, 'status': _records[e['id']]?['status'], ...patch});
      if (!mounted) return;
      if (patch.containsKey('subcontract_id')) {
        showToast(context, patch['subcontract_id'] != null ? '${e['name']} put on contractor work (NMR)' : '${e['name']} back on own work');
      } else {
        showToast(context, 'Work note saved for ${e['name']}');
      }
      await Future.wait([_reloadDay(), _reloadCrews()]);
    } catch (err) {
      if (mounted) showToast(context, errorText(err), error: true);
    }
  }

  Future<void> _refresh() async {
    await widget.reloadProjects();
    await _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final isClient = user?.role == 'Client';
    final isAdmin = user?.role == 'Admin';
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final projects = widget.projects;
    final pid = _pid;
    final project = projects.where((x) => x['id'] == pid).firstOrNull;
    final active = (_employees ?? const []).where((e) => e['status'] == 'active').toList();
    final records = _records;
    final markedCount = active.where((e) => records[e['id']] != null).length;
    final counts = <String, int>{for (final (k, _) in kFieldStatuses) k: 0};
    for (final a in _attendance) {
      if (counts.containsKey(a['status'])) counts[a['status'] as String] = counts[a['status']]! + 1;
    }
    final contracts = asMaps(_crews?['contracts']);

    return RefreshList(onRefresh: _refresh, children: [
      // ── header
      Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Eyebrow('Field Operations', color: p.accentText),
              const SizedBox(height: 4),
              Text('Daily Attendance', style: tt.headlineMedium),
              if (isClient) ...[
                const SizedBox(height: 4),
                Text('View-only — attendance for your projects', style: tt.bodySmall),
              ],
            ]),
          ),
          if (!isClient && (user?.roleIn(['Admin', 'Accountant']) ?? false))
            OutlinedButton.icon(
              onPressed: () async {
                await showCategoryManager(context);
                _loadAll();
              },
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: const Text('Categories'),
            ),
        ]),
      ),

      // ── project & date
      Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 0),
        child: AppDropdown<int>(
          label: 'Project',
          hint: 'Select project',
          value: pid,
          items: [for (final x in projects) (x['id'] as int, (x['name'] ?? '').toString())],
          onChanged: (v) {
            if (v == null || v == _pid) return;
            setState(() => _pid = v);
            _loadAll();
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 0),
        child: Row(children: [
          Expanded(
            child: DateField(
              label: 'Date',
              value: _day,
              clearable: false,
              firstDate: isAdmin || isClient ? null : toDate(daysAgoIso(3)),
              lastDate: DateTime.now(),
              onChanged: (v) {
                if (v == null || v == _day) return;
                setState(() => _day = v);
                _loadAll();
              },
            ),
          ),
          if (pid != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => openWebPath(context, '/admin/projects/$pid'),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Full Project View'),
            ),
          ],
        ]),
      ),
      if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),

      if (_error != null && _employees == null)
        ErrorRetry(message: errorText(_error), onRetry: _loadAll)
      else ...[
        // ── summary bar
        if (project != null && _employees != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 14, kGutter, 0),
            child: Surface(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text((project['name'] ?? '').toString(), style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '$markedCount', style: tabular(tt.titleMedium).copyWith(fontWeight: FontWeight.w800)),
                  TextSpan(text: '/${active.length} marked for ${fmtDate(_day)}', style: tt.bodyMedium?.copyWith(color: p.fgMuted)),
                ])),
                const SizedBox(height: 10),
                Wrap(spacing: 14, runSpacing: 6, children: [
                  for (final (k, label) in kFieldStatuses) _count(context, label, counts[k]!, p.tone(dayTone(k))),
                  if (active.length > markedCount) _count(context, 'Not marked', active.length - markedCount, p.fg),
                ]),
              ]),
            ),
          ),

        // ── contractor crews
        if (!isClient && pid != null) ContractorCrewsToday(data: _crews, onChanged: _reloadCrews),

        // ── workers
        if (active.isNotEmpty) SectionHeader(isClient ? 'Workers' : 'Mark workers · ${fmtDate(_day)}'),
        if (pid == null)
          const Padding(
            padding: EdgeInsets.fromLTRB(kGutter, 14, kGutter, 0),
            child: Surface(child: EmptyState(icon: Icons.engineering_outlined, title: 'No assigned projects found.')),
          )
        else if (_employees != null && active.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 14, kGutter, 0),
            child: Surface(
              child: EmptyState(
                icon: Icons.engineering_outlined,
                title: isClient
                    ? 'No employees on this project yet.'
                    : 'No employees on this project yet. Tap "Add Employee" to register your first field worker.',
              ),
            ),
          ),
        for (final e in active)
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
            child: DailyAttendanceCard(
              key: ValueKey('se-${e['id']}'),
              employee: e,
              status: records[e['id']]?['status'] as String?,
              record: records[e['id']],
              onMark: _mark,
              onDetails: _saveDetails,
              contracts: contracts,
              readOnly: isClient,
            ),
          ),

        // ── records
        if (projects.isNotEmpty)
          _FieldAttendanceSummary(
            pid: pid,
            projectName: project?['name']?.toString(),
            employees: _allEmployees ?? _employees ?? const [],
            reloadKey: _tick,
          ),

        // ── organisation register
        if (!isClient) ...[
          SectionHeader('Employee Register (Organisation) · ${(_allEmployees ?? const []).length}'),
          RowGroup(children: [
            if ((_allEmployees ?? const []).isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('No employees yet — tap the button below to add your first worker.', textAlign: TextAlign.center)),
              ),
            for (final e in _allEmployees ?? const <Map<String, dynamic>>[]) _orgEmployee(context, e),
          ]),
        ],
      ],
    ]);
  }

  Widget _count(BuildContext context, String label, int n, Color color) {
    final tt = Theme.of(context).textTheme;
    return Text.rich(TextSpan(children: [
      TextSpan(text: '$label ', style: tt.bodySmall),
      TextSpan(text: '$n', style: tabular(tt.titleSmall).copyWith(color: color, fontWeight: FontWeight.w800)),
    ]));
  }

  Widget _orgEmployee(BuildContext context, Map<String, dynamic> e) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final projects = (e['assigned_projects'] as List? ?? const []).map((x) => x.toString()).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((e['name'] ?? '').toString(), style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(dash(e['role_title']), style: tt.bodySmall),
            ]),
          ),
          StatusChip(e['status'], dense: true, tone: e['status'] == 'active' ? Tone.success : Tone.neutral),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Fig('Wage', wageText(e))),
          Expanded(
            flex: 2,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Eyebrow('Assigned Projects (via phases)'),
              const SizedBox(height: 3),
              Text(
                projects.isNotEmpty ? projects.join(', ') : 'Unassigned — assign via Project → Phases',
                style: tt.bodySmall?.copyWith(color: projects.isNotEmpty ? p.fg : p.fgSubtle),
              ),
            ]),
          ),
        ]),
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────── attendance records (FieldAttendanceSummary.jsx)

class _FieldAttendanceSummary extends StatefulWidget {
  final int? pid;
  final String? projectName;
  final List<Map<String, dynamic>> employees;
  final Object? reloadKey;
  const _FieldAttendanceSummary({required this.pid, required this.projectName, required this.employees, this.reloadKey});

  @override
  State<_FieldAttendanceSummary> createState() => _FieldAttendanceSummaryState();
}

class _Group {
  final String key;
  final String label;
  String sub;
  final String sort;
  final Map<String, int> c = {for (final (k, _) in kFieldStatuses) k: 0};
  final Set<String> projects = {};
  _Group(this.key, this.label, {this.sub = '', this.sort = ''});
  double get worked => c['present']! + c['half_day']! * 0.5;
}

const _letters = {'present': 'P', 'half_day': '½', 'absent': 'A', 'leave': 'L'};

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

String _fmtWorked(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class _FieldAttendanceSummaryState extends State<_FieldAttendanceSummary> {
  String _from = daysAgoIso(6);
  String _to = daysAgoIso(0);
  String _scope = 'project';
  String _view = 'worker';

  static final _presets = <(String, String, (String, String) Function())>[
    ('today', 'Today', () => (daysAgoIso(0), daysAgoIso(0))),
    ('7d', 'Last 7 days', () => (daysAgoIso(6), daysAgoIso(0))),
    ('month', 'This month', () => (monthStartIso(), daysAgoIso(0))),
  ];

  bool get _all => _scope == 'all' || widget.pid == null;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final views = _all
        ? const [('worker', 'By worker'), ('day', 'By day'), ('project', 'By project')]
        : const [('worker', 'By worker'), ('day', 'By day')];
    final shownView = views.any((v) => v.$1 == _view) ? _view : 'worker';
    final activePreset = _presets.where((x) {
      final (f, t) = x.$3();
      return f == _from && t == _to;
    }).firstOrNull?.$1;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Attendance records', padding: EdgeInsets.fromLTRB(kGutter, 28, kGutter, 4)),
      if (widget.pid != null)
        FilterBar<String>(
          value: _scope,
          options: [('project', widget.projectName ?? 'This project'), ('all', 'All projects')],
          onChanged: (v) => setState(() => _scope = v),
        ),
      FilterBar<String>(
        value: activePreset ?? '',
        options: [for (final (k, l, _) in _presets) (k, l)],
        onChanged: (k) {
          final (f, t) = _presets.firstWhere((x) => x.$1 == k).$3();
          setState(() {
            _from = f;
            _to = t;
          });
        },
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 12),
        child: Row(children: [
          Expanded(
            child: DateField(
              label: 'From',
              value: _from,
              clearable: false,
              lastDate: toDate(_to),
              onChanged: (v) => setState(() => _from = v ?? _from),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DateField(
              label: 'To',
              value: _to,
              clearable: false,
              firstDate: toDate(_from),
              lastDate: DateTime.now(),
              onChanged: (v) => setState(() => _to = v ?? _to),
            ),
          ),
        ]),
      ),
      if (_from.compareTo(_to) > 0)
        Note('No attendance marked between ${fmtDate(_from)} and ${fmtDate(_to)}.')
      else
        InlineAsync<List<Map<String, dynamic>>>(
          depKey: '$_all|${widget.pid}|$_from|$_to|${widget.reloadKey}',
          load: () async => asMaps(await context.read<ApiClient>().get(
              _all ? '/field-attendance' : '/projects/${widget.pid}/attendance',
              params: {'date_from': _from, 'date_to': _to})),
          builder: (ctx, rows, _) => _summary(context, tt, rows, views, shownView),
        ),
    ]);
  }

  Widget _summary(BuildContext context, TextTheme tt, List<Map<String, dynamic>> rows, List<(String, String)> views, String shownView) {
    final p = context.pal;
    final info = {for (final e in widget.employees) e['id']: e};
    final g = <String, Map<String, _Group>>{'worker': {}, 'day': {}, 'project': {}};
    _Group add(String kind, String key, _Group Function() init, String status) {
      final grp = g[kind]!.putIfAbsent(key, init);
      if (grp.c.containsKey(status)) grp.c[status] = grp.c[status]! + 1;
      return grp;
    }

    final totals = <String, int>{for (final (k, _) in kFieldStatuses) k: 0};
    final people = <String, Set<dynamic>>{};
    for (final r in rows) {
      final status = (r['status'] ?? '').toString();
      if (totals.containsKey(status)) totals[status] = totals[status]! + 1;
      (people[status] ??= {}).add(r['employee_id']);
      final w = add(
          'worker',
          '${r['employee_id']}',
          () => _Group('${r['employee_id']}', (r['employee_name'] ?? info[r['employee_id']]?['name'] ?? '#${r['employee_id']}').toString(),
              sub: (info[r['employee_id']]?['role_title'] ?? '').toString()),
          status);
      if (r['project_name'] != null) w.projects.add(r['project_name'].toString());
      add('day', '${r['attendance_date']}',
          () => _Group('${r['attendance_date']}', fmtDate(r['attendance_date']), sort: '${r['attendance_date']}'), status);
      add('project', '${r['project_id']}', () => _Group('${r['project_id']}', (r['project_name'] ?? '#${r['project_id']}').toString()),
          status);
    }
    List<_Group> finish(Map<String, _Group> m, int Function(_Group, _Group) cmp) {
      final list = m.values.toList();
      for (final x in list) {
        if (x.sub.isEmpty) x.sub = x.projects.join(', ');
      }
      return list..sort(cmp);
    }

    int byLabel(_Group a, _Group b) => a.label.compareTo(b.label);
    final groups = {
      'worker': finish(g['worker']!, byLabel),
      'day': finish(g['day']!, (a, b) => b.sort.compareTo(a.sort)),
      'project': finish(g['project']!, byLabel),
    };
    final oneDay = _from == _to;
    String hint(String k) {
      final n = totals[k]!;
      if (oneDay) return _plural(n, 'worker');
      return n > 0 ? '${_plural(n, 'day')}, by ${_plural(people[k]?.length ?? 0, 'worker')}' : 'none';
    }

    final worked = totals['present']! + totals['half_day']! * 0.5;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrid(children: [
        for (final (k, label) in kFieldStatuses) KpiTile(label: label, value: '${totals[k]}', sub: hint(k), tone: dayTone(k)),
      ]),
      const SizedBox(height: 10),
      KpiGrid(columns: 1, children: [
        KpiTile(label: 'Total days worked', value: _fmtWorked(worked), sub: 'a half day counts as ½'),
      ]),
      const SizedBox(height: 4),
      FilterBar<String>(value: shownView, options: views, onChanged: (v) => setState(() => _view = v)),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kGutter),
          child: Surface(
            child: EmptyState(icon: Icons.event_busy_outlined, title: 'No attendance marked between ${fmtDate(_from)} and ${fmtDate(_to)}.'),
          ),
        )
      else
        RowGroup(children: [
          for (final r in groups[shownView]!)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.label, style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (shownView == 'worker' && r.sub.isNotEmpty) Text(r.sub, style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Wrap(spacing: 10, children: [
                      for (final (k, _) in kFieldStatuses)
                        Text.rich(TextSpan(children: [
                          TextSpan(text: '${_letters[k]} ', style: tt.bodySmall),
                          TextSpan(
                            text: '${r.c[k]}',
                            style: tabular(tt.bodySmall).copyWith(
                                fontWeight: FontWeight.w700, color: r.c[k]! > 0 ? p.tone(dayTone(k)) : p.fgSubtle),
                          ),
                        ])),
                    ]),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_fmtWorked(r.worked), style: tabular(tt.titleMedium).copyWith(fontWeight: FontWeight.w800)),
                  const Eyebrow('Days worked'),
                ]),
              ]),
            ),
        ]),
    ]);
  }
}
