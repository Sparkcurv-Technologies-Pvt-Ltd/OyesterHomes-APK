import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/storage/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../org/org_provider.dart';
import 'nav_config.dart';
import 'notifications_screen.dart';
import 'routes.dart';
import 'search_screen.dart';

/// Signed-in frame. The web's three header rows become: an app bar (page title, company switcher,
/// search, alerts, account), a bottom bar with up to five role-based destinations, and a drawer with
/// every page grouped by workflow gear (N, 1 Setup … 6 Money), exactly as the web filters them.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String _current = '/admin';
  final Map<String, Widget> _built = {};
  Timer? _poll;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    final count = context.read<NotificationCount>();
    count.refresh();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => count.refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _open(NavPage page) => setState(() => _current = page.path);

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final userGears = gearsFor(user);
    final allowed = {for (final g in userGears) for (final p in g.pages) p.path: p};
    // The web always renders the dashboard at /admin, even for roles with no gears.
    final home = pageForPath('/admin')!;
    final current = allowed[_current] ?? home;
    var bottom = bottomPagesFor(user);
    if (bottom.isEmpty || bottom.first.path != '/admin') bottom = [home, ...bottom].take(5).toList();
    final bottomIndex = bottom.indexWhere((p) => p.path == current.path);
    final pages = {for (final p in [...allowed.values, home]) p.path: p};

    // Keep each visited page alive so switching tabs does not refetch.
    _built.putIfAbsent(current.path, () => KeyedSubtree(key: PageStorageKey(current.path), child: current.builder(null)));
    _built.removeWhere((k, _) => !pages.containsKey(k));
    final keys = _built.keys.toList();

    return PopScope(
      canPop: current.path == '/admin',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && current.path != '/admin') setState(() => _current = '/admin');
      },
      child: Scaffold(
        key: _scaffoldKey,
        appBar: _ShellBar(title: current.label, onMenu: () => _scaffoldKey.currentState?.openDrawer(), onOpenPage: _open),
        drawer: _ShellDrawer(gears: userGears, current: current.path, onOpen: (p) {
          Navigator.pop(context);
          _open(p);
        }),
        body: IndexedStack(
          index: keys.indexOf(current.path),
          children: [for (final k in keys) _built[k]!],
        ),
        bottomNavigationBar: bottom.length < 2
            ? null
            : DecoratedBox(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: context.pal.border))),
                child: NavigationBar(
                  selectedIndex: bottomIndex < 0 ? 0 : bottomIndex,
                  indicatorColor: bottomIndex < 0 ? Colors.transparent : null,
                  onDestinationSelected: (i) => _open(bottom[i]),
                  destinations: [
                    for (final p in bottom) NavigationDestination(icon: Icon(p.icon), label: bottomLabels[p.path] ?? p.label),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ShellBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback onMenu;
  final void Function(NavPage) onOpenPage;
  const _ShellBar({required this.title, required this.onMenu, required this.onOpenPage});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final unread = context.watch<NotificationCount>().unread;
    final user = context.watch<AuthProvider>().user;
    return AppBar(
      toolbarHeight: 64,
      leading: IconButton(tooltip: 'Menu', onPressed: onMenu, icon: const Icon(Icons.menu)),
      titleSpacing: 0,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        const _OrgSwitcher(),
      ]),
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search),
          onPressed: () => push(context, SearchScreen(onOpenPage: onOpenPage)),
        ),
        if (user?.isStaff ?? false)
          IconButton(
            tooltip: 'Alerts',
            onPressed: () => push(context, const NotificationsScreen()),
            icon: Badge(
              isLabelVisible: unread > 0,
              backgroundColor: p.danger,
              label: Text(unread > 99 ? '99+' : '$unread', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
              child: const Icon(Icons.notifications_none),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            tooltip: 'Account',
            onPressed: () => _showAccount(context),
            icon: InitialsAvatar(user?.name, size: 32),
          ),
        ),
      ],
    );
  }
}

