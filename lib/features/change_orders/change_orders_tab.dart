import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import 'change_order_form.dart';

const _statuses = ['Draft', 'Pending Client Review', 'Revision Requested', 'Approved', 'Rejected'];

/// The project's Change Orders tab (web ChangeOrdersTab.jsx + ChangeOrderFormModal.jsx + ChangeOrderStatusBadge):
/// variation summary, filters (phase / status / category), PDF and Excel export, new change order, and per
/// change order: details, attachments, estimate history, activity, approve / reject / request revision
/// (Client, Admin), revise / submit for review (Admin, Project Manager, Site Engineer) and record payment
/// (Admin, Accountant). Embedded tab: no Scaffold, scrolls itself, pull-to-refresh.
class ChangeOrdersTab extends StatefulWidget {
  final int projectId;
  final List<dynamic> phases;
  const ChangeOrdersTab({super.key, required this.projectId, required this.phases});

  @override
  State<ChangeOrdersTab> createState() => _ChangeOrdersTabState();
}

class _ChangeOrdersTabState extends State<ChangeOrdersTab> {
  final _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  String _status = '';
  String _category = '';
  String _phase = '';
  final Set<int> _open = {};
  String? _exporting;
  int? _busyId;

  Map<String, dynamic> get _filterParams => {'status': _status, 'category': _category, 'phase_id': _phase};

  Future<Map<String, dynamic>> _load() async => Map<String, dynamic>.from(
      await context.read<ApiClient>().get('/projects/${widget.projectId}/change-orders', params: _filterParams) as Map);

  Future<void> _reload() async => _view.currentState?.reload();

  void _setFilter(void Function() change) {
    setState(change);
    _reload();
  }

  Future<void> _export(String fmt) async {
    setState(() => _exporting = fmt);
    await downloadAndOpen(context, context.read<ApiClient>(), '/projects/${widget.projectId}/change-orders/export',
        fallbackName: 'change-orders.${fmt == 'pdf' ? 'pdf' : 'xlsx'}', params: {'fmt': fmt, ..._filterParams});
    if (mounted) setState(() => _exporting = null);
  }

  Future<void> _openForm([Map<String, dynamic>? co]) async {
    final saved = await showChangeOrderSheet(context, projectId: widget.projectId, phases: widget.phases, co: co);
    if (saved == true) await _reload();
  }

  Future<void> _action(Map<String, dynamic> co, String action) async {
    final number = co['co_number'];
    String? comment;
    if (action == 'approve') {
      final yes = await confirmDialog(context,
          title: 'Approve $number',
          message: 'Approve $number — "${co['title']}" at ${inr(co['estimated_cost'])}?\n\n'
              "This amount will be added to the project's contract value and financial ledger.",
          confirmLabel: 'Approve');
      if (!yes) return;
    } else if (action == 'reject') {
      comment = await promptText(context,
          title: 'Reject $number?', label: 'Add an optional reason', confirmLabel: 'Reject');
      if (comment == null) return;
    } else {
      comment = await promptText(context,
          title: 'Request revision',
          label: 'What should be revised in $number? (required)',
          confirmLabel: 'Request Revision',
          required: true);
      if (comment == null || comment.trim().isEmpty) return;
    }
    if (!mounted) return;
    final api = context.read<ApiClient>();
    setState(() => _busyId = co['id'] as int);
    final ok = await runAction(
      context,
      () => api.post('/change-orders/${co['id']}/$action',
          data: {'comment': (comment ?? '').isEmpty ? null : comment, 'confirm': true}),
      success: action == 'approve'
          ? '$number approved'
          : action == 'reject'
              ? '$number rejected'
              : 'Revision requested',
    );
    if (mounted) setState(() => _busyId = null);
    if (ok) await _reload();
  }

