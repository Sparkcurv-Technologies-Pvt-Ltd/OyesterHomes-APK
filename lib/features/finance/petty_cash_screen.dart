import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import '../org/org_provider.dart';
import 'finance_shared.dart';

/// Petty cash (web PettyCashPage.jsx, routers/petty_cash.py): the MD (Admin) gives cash and decides
/// requests; site engineers and project managers log each bill against a project and can ask for more
/// once their balance is at the limit or below. Top-level page: no AppBar.
class PettyCashScreen extends StatelessWidget {
  const PettyCashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(body: user?.role == 'Admin' ? const _AdminView() : const _HolderView());
  }
}

String _limitText(dynamic limit) => inr(limit);

// ───────────────────────────────────────────────────────── ledger

class _Ledger extends StatelessWidget {
  final List<Map<String, dynamic>> entries;
  final EdgeInsetsGeometry margin;
  const _Ledger({required this.entries, this.margin = const EdgeInsets.symmetric(horizontal: kGutter)});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text('No entries yet.', textAlign: TextAlign.center, style: tt.bodySmall),
      );
    }
    return RowGroup(margin: margin, children: [
      for (final e in entries)
        Builder(builder: (context) {
          final topup = e['kind'] == 'topup';
          final desc = (e['description'] ?? '').toString();
          final bill = (e['bill_url'] ?? '').toString();
          return RowTile(
            title: desc.isNotEmpty ? desc : (topup ? 'Top-up' : 'Expense'),
            subtitleWidget: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(fmtDate(e['entry_date']), style: tabular(tt.bodySmall)),
              if ((e['project_name'] ?? '').toString().isNotEmpty) Text('${e['project_name']}', style: tt.bodySmall),
              if (bill.isNotEmpty)
                InkWell(
                  onTap: () => openServerFile(context, apiOf(context), bill),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.receipt_outlined, size: 14, color: p.accentText),
                      const SizedBox(width: 3),
                      Text('bill', style: tt.bodySmall?.copyWith(color: p.accentText, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
            ]),
            trailing: figure(context, '${topup ? '+' : '−'}${inr(e['amount'])}', color: topup ? p.success : null, strong: true),
          );
        }),
    ]);
  }
}

// ───────────────────────────────────────────────────────── holder (site engineer / project manager)

class _HolderData {
  final Map<String, dynamic> me;
  final List<Map<String, dynamic>> projects;
  const _HolderData(this.me, this.projects);
}

class _HolderView extends StatefulWidget {
  const _HolderView();

  @override
  State<_HolderView> createState() => _HolderViewState();
}

class _HolderViewState extends State<_HolderView> {
  final _key = GlobalKey<AsyncViewState<_HolderData>>();

  Future<_HolderData> _load(Map<String, dynamic> orgParams) async {
    final api = apiOf(context);
    final r = await Future.wait([
      api.get('/petty-cash/me'),
      api.get('/projects', params: {'limit': 200, ...orgParams}).catchError((_) => const <String, dynamic>{}),
    ]);
    return _HolderData(jMap(r[0]), jList(jMap(r[1])['items']));
  }

  Future<void> _logBill(List<Map<String, dynamic>> projects) async {
    final saved = await showAppSheet<bool>(context,
        title: 'Log a bill',
        subtitle: 'It is taken from your petty cash and booked to the project.',
        builder: (ctx) => _BillForm(projects: projects));
    if (saved == true) await _key.currentState?.reload();
  }

  Future<void> _ask() async {
    final sent = await showAppSheet<bool>(context, title: 'Ask for more petty cash', builder: (ctx) => const _AskForm());
    if (sent == true) await _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrgProvider>();
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    return AsyncView<_HolderData>(
      key: _key,
      depKey: org.orgKey,
      load: () => _load(org.orgParams),
      builder: (context, d, reload) {
        final me = d.me;
        final balance = toNum(me['balance']);
        final limit = toNum(me['limit']);
        final low = balance <= limit;
        final pending = me['pending_request'] == null ? null : jMap(me['pending_request']);
        final canRequest = me['can_request'] == true;
        return RefreshList(onRefresh: reload, children: [
          Surface(
            margin: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Eyebrow('Cash in hand'),
              const SizedBox(height: 8),
              Text(inr(balance),
                  style: tabular(tt.headlineMedium).copyWith(fontWeight: FontWeight.w700, color: low ? p.warning : p.fg)),
              const SizedBox(height: 4),
              Text(
                pending != null
                    ? 'Asked for ${inr(pending['amount'])} — waiting for the MD'
                    : low
                        ? 'At ${_limitText(limit)} or less — you can ask for more'
                        : 'You can ask for more once this is ${_limitText(limit)} or less',
                style: tt.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: () => _logBill(d.projects),
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('Log a bill'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: canRequest ? _ask : null,
                      icon: const Icon(Icons.front_hand_outlined, size: 18),
                      label: const Text('Ask for more'),
                    ),
                  ),
                ),
              ]),
              if (!canRequest && (me['why_not'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('${me['why_not']}', style: tt.bodySmall),
              ],
            ]),
          ),
          const SectionHeader('My petty cash'),
          _Ledger(entries: jList(me['entries'])),
        ]);
      },
    );
  }
}