/// Company / branch picker (web OrgSwitcher). Hidden when the user has no companies.
class _OrgSwitcher extends StatelessWidget {
  const _OrgSwitcher();

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrgProvider>();
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    if (!org.enabled || (org.company == null && !(org.allCompanies && org.companies.isNotEmpty))) return const SizedBox();
    final c = org.company;
    final label = c == null
        ? 'All companies · ${org.companies.length} compan${org.companies.length == 1 ? 'y' : 'ies'}'
        : '${c['name']} · ${org.branch?['name'] ?? 'All branches'}';
    final row = Row(mainAxisSize: MainAxisSize.min, children: [
      CodeTag(OrgProvider.codeOf(c)),
      const SizedBox(width: 6),
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(fontSize: 12))),
      if (org.multi) Icon(Icons.unfold_more, size: 15, color: p.fgSubtle),
    ]);
    if (!org.multi) return Padding(padding: const EdgeInsets.only(top: 2), child: row);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _pickOrg(context),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: row),
    );
  }

  void _pickOrg(BuildContext context) {
    final org = context.read<OrgProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final p = ctx.pal;
        Widget tick(bool on) => Icon(Icons.check, size: 18, color: on ? p.accentText : Colors.transparent);
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 16), children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Eyebrow('Working in')),
            if (org.companies.length > 1)
              ListTile(
                leading: tick(org.allCompanies),
                title: const Text('All companies'),
                onTap: () {
                  org.selectAll();
                  Navigator.pop(ctx);
                },
              ),
            for (final c in org.companies) ...[
              const Divider(height: 1),
              ListTile(
                leading: tick(org.company?['id'] == c['id'] && org.branch == null),
                title: Row(children: [
                  CodeTag(OrgProvider.codeOf(c)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(c['name'] ?? '', overflow: TextOverflow.ellipsis)),
                ]),
                onTap: () {
                  org.selectCompany(c['id'] as int);
                  Navigator.pop(ctx);
                },
              ),
              for (final b in org.branchesOf(c))
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 40, right: 16),
                  leading: tick(org.branch?['id'] == b['id']),
                  title: Text(b['name'] ?? '', style: Theme.of(ctx).textTheme.bodyMedium),
                  trailing: Text('${b['project_count'] ?? ''}',
                      style: tabular(TextStyle(fontFamily: monoFamily, fontSize: 11, color: p.fgSubtle))),
                  onTap: () {
                    org.selectBranch(c['id'] as int, b['id'] as int);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ]),
        );
      },
    );
  }
}

class _ShellDrawer extends StatelessWidget {
  final List<NavGear> gears;
  final String current;
  final void Function(NavPage) onOpen;
  const _ShellDrawer({required this.gears, required this.current, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final user = context.watch<AuthProvider>().user;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Image.asset(dark ? 'assets/images/sitera-logo-horizontal-on-dark.png' : 'assets/images/sitera-logo-horizontal.png',
                  height: 34),
              if (user?.tenantName != null) ...[
                const SizedBox(height: 10),
                Text(user!.tenantName!, style: tt.bodySmall),
              ],
            ]),
          ),
          Divider(color: p.border),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
              for (final g in gears) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Row(children: [
                    Text(g.key, style: TextStyle(fontFamily: monoFamily, fontSize: 11, fontWeight: FontWeight.w600, color: p.accentText)),
                    const SizedBox(width: 8),
                    Eyebrow(g.label),
                  ]),
                ),
                for (final pg in g.pages)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: ListTile(
                      dense: false,
                      selected: pg.path == current,
                      selectedTileColor: p.muted,
                      selectedColor: p.fg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
                      leading: Icon(pg.icon, size: 21, color: pg.path == current ? p.accentText : p.fgMuted),
                      title: Text(pg.label,
                          style: tt.bodyMedium?.copyWith(fontWeight: pg.path == current ? FontWeight.w700 : FontWeight.w500)),
                      onTap: () => onOpen(pg),
                    ),
                  ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

void _showAccount(BuildContext context) {
  showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) {
      final p = ctx.pal;
      final tt = Theme.of(ctx).textTheme;
      final user = ctx.read<AuthProvider>().user;
      final theme = ctx.watch<ThemeController>();
      // Scrollable and padded past the system navigation bar so "Sign out" is never cut off.
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewPaddingOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            InitialsAvatar(user?.name, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.name ?? '', style: tt.titleMedium),
                Text(user?.email ?? '', style: tt.bodySmall),
                const SizedBox(height: 4),
                Eyebrow(user?.roleLabel ?? ''),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          const Eyebrow('Theme'),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {theme.mode},
            onSelectionChanged: (s) => theme.set(s.first),
          ),
          const SizedBox(height: 16),
          Text('Server: ${ApiConfig.baseUrlSync}', style: tt.bodySmall),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: p.danger, side: BorderSide(color: p.danger.withValues(alpha: 0.5))),
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AuthProvider>().logout();
            },
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out'),
          ),
        ]),
      );
    },
  );
}
