import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../shell/routes.dart';
import '_shared.dart';
import 'purchase_order_screen.dart';

/// One vendor quotation: lines, total, status, print, send by WhatsApp / email, share history and
/// vendor payments (web QuotationDetailPage.jsx).
class QuotationDetailScreen extends StatefulWidget {
  final int projectId;
  final int quotationId;
  const QuotationDetailScreen({super.key, required this.projectId, required this.quotationId});

  @override
  State<QuotationDetailScreen> createState() => _QuotationDetailScreenState();
}

class _Data {
  final Map<String, dynamic> q;
  final Map<String, dynamic>? vendor;
  final List<Map<String, dynamic>> log;
  _Data(this.q, this.vendor, this.log);
}

class _QuotationDetailScreenState extends State<QuotationDetailScreen> {
  String? _title;

  Future<_Data> _load() async {
    final api = context.read<ApiClient>();
    final id = widget.quotationId;
    final res = await Future.wait([api.get('/quotations/$id'), api.get('/quotations/$id/share-log')]);
    final q = Map<String, dynamic>.from(res[0] as Map);
    Map<String, dynamic>? vendor;
    if (q['vendor_id'] != null) {
      try {
        vendor = asMap(await api.get('/vendors/${q['vendor_id']}'));
      } catch (_) {
        vendor = null;
      }
    }
    if (mounted && _title != q['quotation_number']) setState(() => _title = q['quotation_number'] as String?);
    return _Data(q, vendor, asMaps(res[1]));
  }

  Future<void> _setStatus(String? status, Future<void> Function() reload) async {
    if (status == null) return;
    final api = context.read<ApiClient>();
    final ok = await runAction(context, () => api.patch('/quotations/${widget.quotationId}', data: {'status': status}),
        success: 'Status set to $status');
    if (ok) await reload();
  }

  Future<void> _print(Map<String, dynamic> q) async {
    await downloadAndOpen(context, context.read<ApiClient>(), '/quotations/${widget.quotationId}/print',
        fallbackName: '${q['quotation_number'] ?? 'quotation'}.html');
  }

  Future<void> _send(String channel, _Data d, Future<void> Function() reload) async {
    final sent = await showAppSheet<bool>(context,
        title: channel == 'whatsapp' ? 'Send via WhatsApp' : 'Send via Email',
        subtitle: 'Contact is read live from the vendor record.',
        builder: (ctx) => _SendForm(quotationId: widget.quotationId, channel: channel, vendor: d.vendor));
    if (sent == true) await reload();
  }

  Future<void> _pay(Map<String, dynamic> q) async {
    await showAppSheet<bool>(context,
        title: 'Record Vendor Payment',
        subtitle: 'Against ${q['quotation_number']} — ${q['vendor_name']}. Appears immediately on the project balance sheet.',
        builder: (ctx) => _VendorPaymentForm(projectId: widget.projectId, quotationId: widget.quotationId, q: q));
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final canPay = user?.roleIn(['Admin', 'Accountant']) ?? false;
    return AppScaffold(
      title: _title ?? 'Quotation',
      subtitle: 'Quotation',
      body: AsyncView<_Data>(
        load: _load,
        builder: (context, d, reload) => RefreshList(onRefresh: reload, children: _body(context, d, reload, canPay)),
      ),
    );
  }

  List<Widget> _body(BuildContext context, _Data d, Future<void> Function() reload, bool canPay) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final q = d.q;
    final po = asMap(q['purchase_order']);
    final livePO = po != null && po['status'] != 'CANCELLED';
    final lines = asMaps(q['line_items']);