  Future<void> _recordPayment(Map<String, dynamic> co) async {
    final saved = await showAppSheet<bool>(context,
        title: 'Record Payment',
        subtitle: 'Record client payment for ${co['co_number']} — "${co['title']}".\n'
            'The amount will be credited to the project balance sheet and a receipt emailed to the client.',
        builder: (ctx) => _PaymentForm(co: co));
    if (saved == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().user?.role;
    return AsyncView<Map<String, dynamic>>(
      key: _view,
      load: _load,
      builder: (context, data, reload) => _body(context, data, reload, role),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> data, Future<void> Function() reload, String? role) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final canContract = const ['Admin', 'ProjectManager', 'SiteEngineer'].contains(role);
    final canDecide = const ['Client', 'Admin'].contains(role);
    final canPay = const ['Admin', 'Accountant'].contains(role);
    final s = data['summary'] is Map ? Map<String, dynamic>.from(data['summary'] as Map) : null;
    final cos = (data['change_orders'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final filtered = _status.isNotEmpty || _category.isNotEmpty || _phase.isNotEmpty;
    final approvedCount = toInt(s?['approved_count']);

    return RefreshList(
      onRefresh: reload,
      children: [
        if (canContract)
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 12),
            child: SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Change Order'),
              ),
            ),
          ),
        if (s != null && approvedCount > 0)
          Surface(
            margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 12),
            padding: const EdgeInsets.all(14),
            color: p.toneFill(Tone.warning),
            borderColor: p.toneBorder(Tone.warning),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 18, color: p.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(style: tt.bodyMedium?.copyWith(color: p.warning), children: [
                    const TextSpan(text: 'Your project cost has increased by '),
                    TextSpan(text: inr(s['approved_variations']), style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' (${s['increase_pct']}%) due to '),
                    TextSpan(text: '$approvedCount', style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' approved modification${approvedCount != 1 ? 's' : ''}. Revised contract value: '),
                    TextSpan(text: inr(s['revised_contract_value']), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const TextSpan(text: '.'),
                  ]),
                ),
              ),
            ]),
          ),
        if (s != null)
          KpiGrid(children: [
            KpiTile(label: 'Original Contract', value: inr(s['original_budget'])),
            KpiTile(
              label: 'Approved Variations',
              value: '+${inr(s['approved_variations'])}',
              sub: '$approvedCount approved · +${s['increase_pct']}% of contract',
              tone: Tone.accent,
            ),
            KpiTile(label: 'Revised Contract Value', value: inr(s['revised_contract_value']), tone: Tone.accent),
            KpiTile(label: 'Pending Review', value: inr(s['pending_co_value']), tone: Tone.info),
          ]),
        SectionHeader(
          'Change Orders · ${cos.length}',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            _ExportButton(label: 'PDF', icon: Icons.picture_as_pdf_outlined, busy: _exporting == 'pdf', onTap: () => _export('pdf')),
            const SizedBox(width: 6),
            _ExportButton(label: 'Excel', icon: Icons.grid_on_outlined, busy: _exporting == 'xlsx', onTap: () => _export('xlsx')),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
          child: Row(children: [
            _FilterMenu(
              allLabel: 'All phases',
              value: _phase,
              options: [
                for (final ph in widget.phases)
                  if (ph is Map) ('${ph['id']}', '${ph['name']}'),
              ],
              onChanged: (v) => _setFilter(() => _phase = v),
            ),
            const SizedBox(width: 8),
            _FilterMenu(
              allLabel: 'All statuses',
              value: _status,
              options: [for (final st in _statuses) (st, st)],
              onChanged: (v) => _setFilter(() => _status = v),
            ),
            const SizedBox(width: 8),
            _FilterMenu(
              allLabel: 'All categories',
              value: _category,
              options: [for (final c in coCategories) (c, c)],
              onChanged: (v) => _setFilter(() => _category = v),
            ),
          ]),
        ),
        if (cos.isEmpty)
          Surface(
            margin: const EdgeInsets.symmetric(horizontal: kGutter),
            padding: EdgeInsets.zero,
            child: EmptyState(
              icon: Icons.difference_outlined,
              title: filtered ? 'No change orders match the selected filters.' : 'No change orders yet',
              message: filtered
                  ? null
                  : 'Client modifications and scope variations will appear here, separate from the base contract.',
            ),
          )
        else
          for (final co in cos) ...[
            _ChangeOrderCard(
              co: co,
              open: _open.contains(co['id']),
              busy: _busyId == co['id'],
              canDecide: canDecide,
              canContract: canContract,
              canPay: canPay,
              onToggle: () => setState(() {
                if (!_open.remove(co['id'])) _open.add(co['id'] as int);
              }),
              onAction: (a) => _action(co, a),
              onRevise: () => _openForm(co),
              onRecordPayment: () => _recordPayment(co),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _ExportButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback onTap;
  const _ExportButton({required this.label, required this.icon, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10)),
        icon: busy
            ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, size: 15),
        label: Text(label),
      );
}

