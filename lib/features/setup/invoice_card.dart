import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';

// Read-only invoice card for the client detail page: the web's InvoiceCard (ProjectFinancePage.jsx)
// with canWrite=false, plus its print / WhatsApp / email actions (utils/invoiceShare.js).

String _money(dynamic n) => inr(n);

/// `invoiceText` from invoiceShare.js.
String invoiceText(Map<String, dynamic> inv, String? projectName, String? brand) {
  final b = StringBuffer('${brand ?? 'Sitera'} — Invoice ${inv['invoice_number']}\n');
  if (projectName != null && projectName.isNotEmpty) b.write('Project: $projectName\n');
  b.write('Amount: ${_money(inv['amount'])}\nTax: ${_money(inv['tax_amount'])}\nTotal: ${_money(inv['total'])}\n');
  b.write('Paid: ${_money(inv['paid_amount'])}\nBalance Due: ${_money(inv['balance_due'])}\n');
  b.write('Issue Date: ${fmtDate(inv['issue_date'])}\nDue Date: ${fmtDate(inv['due_date'])}\nStatus: ${inv['status']}');
  final desc = (inv['description'] ?? '').toString();
  if (desc.isNotEmpty) b.write('\nNote: $desc');
  return b.toString();
}

String _attr(Object? s) =>
    (s ?? '').toString().replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');

/// `printInvoice`: the same letterhead + layout as the web, saved as HTML and opened (print from the viewer).
Future<void> printInvoice(BuildContext context, Map<String, dynamic> inv, {String? projectName, String? clientName}) async {
  final api = context.read<ApiClient>();
  Map<String, dynamic>? lh;
  try {
    final pid = inv['project_id'];
    lh = Map<String, dynamic>.from(
        await api.get('/company/letterhead', params: pid != null ? {'project_id': pid} : {}) as Map);
  } catch (_) {
    lh = null;
  }
  final logo = lh?['logo_url'] != null
      ? '<img id="inv-logo" src="${_attr(ApiConfig.fileUrl(lh!['logo_url'].toString()))}" alt="${_attr(lh['name'])}" style="max-height:64px;max-width:240px;object-fit:contain" />'
      : '<img id="inv-logo" src="${_attr(ApiConfig.baseUrlSync)}/sitera-logo-horizontal.png" alt="Sitera ERP" style="max-height:56px;max-width:240px;object-fit:contain" />';
  final lines = (lh?['lines'] as List? ?? const []).map((l) => '<div>${_attr(l)}</div>').join();
  final brand = '<div>$logo${lh != null ? '<div class="issuer"><b>${_attr(lh['name'])}</b>$lines</div>' : ''}</div>';
  final desc = (inv['description'] ?? '').toString();
  final html = '''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Invoice ${inv['invoice_number']}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: Arial, Helvetica, sans-serif; color: #18181b; padding: 40px; }
  .head { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 4px solid #f97316; padding-bottom: 16px; margin-bottom: 24px; }
  .inv-no { font-size: 20px; font-weight: 700; text-align: right; }
  .status { display: inline-block; margin-top: 6px; padding: 3px 10px; border: 1px solid #18181b; font-size: 11px; letter-spacing: 1px; text-transform: uppercase; }
  .meta { display: flex; flex-wrap: wrap; gap: 24px 40px; margin-bottom: 24px; font-size: 13px; }
  .meta b { display: block; font-size: 11px; text-transform: uppercase; letter-spacing: 1px; color: #71717a; margin-bottom: 3px; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 24px; }
  th { text-align: left; font-size: 11px; text-transform: uppercase; letter-spacing: 1px; color: #71717a; border-bottom: 2px solid #18181b; padding: 8px 6px; }
  td { padding: 10px 6px; border-bottom: 1px solid #e4e4e7; font-size: 14px; }
  td.r, th.r { text-align: right; }
  .totals { margin-left: auto; width: 280px; max-width: 100%; font-size: 14px; }
  .totals div { display: flex; justify-content: space-between; padding: 6px 0; }
  .totals .grand { border-top: 2px solid #18181b; font-weight: 800; font-size: 16px; }
  .balance { color: #dc2626; font-weight: 700; }
  .issuer { margin-top: 8px; font-size: 12px; color: #52525b; white-space: pre-line; }
  .issuer b { display: block; font-size: 15px; color: #18181b; }
  .foot { margin-top: 48px; font-size: 11px; color: #71717a; border-top: 1px solid #e4e4e7; padding-top: 12px; }
  @media print { body { padding: 20px; } }
</style></head><body>
  <div class="head">
    $brand
    <div class="inv-no">INVOICE ${inv['invoice_number']}<br/><span class="status">${inv['status']}</span></div>
  </div>
  <div class="meta">
    ${projectName != null ? '<div><b>Project</b>${_attr(projectName)}</div>' : ''}
    ${clientName != null ? '<div><b>Billed To</b>${_attr(clientName)}</div>' : ''}
    <div><b>Issue Date</b>${fmtDate(inv['issue_date'])}</div>
    <div><b>Due Date</b>${fmtDate(inv['due_date'])}</div>
  </div>
  <table>
    <tr><th>Description</th><th class="r">Amount</th></tr>
    <tr><td>${desc.isEmpty ? 'Construction work — progress billing' : _attr(desc)}</td><td class="r">${_money(inv['amount'])}</td></tr>
    <tr><td>Tax</td><td class="r">${_money(inv['tax_amount'])}</td></tr>
  </table>
  <div class="totals">
    <div><span>Total</span><span>${_money(inv['total'])}</span></div>
    <div><span>Paid</span><span>${_money(inv['paid_amount'])}</span></div>
    <div class="grand"><span>Balance Due</span><span class="balance">${_money(inv['balance_due'])}</span></div>
  </div>
  <div class="foot">${_attr(lh?['name'] ?? 'Sitera')} · Printed ${fmtDate(DateTime.now())}</div>
</body></html>''';
  if (!context.mounted) return;
  final safe = 'Invoice-${inv['invoice_number']}'.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  await openBytes(context, utf8.encode(html), '$safe.html');
}

