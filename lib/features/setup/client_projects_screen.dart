import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../projects/project_detail_screen.dart';
import '../projects/project_form_sheet.dart';
import '../projects/project_tile.dart';
import '../shell/routes.dart';
import 'setup_kit.dart';

/// A client's project portfolio (web ClientProjectsPage.jsx). Admin can start a new project for the client.
class ClientProjectsScreen extends StatefulWidget {
  final int clientId;
  const ClientProjectsScreen({super.key, required this.clientId});

  @override
  State<ClientProjectsScreen> createState() => _ClientProjectsScreenState();
}

class _ClientProjectsScreenState extends State<ClientProjectsScreen> {
  final _view = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();
  Map<String, dynamic>? _client;

  @override
  void initState() {
    super.initState();
    _loadClient();
  }

  Future<void> _loadClient() async {
    try {
      final c = Map<String, dynamic>.from(await context.read<ApiClient>().get('/clients/${widget.clientId}') as Map);
      if (mounted) setState(() => _client = c);
    } catch (_) {
      // The header just keeps its placeholder; the list shows its own error.
    }
  }

  Future<void> _newProject() async {
    final created = await showProjectForm(context, clientId: widget.clientId);
    if (created != null) _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().user?.isAdmin ?? false;
    final api = context.read<ApiClient>();
    final company = (_client?['company'] ?? '').toString();
    return AppScaffold(
      title: (_client?['name'] ?? '…').toString(),
      subtitle: company.isEmpty ? 'Client Portfolio' : company,
      fab: isAdmin
          ? FloatingActionButton.extended(onPressed: _newProject, icon: const Icon(Icons.add), label: const Text('New Project'))
          : null,
      body: AsyncView<List<Map<String, dynamic>>>(
        key: _view,
        load: () async => asMaps(await api.get('/clients/${widget.clientId}/projects')),
        builder: (context, projects, reload) => RefreshList(
          onRefresh: () async {
            await Future.wait([reload(), _loadClient()]);
          },
          children: [
            SectionHeader('Client Portfolio · ${projects.length}', padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 8)),
            if (projects.isEmpty)
              const EmptyState(icon: Icons.apartment_outlined, title: 'No projects found.')
            else
              for (final p in projects)
                Padding(
                  padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
                  child: ProjectTile(
                    project: p,
                    onTap: () async {
                      await push(context, ProjectDetailScreen(projectId: p['id'] as int));
                      reload();
                    },
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