class _BillForm extends StatefulWidget {
  final List<Map<String, dynamic>> projects;
  const _BillForm({required this.projects});

  @override
  State<_BillForm> createState() => _BillFormState();
}

class _BillFormState extends State<_BillForm> {
  int? _projectId;
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  String? _date = todayIso();
  String? _billUrl;
  bool _uploading = false;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  bool get _valid => _projectId != null && toNum(_amount.text) > 0 && _desc.text.trim().isNotEmpty;

  Future<void> _upload() async {
    setState(() => _uploading = true);
    final up = await pickAndUpload(context, apiOf(context), extensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf']);
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (up != null) _billUrl = up['url'] as String?;
    });
  }

  Future<void> _save() async {
    if (_busy) return; // one tap = one bill
    setState(() => _busy = true);
    try {
      final r = jMap(await apiOf(context).post('/petty-cash/expenses', data: {
        'project_id': _projectId,
        'amount': toNum(_amount.text),
        'description': _desc.text,
        'entry_date': _date,
        'bill_url': _billUrl,
      }));
      if (!mounted) return;
      showToast(context, 'Logged · ${inr(r['balance'])} left');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppDropdown<int>(
        label: 'Project',
        hint: 'Choose…',
        value: _projectId,
        items: [for (final x in widget.projects) (x['id'] as int, '${x['name']}')],
        onChanged: (v) => setState(() => _projectId = v),
      ),
      kFieldGap,
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: AppTextField(controller: _amount, label: 'Amount (₹)', money: true, onChanged: (_) => setState(() {}))),
        const SizedBox(width: 10),
        Expanded(
          child: DateField(
            label: 'Date',
            value: _date,
            clearable: false,
            lastDate: DateTime.now(),
            onChanged: (v) => setState(() => _date = v),
          ),
        ),
      ]),
      kFieldGap,
      AppTextField(
        controller: _desc,
        label: 'What for',
        hint: 'e.g. Binding wire, tea for crew',
        maxLines: 4,
        minLines: 2,
        onChanged: (_) => setState(() {}),
      ),
      kFieldGap,
      OutlinedButton.icon(
        onPressed: _uploading ? null : _upload,
        icon: _uploading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(_billUrl != null ? Icons.check_circle_outline : Icons.receipt_outlined,
                size: 18, color: _billUrl != null ? p.success : null),
        label: Text(_billUrl != null ? 'Bill photo added ✓' : 'Add bill photo'),
      ),
      const SizedBox(height: 20),
      SubmitButton(label: 'Save', busy: _busy, onPressed: _valid ? _save : null),
    ]);
  }
}

class _AskForm extends StatefulWidget {
  const _AskForm();

  @override
  State<_AskForm> createState() => _AskFormState();
}

class _AskFormState extends State<_AskForm> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => apiOf(context).post('/petty-cash/requests',
          data: {'amount': toNum(_amount.text), 'note': _note.text.isEmpty ? null : _note.text}),
      success: 'Request sent to the MD',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(controller: _amount, label: 'Amount (₹)', money: true, autofocus: true, onChanged: (_) => setState(() {})),
        kFieldGap,
        AppTextField(controller: _note, label: 'Note'),
        const SizedBox(height: 20),
        SubmitButton(label: 'Send to MD', busy: _busy, onPressed: toNum(_amount.text) > 0 ? _send : null),
      ]);
}

// ───────────────────────────────────────────────────────── admin (the MD)

class _AdminView extends StatefulWidget {
  const _AdminView();

  @override
  State<_AdminView> createState() => _AdminViewState();
}

class _AdminViewState extends State<_AdminView> {
  final _key = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  int? _open;
  List<Map<String, dynamic>>? _openEntries;
  bool _busy = false;

  Future<void> _reload() async {
    await _key.currentState?.reload();
    if (_open != null) await _loadHolder(_open!);
  }

  Future<void> _loadHolder(int id) async {
    try {
      final d = jMap(await apiOf(context).get('/petty-cash/holders/$id'));
      if (mounted && _open == id) setState(() => _openEntries = jList(d['entries']));
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    }
  }

  void _toggle(int id) {
    setState(() {
      if (_open == id) {
        _open = null;
      } else {
        _open = id;
        _openEntries = null;
      }
    });
    if (_open != null) _loadHolder(id);
  }

  /// One tap = one top-up / approval (web useSubmitGuard).
  Future<bool> _act(String url, Map<String, dynamic> body, String ok) async {
    if (_busy) return false;
    setState(() => _busy = true);
    final done = await runAction(context, () => apiOf(context).post(url, data: body), success: ok);
    if (mounted) setState(() => _busy = false);
    if (done) await _reload();
    return done;
  }