    return [
      Surface(
        margin: const EdgeInsets.symmetric(horizontal: kGutter),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Eyebrow('Quotation', color: p.accentText),
          const SizedBox(height: 4),
          Text(dash(q['quotation_number']), style: tt.headlineMedium),
          const SizedBox(height: 6),
          Text(
            [
              dash(q['vendor_name']),
              fmtDate(q['quotation_date']),
              if (q['valid_until'] != null) 'Valid until ${fmtDate(q['valid_until'])}',
            ].join(' · '),
            style: tt.bodyMedium?.copyWith(color: p.fgMuted),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [QuotationStatusChip(q['status'] as String?), QuotationPOChip(po)]),
          const SizedBox(height: 14),
          AppDropdown<String>(
            label: 'Set status…',
            value: null,
            items: const [
              ('draft', 'draft'),
              ('sent', 'sent'),
              ('accepted', 'accepted'),
              ('rejected', 'rejected'),
              ('expired', 'expired'),
            ],
            onChanged: (v) => _setStatus(v, reload),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            SmallAction(label: 'Print', icon: Icons.print_outlined, onPressed: () => _print(q)),
            SmallAction(
                label: 'WhatsApp', icon: Icons.chat_outlined, color: p.success, onPressed: () => _send('whatsapp', d, reload)),
            SmallAction(label: 'Email', icon: Icons.mail_outline, color: p.info, onPressed: () => _send('email', d, reload)),
          ]),
          if (canPay) ...[
            const SizedBox(height: 10),
            if (livePO)
              SubmitButton(
                label: 'Pay on ${po['po_number']}',
                icon: Icons.currency_rupee,
                onPressed: () async {
                  await push(context, PurchaseOrderScreen(projectId: widget.projectId, quotationId: widget.quotationId));
                  reload();
                },
              )
            else
              SubmitButton(label: 'Record Payment', icon: Icons.currency_rupee, onPressed: () => _pay(q)),
          ],
        ]),
      ),
      const SectionHeader('Line items'),
      RowGroup(
        footer: TotalBand('Quotation Total', inr(q['quotation_total']), valueColor: p.accentText),
        children: [
          for (final li in lines)
            RowTile(
              title: dash(li['product_name']),
              subtitle: [
                '${qty(li['quantity'])} ${li['unit'] ?? ''} × ${inr(li['unit_price'])}',
                if ((li['notes'] ?? '').toString().isNotEmpty) li['notes'].toString(),
              ].join('\n'),
              trailing: Text(inr(li['line_total']), style: tabular(tt.titleSmall).copyWith(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      const SectionHeader('Share History'),
      if (d.log.isEmpty)
        const InlineNote('Not shared yet.')
      else
        RowGroup(children: [
          for (final s in d.log)
            RowTile(
              leading: Icon(s['channel'] == 'whatsapp' ? Icons.chat_outlined : Icons.mail_outline,
                  size: 18, color: s['channel'] == 'whatsapp' ? p.success : p.accentText),
              title: s['channel'] == 'whatsapp' ? 'Whatsapp' : 'Email',
              subtitle: 'to ${dash(s['sent_to'])} · by ${dash(s['sent_by'])}\n${fmtDateTime(s['sent_at'], empty: '')}',
              trailing: StatusChip(s['status'] as String?,
                  label: s['status'] as String?, tone: s['status'] == 'sent' ? Tone.success : Tone.danger, dense: true),
            ),
        ]),
    ];
  }
}

class _SendForm extends StatefulWidget {
  final int quotationId;
  final String channel;
  final Map<String, dynamic>? vendor;
  const _SendForm({required this.quotationId, required this.channel, required this.vendor});

  @override
  State<_SendForm> createState() => _SendFormState();
}

class _SendFormState extends State<_SendForm> {
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    final api = context.read<ApiClient>();
    try {
      final r = asMap(await api.post('/quotations/${widget.quotationId}/send', data: {'channel': widget.channel})) ?? {};
      if (!mounted) return;
      final wa = r['wa_link'] as String?;
      if (wa != null && wa.isNotEmpty) await openExternal(context, wa);
      if (!mounted) return;
      if (r['status'] == 'sent') {
        showToast(context, 'Sent via ${widget.channel} to ${r['sent_to']}');
      } else {
        showToast(context, 'Email delivery failed (logged in share history) — check SMTP settings', error: true);
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final wa = widget.channel == 'whatsapp';
    final v = widget.vendor ?? const <String, dynamic>{};
    final raw = (wa ? v['phone'] : v['email'])?.toString().trim() ?? '';
    final contact = raw.isEmpty ? null : raw;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Surface(
        child: InfoTile(label: wa ? 'Vendor Phone' : 'Vendor Email', value: contact ?? 'Not on file'),
      ),
      if (contact == null) ...[
        const SizedBox(height: 10),
        Text('This vendor has no ${wa ? 'phone number' : 'email'} on file. Add it in the Vendor record first.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.danger)),
      ],
      const SizedBox(height: 18),
      SubmitButton(label: 'Send', icon: Icons.send_outlined, busy: _sending, onPressed: contact == null ? null : _send),
    ]);
  }
}

class _VendorPaymentForm extends StatefulWidget {
  final int projectId;
  final int quotationId;
  final Map<String, dynamic> q;
  const _VendorPaymentForm({required this.projectId, required this.quotationId, required this.q});

  @override
  State<_VendorPaymentForm> createState() => _VendorPaymentFormState();
}

class _VendorPaymentFormState extends State<_VendorPaymentForm> {
  late final TextEditingController _amount = TextEditingController(text: inputNum(widget.q['quotation_total']));
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'BankTransfer';
  bool _paying = false;

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amt = toNum(_amount.text);
    if (!(amt > 0)) {
      showToast(context, 'Enter a valid amount', error: true);
      return;
    }
    setState(() => _paying = true);
    final api = context.read<ApiClient>();
    try {
      await api.post('/projects/${widget.projectId}/vendor-payments', data: {
        'vendor_id': widget.q['vendor_id'],
        'amount': amt,
        'payment_method': _method,
        'reference_no': _ref.text.trim().isEmpty ? null : _ref.text,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text,
        'quotation_id': widget.quotationId,
      });
      if (!mounted) return;
      showToast(context, 'Payment recorded — reflected in the project balance sheet');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(controller: _amount, label: 'Amount (₹)', money: true, requiredField: true),
        kFieldGap,
        AppDropdown<String>(
          label: 'Payment Method',
          value: _method,
          items: [for (final m in kPayMethods) (m, m)],
          onChanged: (v) {
            if (v != null) setState(() => _method = v);
          },
        ),
        kFieldGap,
        AppTextField(controller: _ref, label: 'Reference No.', capitalization: TextCapitalization.characters),
        kFieldGap,
        AppTextField(controller: _notes, label: 'Notes'),
        const SizedBox(height: 18),
        SubmitButton(label: 'Record Payment', busy: _paying, onPressed: _submit),
      ]);
}
