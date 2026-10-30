import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../projects/project_detail_screen.dart';
import '../shell/routes.dart';
import 'client_form_sheet.dart';
import 'invoice_card.dart';
import 'setup_kit.dart';

/// One client: contact details and the Projects / Invoices / Documents tabs (web ClientDetailPage.jsx).
class ClientDetailScreen extends StatefulWidget {
  final int clientId;
  const ClientDetailScreen({super.key, required this.clientId});

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  static const _tabs = ['Projects', 'Invoices', 'Documents'];
  final _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  Map<String, dynamic>? _client;

  Future<Map<String, dynamic>> _load() async {
    final c = Map<String, dynamic>.from(await context.read<ApiClient>().get('/clients/${widget.clientId}') as Map);
    if (mounted) setState(() => _client = c);
    return c;
  }

  Future<void> _edit() async {
    if (_client == null) return;
    if (await showClientForm(context, client: _client)) _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().user?.isAdmin ?? false;
    final c = _client;
    return DefaultTabController(
      length: _tabs.length,
      child: AppScaffold(
        title: c == null ? 'Client' : (c['name'] ?? '').toString(),
        subtitle: c == null ? null : dash(c['company']) == '—' ? 'Client' : c['company'].toString(),
        actions: [
          if (isAdmin && c != null) IconButton(tooltip: 'Edit Client', icon: const Icon(Icons.edit_outlined), onPressed: _edit),
        ],
        bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in _tabs) Tab(text: t)]),
        body: AsyncView<Map<String, dynamic>>(
          key: _view,
          load: _load,
          builder: (context, client, _) => Column(children: [
            _Contact(client: client),
            Expanded(
              child: TabBarView(children: [
                _ProjectsTab(clientId: widget.clientId),
                _InvoicesTab(clientId: widget.clientId),
                _DocumentsTab(clientId: widget.clientId),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Contact extends StatelessWidget {
  final Map<String, dynamic> client;
  const _Contact({required this.client});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final email = (client['email'] ?? '').toString();
    final phone = (client['phone'] ?? '').toString();
    final address = (client['address'] ?? '').toString();
    Widget line(IconData icon, String value, VoidCallback? onTap) => InkWell(
          onTap: value.isEmpty ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(children: [
              Icon(icon, size: 16, color: p.fgSubtle),
              const SizedBox(width: 10),
              Expanded(
                child: Text(dash(value),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: value.isNotEmpty && onTap != null ? p.accentText : p.fgMuted,
                        fontWeight: FontWeight.w500)),
              ),
            ]),
          ),
        );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: p.card, border: Border(bottom: BorderSide(color: p.border))),
      padding: const EdgeInsets.fromLTRB(kGutter, 6, kGutter, 6),
      child: Column(children: [
        line(Icons.mail_outline, email, () => openExternal(context, 'mailto:$email')),
        line(Icons.phone_outlined, phone, () => openExternal(context, 'tel:${phone.replaceAll(RegExp(r'[^\d+]'), '')}')),
        line(Icons.place_outlined, address, null),
      ]),
    );
  }
}

class _ProjectsTab extends StatelessWidget {
  final int clientId;
  const _ProjectsTab({required this.clientId});

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final tt = Theme.of(context).textTheme;
    return AsyncView<List<Map<String, dynamic>>>(
      load: () async => asMaps(await api.get('/clients/$clientId/projects')),
      builder: (context, projects, reload) => RefreshList(
        onRefresh: reload,
        padding: const EdgeInsets.only(top: 12, bottom: 32),
        children: [
          if (projects.isEmpty)
            const EmptyState(icon: Icons.apartment_outlined, title: 'No projects for this client.')
          else
            RowGroup(children: [
              for (final pr in projects)
                RowTile(
                  chevron: true,
                  onTap: () => push(context, ProjectDetailScreen(projectId: pr['id'] as int)),
                  leading: SizedBox(
                    width: 52,
                    child: Text('${toInt(pr['percent_complete'])}%',
                        style: tabular(tt.titleLarge).copyWith(fontWeight: FontWeight.w700)),
                  ),
                  title: (pr['name'] ?? '').toString(),
                  subtitle: dash(pr['location']),
                  trailing: StatusChip(pr['status']?.toString(), dense: true),
                ),
            ]),
        ],
      ),
    );
  }
}

class _InvoicesTab extends StatelessWidget {
  final int clientId;
  const _InvoicesTab({required this.clientId});

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return AsyncView<List<Map<String, dynamic>>>(
      load: () async => asMaps(await api.get('/clients/$clientId/invoices')),
      builder: (context, invoices, reload) => RefreshList(
        onRefresh: reload,
        padding: const EdgeInsets.only(top: 12, bottom: 32),
        children: [
          if (invoices.isEmpty)
            const EmptyState(icon: Icons.receipt_long_outlined, title: 'No invoices for this client.')
          else
            for (final inv in invoices) ClientInvoiceCard(inv: inv),
        ],
      ),
    );
  }
}

class _DocumentsTab extends StatelessWidget {
  final int clientId;
  const _DocumentsTab({required this.clientId});

  static IconData _icon(String type) {
    if (type == 'pdf') return Icons.picture_as_pdf_outlined;
    if (['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(type)) return Icons.image_outlined;
    if (['xls', 'xlsx', 'csv'].contains(type)) return Icons.table_chart_outlined;
    return Icons.description_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final p = context.pal;
    return AsyncView<List<Map<String, dynamic>>>(
      load: () async => asMaps(await api.get('/clients/$clientId/documents')),
      builder: (context, docs, reload) => RefreshList(
        onRefresh: reload,
        padding: const EdgeInsets.only(top: 12, bottom: 32),
        children: [
          if (docs.isEmpty)
            const EmptyState(icon: Icons.folder_open_outlined, title: 'No documents.')
          else
            RowGroup(children: [
              for (final d in docs)
                RowTile(
                  leading: Icon(_icon((d['file_type'] ?? '').toString().toLowerCase()), size: 20, color: p.accentText),
                  title: (d['document_name'] ?? '').toString(),
                  subtitle: '${d['category'] ?? 'Other'} · ${dash(d['uploader_name'])} · ${fmtDate(d['uploaded_at'])}',
                  trailing: Eyebrow((d['file_type'] ?? '').toString()),
                  onTap: () {
                    final url = (d['file_url'] ?? '').toString();
                    if (url.isEmpty) return;
                    final name = (d['document_name'] ?? '').toString();
                    final ext = (d['file_type'] ?? '').toString();
                    final file = ext.isNotEmpty && !name.toLowerCase().endsWith('.${ext.toLowerCase()}') ? '$name.$ext' : name;
                    openServerFile(context, api, url, name: file.isEmpty ? null : file);
                  },
                ),
            ]),
        ],
      ),
    );
  }
}
