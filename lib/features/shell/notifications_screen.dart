import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import 'routes.dart';

/// Unread alert count, polled by the shell every 30 s (web NotificationBell `refetchInterval: 30000`).
class NotificationCount extends ChangeNotifier {
  final ApiClient _api;
  NotificationCount(this._api);
  int unread = 0;

  Future<void> refresh() async {
    try {
      final d = await _api.get('/notifications/unread-count');
      final c = toInt((d as Map)['count']);
      if (c != unread) {
        unread = c;
        notifyListeners();
      }
    } catch (_) {}
  }
}

/// Icon and tone for an alert type: red when something stopped or was refused, green when it went
/// through, amber when it waits on someone; the icon says which area it came from (web `look`).
(IconData, Tone) _look(String type) {
  if (type.contains('Blocked')) return (Icons.warning_amber_rounded, Tone.danger);
  if (type.contains('Delayed')) return (Icons.schedule, Tone.warning);
  if (RegExp('Rejected|Cancelled|ShortClosed').hasMatch(type)) return (Icons.cancel_outlined, Tone.danger);
  if (RegExp('Approved|Released').hasMatch(type)) return (Icons.check_circle_outline, Tone.success);
  final tone = RegExp('Requested|Enquiry|New|Assigned').hasMatch(type) ? Tone.warning : Tone.neutral;
  if (type.startsWith('Material')) return (Icons.assignment_outlined, tone);
  if (type.startsWith('PO')) return (Icons.local_shipping_outlined, type == 'PODelivered' ? Tone.success : tone);
  if (type.startsWith('Contractor')) return (Icons.engineering_outlined, tone);
  if (type.startsWith('PettyCash')) {
    return type == 'PettyCashTopup' ? (Icons.currency_rupee, Tone.success) : (Icons.account_balance_wallet_outlined, tone);
  }
  if (type == 'Inventory') return (Icons.inventory_2_outlined, Tone.warning);
  if (type == 'ChangeOrder') return (Icons.edit_document, Tone.warning);
  if (RegExp('^(Leave|SiteVisit)').hasMatch(type)) return (Icons.calendar_today_outlined, tone);
  if (type.startsWith('Lead')) return (Icons.person_add_alt, tone);
  return (Icons.notifications_none, Tone.neutral);
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final count = context.read<NotificationCount>();
    final key = GlobalKey<AsyncViewState<List>>();
    return AppScaffold(
      title: 'Alerts',
      actions: [
        TextButton.icon(
          onPressed: () async {
            final ok = await runAction(context, () => api.post('/notifications/read-all'));
            if (ok) {
              count.refresh();
              key.currentState?.reload();
            }
          },
          icon: const Icon(Icons.done_all, size: 18),
          label: const Text('Mark all read'),
        ),
      ],
      body: AsyncView<List>(
        key: key,
        load: () async => (await api.get('/notifications')) as List,
        builder: (context, items, reload) => RefreshList(
          onRefresh: () async {
            await reload();
            await count.refresh();
          },
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (items.isEmpty)
              const EmptyState(
                icon: Icons.notifications_none,
                title: 'No alerts yet',
                message: 'Requests waiting for you, decisions on yours, deliveries and site problems show up here.',
              ),
            for (final raw in items) _NotificationRow(n: Map<String, dynamic>.from(raw as Map), onChanged: reload),
          ],
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final Map<String, dynamic> n;
  final Future<void> Function() onChanged;
  const _NotificationRow({required this.n, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final (icon, tone) = _look((n['type'] ?? '') as String);
    final read = n['is_read'] == true;
    return Opacity(
      opacity: read ? 0.6 : 1,
      child: InkWell(
        onTap: () async {
          final api = context.read<ApiClient>();
          final count = context.read<NotificationCount>();
          if (!read) {
            try {
              await api.post('/notifications/${n['id']}/read');
            } catch (_) {}
            count.refresh();
            onChanged();
          }
          if (!context.mounted) return;
          final link = n['link'] as String?;
          if (link != null && link.isNotEmpty) {
            openWebPath(context, link);
          } else if (n['project_id'] != null) {
            openWebPath(context, '/admin/projects/${n['project_id']}${n['type'] == 'ChangeOrder' ? '?tab=variations' : ''}');
          }
        },
        child: Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
          padding: const EdgeInsets.fromLTRB(kGutter, 14, kGutter, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 19, color: p.tone(tone))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(dash(n['title']), style: tt.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  if (!read) Container(width: 7, height: 7, margin: const EdgeInsets.only(left: 8), color: p.accent),
                ]),
                if ((n['message'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(n['message'].toString(), style: tt.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 5),
                Eyebrow(timeAgo(n['created_at'])),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