  Future<void> _approve(Map<String, dynamic> r) async {
    final a = await askAmount(context,
        title: 'Approve request',
        subtitle: '${r['holder']} asks for ${inr(r['amount'])}',
        label: 'Amount to give (₹)',
        initial: r['amount'],
        confirmLabel: 'Approve');
    if (a == null || !mounted) return;
    await _act('/petty-cash/requests/${r['id']}/approve', {'amount': a}, 'Approved and topped up');
  }

  Future<void> _reject(Map<String, dynamic> r) async {
    final n = await promptText(context, title: 'Reject request', label: 'Reason (optional)', confirmLabel: 'Reject');
    if (n == null || !mounted) return;
    await _act('/petty-cash/requests/${r['id']}/reject', {'note': n}, 'Rejected');
  }

  Future<void> _topup(Map<String, dynamic> h) async {
    await showAppSheet<void>(context,
        title: 'Give petty cash to ${h['name']}',
        builder: (ctx) => _TopupForm(onGive: (amount, note) => _act('/petty-cash/topups', {
              'holder_id': h['id'],
              'amount': amount,
              'note': note.isEmpty ? null : note,
            }, 'Cash given')));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    return AsyncView<Map<String, dynamic>>(
      key: _key,
      load: () async => jMap(await apiOf(context).get('/petty-cash')),
      builder: (context, d, reload) {
        final limit = toNum(d['limit']);
        final requests = jList(d['pending_requests']);
        final holders = jList(d['holders']);
        return RefreshList(onRefresh: _reload, children: [
          const SizedBox(height: 4),
          KpiGrid(children: [
            KpiTile(label: 'Held by staff', value: inrCompact(d['total_held']), icon: Icons.account_balance_wallet_outlined),
            KpiTile(label: 'Waiting requests', value: '${requests.length}', icon: Icons.front_hand_outlined),
          ]),
          NoteText('Staff can ask for more only when they hold ${_limitText(limit)} or less.',
              padding: const EdgeInsets.fromLTRB(kGutter, 10, kGutter, 0)),
          if (requests.isNotEmpty) ...[
            const SectionHeader('Requests'),
            RowGroup(children: [
              for (final r in requests)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text.rich(TextSpan(style: tt.bodyMedium, children: [
                      TextSpan(text: '${r['holder']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: ' asks for '),
                      TextSpan(text: inr(r['amount']), style: tabular(null).copyWith(fontWeight: FontWeight.w700)),
                    ])),
                    const SizedBox(height: 3),
                    Text(
                        'has ${inr(r['balance_at_request'])} left${(r['note'] ?? '').toString().isNotEmpty ? ' · ${r['note']}' : ''}',
                        style: tt.bodySmall),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: ToneButton(
                          label: 'Approve',
                          icon: Icons.check,
                          color: p.success,
                          height: 44,
                          onPressed: _busy ? null : () => _approve(r),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _reject(r),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Reject'),
                        ),
                      ),
                    ]),
                  ]),
                ),
            ]),
          ],
          const SectionHeader('Who holds what'),
          if (holders.isEmpty)
            const EmptyLine('No site engineers or project managers yet.')
          else
            RowGroup(children: [
              for (final h in holders)
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  RowTile(
                    title: '${h['name']}',
                    subtitle: '${h['role'] == 'ProjectManager' ? 'Project Manager' : 'Site Engineer'} · spent '
                        '${inr(h['spent_this_month'])} this month${h['pending'] == true ? ' · asked for more' : ''}',
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      figure(context, inr(h['balance']),
                          color: toNum(h['balance']) <= limit ? p.warning : null, strong: true),
                      Icon(_open == h['id'] ? Icons.expand_less : Icons.expand_more, size: 20, color: p.fgSubtle),
                    ]),
                    onTap: () => _toggle(h['id'] as int),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => _topup(h),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Give cash'),
                      ),
                    ),
                  ),
                  if (_open == h['id'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _openEntries == null
                          ? const LoadingView()
                          : _Ledger(entries: _openEntries!, margin: const EdgeInsets.symmetric(horizontal: 12)),
                    ),
                ]),
            ]),
        ]);
      },
    );
  }
}

class _TopupForm extends StatefulWidget {
  final Future<bool> Function(double amount, String note) onGive;
  const _TopupForm({required this.onGive});

  @override
  State<_TopupForm> createState() => _TopupFormState();
}

class _TopupFormState extends State<_TopupForm> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _give() async {
    setState(() => _busy = true);
    final ok = await widget.onGive(toNum(_amount.text), _note.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final amt = toNum(_amount.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTextField(controller: _amount, label: 'Amount (₹)', money: true, autofocus: true, onChanged: (_) => setState(() {})),
      kFieldGap,
      AppTextField(controller: _note, label: 'Note'),
      const SizedBox(height: 20),
      SubmitButton(
        label: 'Give ${inr(amt)}',
        icon: Icons.account_balance_wallet_outlined,
        busy: _busy,
        onPressed: amt > 0 ? _give : null,
      ),
    ]);
  }
}
