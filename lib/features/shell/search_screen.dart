import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../org/org_provider.dart';
import '../projects/project_detail_screen.dart';
import 'nav_config.dart';
import 'routes.dart';

/// The web's command palette (Ctrl K): projects in the current company slice plus the pages this user can open.
class SearchScreen extends StatefulWidget {
  final void Function(NavPage page) onOpenPage;
  const SearchScreen({super.key, required this.onOpenPage});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _q = '';
  List<Map<String, dynamic>> _projects = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final user = context.read<AuthProvider>().user;
    final canProjects = gearsFor(user).any((g) => g.pages.any((p) => p.path == '/admin/projects'));
    if (!canProjects) return;
    setState(() => _loading = true);
    try {
      final org = context.read<OrgProvider>();
      final d = await context.read<ApiClient>().get('/projects', params: {'limit': 200, ...org.orgParams});
      _projects = ((d as Map)['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final user = context.watch<AuthProvider>().user;
    final needle = _q.trim().toLowerCase();
    final pages = [
      for (final g in gearsFor(user))
        for (final pg in g.pages)
          if (needle.isEmpty || '${pg.label} ${g.label}'.toLowerCase().contains(needle)) (g, pg),
    ];
    final projects = _projects
        .where((x) => needle.isEmpty ||
            '${x['name']} ${x['location'] ?? ''} ${x['client_name'] ?? ''}'.toLowerCase().contains(needle))
        .take(needle.isEmpty ? 8 : 30)
        .toList();

    Widget projectRows() => RowGroup(children: [
          for (final x in projects)
            RowTile(
              leading: Icon(Icons.apartment_outlined, size: 20, color: p.fgSubtle),
              title: x['name'] ?? '',
              subtitle: (x['branch_name'] ?? x['client_name'] ?? 'Project').toString(),
              chevron: true,
              onTap: () => push(context, ProjectDetailScreen(projectId: x['id'] as int)),
            ),
        ]);

    Widget pageRows() => RowGroup(children: [
          for (final (g, pg) in pages)
            RowTile(
              leading: Icon(pg.icon, size: 20, color: p.fgSubtle),
              title: pg.label,
              subtitle: '${g.key} · ${g.label}',
              chevron: true,
              onTap: () {
                Navigator.pop(context);
                widget.onOpenPage(pg);
              },
            ),
        ]);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search projects and pages',
              prefixIcon: Icon(Icons.search, size: 20),
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (needle.isNotEmpty) ...[
          if (projects.isNotEmpty) ...[const SectionHeader('Projects'), projectRows()],
          if (pages.isNotEmpty) ...[const SectionHeader('Pages'), pageRows()],
        ] else ...[
          if (pages.isNotEmpty) ...[const SectionHeader('Pages'), pageRows()],
          if (projects.isNotEmpty) ...[const SectionHeader('Projects'), projectRows()],
        ],
        if (projects.isEmpty && pages.isEmpty && !_loading) EmptyState(icon: Icons.search_off, title: 'Nothing matches “$_q”.'),
      ]),
    );
  }
}