/// A filter as a chip that opens a menu ("All statuses", "Approved", ...). '' is "All".
class _FilterMenu extends StatelessWidget {
  final String allLabel;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  const _FilterMenu({required this.allLabel, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final current = options.where((o) => o.$1 == value).firstOrNull;
    final active = value.isNotEmpty;
    return PopupMenuButton<String>(
      tooltip: allLabel,
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        PopupMenuItem(value: '', child: Text(allLabel)),
        for (final (v, l) in options) PopupMenuItem(value: v, child: Text(l)),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? p.accent.withValues(alpha: 0.12) : p.card,
          border: Border.all(color: active ? p.accent : p.inputBorder),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(current?.$2 ?? allLabel,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? p.accentText : p.fgMuted)),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down, size: 18, color: p.fgMuted),
        ]),
      ),
    );
  }
}

class _ChangeOrderCard extends StatelessWidget {
  final Map<String, dynamic> co;
  final bool open;
  final bool busy;
  final bool canDecide;
  final bool canContract;
  final bool canPay;
  final VoidCallback onToggle;
  final ValueChanged<String> onAction;
  final VoidCallback onRevise;
  final VoidCallback onRecordPayment;
  const _ChangeOrderCard({
    required this.co,
    required this.open,
    required this.busy,
    required this.canDecide,
    required this.canContract,
    required this.canPay,
    required this.onToggle,
    required this.onAction,
    required this.onRevise,
    required this.onRecordPayment,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final status = (co['status'] ?? '').toString();
    final decidable = const ['Pending Client Review', 'Revision Requested'].contains(status);
    final revisable = const ['Draft', 'Pending Client Review', 'Revision Requested', 'Rejected'].contains(status);
    final amount = status == 'Approved' && co['approved_cost'] != null ? co['approved_cost'] : co['estimated_cost'];
    final days = toInt(co['estimated_time_impact_days']);
    final attachments =
        (co['attachments'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final revisions = (co['revisions'] as List? ?? const []).whereType<Map>().toList();
    final events = (co['events'] as List? ?? const []).whereType<Map>().toList();
    final meta = [
      '${co['category'] ?? ''}${co['phase_name'] != null ? ' · ${co['phase_name']}' : ''}',
      'by ${dash(co['requested_by'])} on ${fmtDate(co['date_requested'])}',
    ].join(' · ');

    final showApprove = canDecide && decidable;
    final showPay = canPay && status == 'Approved' && co['paid_at'] == null;
    final showRevise = canContract && revisable;

    return Surface(
      margin: const EdgeInsets.symmetric(horizontal: kGutter),
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${co['co_number']}',
                        style: tabular(tt.labelLarge).copyWith(color: p.accentText, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${co['title']}', style: tt.titleSmall),
                    const SizedBox(height: 3),
                    Text(meta, style: tt.bodySmall),
                  ]),
                ),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('+${inr(amount)}', style: tabular(tt.titleMedium).copyWith(fontWeight: FontWeight.w700)),
                  if (days > 0)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.event_outlined, size: 12, color: p.fgMuted),
                      const SizedBox(width: 3),
                      Text('+$days days', style: tabular(tt.bodySmall)),
                    ]),
                ]),
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 20, color: p.fgSubtle),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                StatusChip(status, label: status, dense: true),
                if (co['paid_at'] != null) const StatusChip('Paid', dense: true),
                if (attachments.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.attach_file, size: 13, color: p.fgMuted),
                    Text('${attachments.length}', style: tt.bodySmall),
                  ]),
              ]),
            ]),
          ),
        ),
        if (open) ...[
          Divider(height: 1, color: p.border),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if ((co['description'] ?? '').toString().isNotEmpty) ...[
                Text('${co['description']}', style: tt.bodyMedium?.copyWith(color: p.fgMuted)),
                const SizedBox(height: 12),
              ],
              if (status == 'Approved') ...[
                Text(
                  'Approved by ${dash(co['approved_by'])} on ${fmtDate(co['approval_date'])} at ${inr(co['approved_cost'])}',
                  style: tt.bodySmall?.copyWith(color: p.success, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
              ],
              if (attachments.isNotEmpty) ...[
                Eyebrow('Photos & Drawings · ${attachments.length}'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in attachments) AttachmentThumb(attachment: a),
                ]),
                const SizedBox(height: 14),
              ],
              if (revisions.isNotEmpty) ...[
                const Eyebrow('Estimate History'),
                const SizedBox(height: 8),
                for (final r in revisions)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: p.muted,
                      border: Border.all(color: p.border),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Text('v${r['version']}', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 10),
                        Text(inr(r['estimated_cost']), style: tabular(tt.bodyMedium).copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Text('+${toInt(r['estimated_time_impact_days'])}d', style: tabular(tt.bodySmall)),
                        const Spacer(),
                        Flexible(
                          child: Text('${dash(r['by'])} · ${fmtDate(r['at'])}',
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(color: p.fgSubtle)),
                        ),
                      ]),
                      if ((r['note'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('"${r['note']}"', style: tt.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                        ),
                    ]),
                  ),
                const SizedBox(height: 10),
              ],
              if (events.isNotEmpty) ...[
                const Eyebrow('Activity'),
                const SizedBox(height: 6),
                for (final e in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text.rich(
                      TextSpan(style: tt.bodySmall, children: [
                        TextSpan(text: dash(e['by']), style: TextStyle(color: p.fg, fontWeight: FontWeight.w600)),
                        TextSpan(text: ' — ${e['action']}'),
                        if ((e['comment'] ?? '').toString().isNotEmpty)
                          TextSpan(text: ': "${e['comment']}"', style: const TextStyle(fontStyle: FontStyle.italic)),
                        TextSpan(text: '  ${fmtDateTime(e['at'])}', style: TextStyle(color: p.fgSubtle)),
                      ]),
                    ),
                  ),
                const SizedBox(height: 6),
              ],
              if (showApprove || showPay || showRevise)
                busy
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                      )
                    : Wrap(spacing: 8, runSpacing: 8, children: [
                        if (showApprove) ...[
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: p.success, foregroundColor: Colors.white),
                            onPressed: () => onAction('approve'),
                            child: const Text('Approve'),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: p.danger, side: BorderSide(color: p.danger.withValues(alpha: 0.6))),
                            onPressed: () => onAction('reject'),
                            child: const Text('Reject'),
                          ),
                          if (status == 'Pending Client Review')
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: p.info, side: BorderSide(color: p.info.withValues(alpha: 0.6))),
                              onPressed: () => onAction('request-revision'),
                              child: const Text('Request Revision'),
                            ),
                        ],
                        if (showPay)
                          FilledButton.icon(
                            onPressed: onRecordPayment,
                            icon: const Icon(Icons.currency_rupee, size: 16),
                            label: const Text('Record Payment'),
                          ),
                        if (showRevise)
                          OutlinedButton(
                            onPressed: onRevise,
                            child: Text(status == 'Draft' ? 'Submit for Review' : 'Revise Estimate'),
                          ),
                      ]),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _PaymentForm extends StatefulWidget {
  final Map<String, dynamic> co;
  const _PaymentForm({required this.co});

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  late final _amount = TextEditingController(text: inputNum(widget.co['approved_cost'] ?? widget.co['estimated_cost']));
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amt = toNumOrNull(_amount.text);
    if (amt == null || !(amt > 0)) {
      showToast(context, 'Enter a valid amount greater than 0', error: true);
      return;
    }
    final api = context.read<ApiClient>();
    setState(() => _busy = true);
    try {
      final r = await api.post('/change-orders/${widget.co['id']}/record-payment', data: {'amount': amt});
      if (!mounted) return;
      final to = r is Map ? r['receipt_to'] : null;
      showToast(
          context,
          r is Map && r['receipt_sent'] == true
              ? 'Payment recorded — receipt emailed to $to'
              : 'Payment recorded and credited to the balance sheet${to != null ? ' (receipt email failed — check SMTP settings)' : ''}');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(controller: _amount, label: 'Amount (₹)', money: true, autofocus: true),
        const SizedBox(height: 18),
        SubmitButton(label: 'Record Payment', icon: Icons.currency_rupee, busy: _busy, onPressed: _save),
      ]);
}
