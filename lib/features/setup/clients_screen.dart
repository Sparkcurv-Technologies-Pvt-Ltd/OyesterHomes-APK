import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../shell/routes.dart';
import 'client_detail_screen.dart';
import 'client_form_sheet.dart';
import 'setup_kit.dart';

/// Client directory (web ClientsPage.jsx + ClientFormModal.jsx). Admin adds clients.
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _view = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();

  Future<void> _reload() async => _view.currentState?.reload();

  Future<void> _add() async {
    if (await showClientForm(context)) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().user?.isAdmin ?? false;
    final api = context.read<ApiClient>();
    return Scaffold(
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add Client'))
          : null,
      body: AsyncView<List<Map<String, dynamic>>>(
        key: _view,
        load: () async => asMaps(await api.get('/clients')),
        builder: (context, clients, reload) => RefreshList(
          onRefresh: reload,
          children: [
            SectionHeader('Directory · ${clients.length}', padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 8)),
            if (clients.isEmpty)
              const EmptyState(icon: Icons.people_outline, title: 'No clients yet.')
            else
              RowGroup(children: [
                for (final c in clients)
                  _ClientRow(
                    client: c,
                    onTap: () async {
                      await push(context, ClientDetailScreen(clientId: c['id'] as int));
                      reload();
                    },
                  ),
              ]),
          ],
        ),
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  final Map<String, dynamic> client;
  final VoidCallback onTap;
  const _ClientRow({required this.client, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final active = client['is_active'] != false;
    final sub = dash(client['company'] ?? client['email']);
    final phone = (client['phone'] ?? '').toString();
    return RowTile(
      onTap: onTap,
      chevron: true,
      title: (client['name'] ?? '').toString(),
      subtitleWidget: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(phone.isEmpty ? sub : '$sub · $phone', style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        StatusChip(active ? 'Active' : 'Inactive', dense: true),
      ]),
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Text(inr(client['total_billed']), style: tabular(tt.titleSmall)),
        const SizedBox(height: 2),
        Text('${client['project_count'] ?? 0} projects', style: tabular(tt.bodySmall)),
      ]),
    );
  }
}