class ClientInvoiceCard extends StatelessWidget {
  final Map<String, dynamic> inv;
  const ClientInvoiceCard({super.key, required this.inv});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final brand = context.read<AuthProvider>().user?.tenantName;
    final desc = (inv['description'] ?? '').toString();
    return Surface(
      margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text((inv['invoice_number'] ?? '').toString(),
                  style: tt.titleMedium?.copyWith(color: p.accentText, fontWeight: FontWeight.w700)),
              StatusChip(inv['status']?.toString(), dense: true),
            ]),
          ),
          Text(inr(inv['total']), style: tabular(tt.titleSmall)),
          PopupMenuButton<String>(
            tooltip: 'Share',
            icon: Icon(Icons.more_vert, size: 20, color: p.fgMuted),
            onSelected: (v) {
              final text = invoiceText(inv, null, brand);
              switch (v) {
                case 'print':
                  printInvoice(context, inv);
                case 'whatsapp':
                  openExternal(context, 'https://wa.me/?text=${Uri.encodeComponent(text)}');
                case 'email':
                  final subject = 'Invoice ${inv['invoice_number']} — ${brand ?? 'Sitera'}';
                  openExternal(context, 'mailto:?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(text)}');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'print', child: ListTile(leading: Icon(Icons.print_outlined), title: Text('Print invoice'))),
              PopupMenuItem(value: 'whatsapp', child: ListTile(leading: Icon(Icons.chat_outlined), title: Text('Send via WhatsApp'))),
              PopupMenuItem(value: 'email', child: ListTile(leading: Icon(Icons.mail_outline), title: Text('Send via Email'))),
            ],
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Due ${fmtDate(inv['due_date'])}', style: tt.bodySmall),
            if (desc.isNotEmpty) ...[const SizedBox(height: 2), Text(desc, style: tt.bodySmall)],
            const SizedBox(height: 8),
            Row(children: [
              Text('Paid ${inr(inv['paid_amount'])}', style: tabular(tt.bodySmall).copyWith(color: p.tone(Tone.success))),
              const SizedBox(width: 16),
              Text('Balance ${inr(inv['balance_due'])}', style: tabular(tt.bodySmall).copyWith(color: p.tone(Tone.warning))),
            ]),
          ]),
        ),
      ]),
    );
  }
}
