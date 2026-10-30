import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';
import 'labour_shared.dart';

// Port of ContractorWork.jsx (routers/contractors.py): each executed contract's crew marked person by person
// with their own photo, the crew log, and the payment release chain SE → PM → MD.

String _time(dynamic iso) {
  final d = toDate(iso);
  if (d == null) return '';
  final h = d.hour, m = d.minute.toString().padLeft(2, '0');
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:$m ${h < 12 ? 'am' : 'pm'}';
}

/// Round photo thumbnail of a crew mark; tap opens the full photo.
class _Thumb extends StatelessWidget {
  final String? url;
  final double size;
  const _Thumb(this.url, {this.size = 44});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: p.muted, border: Border.all(color: p.border)),
      child: Icon(Icons.photo_camera_outlined, size: size * 0.38, color: p.fgSubtle),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return GestureDetector(
      onTap: () => openServerFile(context, context.read<ApiClient>(), url!),
      child: ClipOval(
        child: Image.network(
          ApiConfig.fileUrl(url!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder,
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────── crews today (site engineer page)

/// ContractorCrewsToday: every executed contract on the project, each person in its crew marked P / ½ / A.
/// [data] is GET /projects/{id}/contractor-attendance (loaded by the page, which also needs the contract list).
class ContractorCrewsToday extends StatefulWidget {
  final Map<String, dynamic>? data;
  final Future<void> Function() onChanged;
  const ContractorCrewsToday({super.key, required this.data, required this.onChanged});

  @override
  State<ContractorCrewsToday> createState() => _ContractorCrewsTodayState();
}

class _ContractorCrewsTodayState extends State<ContractorCrewsToday> {
  final Map<int, bool> _open = {};

  @override
  Widget build(BuildContext context) {
    final contracts = asMaps(widget.data?['contracts']);
    if (contracts.isEmpty) return const SizedBox.shrink();
    final user = context.watch<AuthProvider>().user;
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final day = todayIso();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Contractor crews today'),
      for (final c in contracts)
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
          child: Builder(builder: (context) {
            final id = c['subcontract_id'] as int;
            final isOpen = _open[id] ?? true;
            final today = asMap(c['today']) ?? const {};
            final workers = asMaps(c['workers']);
            return Surface(
              padding: EdgeInsets.zero,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                InkWell(
                  onTap: () => setState(() => _open[id] = !isOpen),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                    child: Row(children: [
                      Icon(isOpen ? Icons.expand_more : Icons.chevron_right, color: p.fgSubtle),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text((c['vendor_name'] ?? '').toString(), style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                            '${(c['trade'] ?? '').toString().isEmpty ? 'Contractor' : c['trade']} · '
                            '${c['basis'] == 'labour' ? 'labour basis' : 'rate basis'} · due ${inr0(c['due'])}',
                            style: tt.bodySmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${today['present'] ?? 0} of ${today['total'] ?? 0} at work'
                            '${today['day_value'] != null ? ' · ${inr0(today['day_value'])}' : ''}',
                            style: tabular(tt.bodySmall).copyWith(fontWeight: FontWeight.w600, color: p.fg),
                          ),
                        ]),
                      ),
                      if (user?.role != 'Client' && toNum(c['due']) > 0)
                        IconButton(
                          tooltip: 'Ask to pay this contractor',
                          onPressed: () async {
                            if (await showRequestPayment(context, c)) widget.onChanged();
                          },
                          icon: const Icon(Icons.payments_outlined),
                        ),
                    ]),
                  ),
                ),
                if (isOpen) ...[
                  Divider(height: 1, color: p.border),
                  for (var i = 0; i < workers.length; i++) ...[
                    if (i > 0) Divider(height: 1, indent: 14, endIndent: 14, color: p.border),
                    _WorkerRow(key: ValueKey('w${workers[i]['id']}'), w: workers[i], day: day, onSaved: widget.onChanged),
                  ],
                  if (workers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                      child: Text("Add each person in ${c['vendor_name']}'s crew once; then mark them here every day.", style: tt.bodySmall),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          if (await _showAddWorker(context, c)) widget.onChanged();
                        },
                        icon: const Icon(Icons.person_add_alt, size: 18),
                        label: const Text('Add a person to the crew'),
                      ),
                    ),
                  ),
                ],
              ]),
            );
          }),
        ),
    ]);
  }
}

/// One person's row: P / ½ / A. Present or half day needs their photo: the camera opens, the photo is uploaded
/// with the time, and the mark is saved. A photo already taken that day is kept when the mark changes.
class _WorkerRow extends StatefulWidget {
  final Map<String, dynamic> w;
  final String day;
  final Future<void> Function() onSaved;
  const _WorkerRow({super.key, required this.w, required this.day, required this.onSaved});

  @override
  State<_WorkerRow> createState() => _WorkerRowState();
}

class _WorkerRowState extends State<_WorkerRow> {
  final _work = TextEditingController();
  final _focus = FocusNode();
  String? _pending;
  bool _busy = false;

  Map<String, dynamic>? get _mark => asMap(widget.w['mark']);
  String get _savedWork => (_mark?['work_done'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _work.text = _savedWork;
    _focus.addListener(() {
      if (!_focus.hasFocus) _saveWork();
    });
  }

  @override
  void didUpdateWidget(covariant _WorkerRow old) {
    super.didUpdateWidget(old);
    final before = (asMap(old.w['mark'])?['work_done'] ?? '').toString();
    if (before != _savedWork && !_focus.hasFocus) _work.text = _savedWork;
  }

  @override
  void dispose() {
    _focus.dispose();
    _work.dispose();
    super.dispose();
  }

  Future<void> _save(String status, [String? photo]) async {
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post('/contractor-workers/${widget.w['id']}/attendance', data: {
        'work_date': widget.day,
        'status': status,
        if (photo != null) ...{
          'photo_url': photo,
          'photo_taken_at': DateTime.now().toUtc().toIso8601String(),
          'lat': null,
          'lng': null,
        },
      });
      if (mounted) showToast(context, '${widget.w['name']}: ${dayLabel(status).toLowerCase()}');
      await widget.onSaved();
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pending = null;
        });
      }
    }
  }

  Future<void> _tap(String status) async {
    if (status == 'absent' || (_mark?['photo_url'] ?? '').toString().isNotEmpty) {
      setState(() => _pending = status);
      await _save(status);
      return;
    }
    setState(() => _pending = status);
    final up = await pickAndUpload(context, context.read<ApiClient>(), imagesOnly: true);
    if (!mounted) return;
    if (up == null) {
      setState(() => _pending = null);
      return;
    }
    await _save(status, up['url']?.toString());
  }

  Future<void> _saveWork() async {
    final m = _mark;
    final text = _work.text.trim();
    if (m == null || text == _savedWork) return;
    try {
      await context.read<ApiClient>().post('/contractor-workers/${widget.w['id']}/attendance',
          data: {'work_date': widget.day, 'status': m['status'], 'work_done': text});
      await widget.onSaved();
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final w = widget.w;
    final m = _mark;
    final atWork = m != null && m['status'] != 'absent';
    final meta = [
      (w['category'] ?? '').toString(),
      if (m?['day_value'] != null && atWork) inr0(m['day_value']),
      if (m?['photo_taken_at'] != null) fmtDateTime(m!['photo_taken_at']),
      if (m?['lat'] != null) 'GPS ✓',
    ].where((s) => s.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _Thumb(m?['photo_url'] as String?),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((w['name'] ?? '').toString(), style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (meta.isNotEmpty) Text(meta, style: tt.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        StatusSegments(
          options: kCrewMarks,
          value: m?['status'] as String?,
          pending: _pending,
          busy: _busy || _pending != null,
          onTap: _tap,
        ),
        if (atWork) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _work,
            focusNode: _focus,
            minLines: 1,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _focus.unfocus(),
            decoration: const InputDecoration(hintText: 'Work done (optional)', prefixIcon: Icon(Icons.edit_note, size: 20)),
          ),
        ],
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────── add a crew member

Future<bool> _showAddWorker(BuildContext context, Map<String, dynamic> contract) async {
  final r = await showAppSheet<bool>(
    context,
    title: 'Add a person to the crew',
    subtitle: (contract['vendor_name'] ?? '').toString(),
    builder: (ctx) => _AddWorkerForm(contract: contract),
  );
  return r == true;
}

class _AddWorkerForm extends StatefulWidget {
  final Map<String, dynamic> contract;
  const _AddWorkerForm({required this.contract});

  @override
  State<_AddWorkerForm> createState() => _AddWorkerFormState();
}

class _AddWorkerFormState extends State<_AddWorkerForm> {
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _phone = TextEditingController();
  String? _cat;
  bool _busy = false;
  String? _error;

  Map<String, dynamic> get _rates => asMap(widget.contract['labour_rates']) ?? const {};

  @override
  void initState() {
    super.initState();
    _cat = _rates.keys.isEmpty ? null : _rates.keys.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final cat = _rates.isNotEmpty ? _cat : _category.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post('/subcontracts/${widget.contract['subcontract_id']}/workers', data: {
        'name': name,
        'category': (cat ?? '').isEmpty ? null : cat,
        'phone': _phone.text.isEmpty ? null : _phone.text,
      });
      if (!mounted) return;
      showToast(context, "$name added to ${widget.contract['vendor_name']}'s crew");
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorText(e);
      });
      showToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rates = _rates;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTextField(
        controller: _name,
        label: 'Name',
        requiredField: true,
        autofocus: true,
        capitalization: TextCapitalization.words,
        onChanged: (_) => setState(() {}),
      ),
      kFieldGap,
      if (rates.isNotEmpty)
        AppDropdown<String>(
          label: 'Worker type',
          value: _cat,
          items: [for (final k in rates.keys) (k, '$k · ${inr0(rates[k])}/day')],
          onChanged: (v) => setState(() => _cat = v),
        )
      else
        AppTextField(controller: _category, label: 'Type', hint: 'e.g. Electrician', capitalization: TextCapitalization.words),
      kFieldGap,
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+]'))],
        decoration: const InputDecoration(labelText: 'Phone (optional)'),
      ),
      const SizedBox(height: 20),
      SheetError(_error),
      SubmitButton(label: 'Add person', icon: Icons.add, busy: _busy, onPressed: _name.text.trim().isEmpty ? null : _save),
    ]);
  }
}

// ───────────────────────────────────────────────────────── crew log (project Subcontractors tab)

/// CrewLog: the crew roster (take a person off) and each day's marks, person by person.
class CrewLog extends StatefulWidget {
  final int subId;
  const CrewLog({super.key, required this.subId});

  @override
  State<CrewLog> createState() => _CrewLogState();
}

class _CrewLogState extends State<CrewLog> {
  int _tick = 0;

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _load() async {
    final api = context.read<ApiClient>();
    final r = await Future.wait([api.get('/subcontracts/${widget.subId}/workers'), api.get('/subcontracts/${widget.subId}/attendance')]);
    return (asMaps(r[0]), asMaps(r[1]));
  }

  Future<void> _leave(Map<String, dynamic> w) async {
    final ok = await confirmDialog(context,
        title: 'Take ${w['name']} off the crew?', message: 'Their past attendance stays.', confirmLabel: 'Take off', destructive: true);
    if (!ok || !mounted) return;
    if (await runAction(context, () => context.read<ApiClient>().patch('/contractor-workers/${w['id']}', data: {'is_active': false}),
        success: '${w['name']} taken off the crew')) {
      setState(() => _tick++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    return InlineAsync<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)>(
      depKey: _tick,
      load: _load,
      builder: (ctx, data, _) {
        final (workers, log) = data;
        final active = workers.where((w) => w['is_active'] == true).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Eyebrow('Crew (${active.length})'),
          const SizedBox(height: 6),
          if (active.isEmpty)
            Text('No one yet — the site engineer adds each person on the site page.', style: tt.bodySmall)
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final w in active)
                InputChip(
                  label: Text('${w['name']} · ${w['category'] ?? ''}'),
                  deleteIcon: const Icon(Icons.person_remove_outlined, size: 18),
                  deleteButtonTooltipMessage: 'Take off the crew',
                  onDeleted: () => _leave(w),
                ),
            ]),
          const SizedBox(height: 14),
          if (log.isEmpty)
            Text('No crew attendance yet.', style: tt.bodySmall)
          else
            for (final d in log)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.card,
                  border: Border.all(color: p.border),
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(
                    '${fmtDate(d['date'])} · ${d['present']} at work · ${qty(d['man_days'])} man-days'
                    '${d['day_value'] != null ? ' · ${inr0(d['day_value'])}' : ''}',
                    style: tabular(tt.bodySmall).copyWith(fontWeight: FontWeight.w700, color: p.fg),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final person in asMaps(d['people'])) _personChip(context, p, person),
                  ]),
                ]),
              ),
        ]);
      },
    );
  }

  Widget _personChip(BuildContext context, AppPalette p, Map<String, dynamic> person) {
    final status = person['status'];
    final absent = status == 'absent';
    final letter = status == 'half_day' ? '½' : absent ? 'A' : 'P';
    final detail = [
      if (person['photo_taken_at'] != null) _time(person['photo_taken_at']),
      if (person['lat'] != null) 'GPS ✓',
    ].join(' · ');
    return Tooltip(
      message: [
        dayLabel(status),
        if (person['photo_taken_at'] != null) fmtDateTime(person['photo_taken_at']),
        if (person['lat'] != null) 'GPS ✓',
        if ((person['work_done'] ?? '').toString().isNotEmpty) person['work_done'],
      ].join(' · '),
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          border: Border.all(color: absent ? p.toneBorder(Tone.danger) : p.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _Thumb(person['photo_url'] as String?, size: 30),
          const SizedBox(width: 6),
          Text((person['name'] ?? '').toString(), style: TextStyle(fontSize: 12, color: absent ? p.danger : p.fg)),
          const SizedBox(width: 4),
          Text(letter, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: absent ? p.danger : p.fg)),
          if (detail.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(detail, style: tabular(TextStyle(fontSize: 11, color: p.fgSubtle))),
          ],
        ]),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────── ask to pay (RequestPaymentDialog)

/// Site engineer asks to pay a contractor (POST /subcontracts/{id}/payment-requests). True when sent.
Future<bool> showRequestPayment(BuildContext context, Map<String, dynamic> contract) async {
  final nmr = toNum(contract['nmr_deducted']);
  final r = await showAppSheet<bool>(
    context,
    title: 'Ask to pay ${contract['vendor_name']}',
    subtitle: '${inr0(contract['due'])} is due${nmr != 0 ? ' after ${inr0(nmr)} NMR deducted' : ''}. '
        'The PM approves, then the MD releases.',
    builder: (ctx) => _RequestPaymentForm(contract: contract),
  );
  return r == true;
}

class _RequestPaymentForm extends StatefulWidget {
  final Map<String, dynamic> contract;
  const _RequestPaymentForm({required this.contract});

  @override
  State<_RequestPaymentForm> createState() => _RequestPaymentFormState();
}

class _RequestPaymentFormState extends State<_RequestPaymentForm> {
  late final _amount = TextEditingController(text: inputNum(widget.contract['due']));
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post('/subcontracts/${widget.contract['subcontract_id']}/payment-requests',
          data: {'amount': toNum(_amount.text), 'note': _note.text.trim().isEmpty ? null : _note.text.trim()});
      if (!mounted) return;
      showToast(context, 'Sent to the project manager for approval');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorText(e);
      });
      showToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(controller: _amount, label: 'Amount (₹)', money: true, onChanged: (_) => setState(() {})),
        kFieldGap,
        AppTextField(controller: _note, label: 'Note', hint: 'e.g. Block B painting done', maxLines: 3, minLines: 1),
        const SizedBox(height: 20),
        SheetError(_error),
        SubmitButton(
          label: _busy ? 'Sending…' : 'Send for approval',
          busy: _busy,
          onPressed: toNum(_amount.text) > 0 ? _save : null,
        ),
      ]);
}

// ───────────────────────────────────────────────────────── payment requests (PaymentRequestsPanel)

Tone _stepTone(String? s) => switch (s) {
      'Requested' => Tone.warning,
      'PM Approved' => Tone.info,
      'Released' => Tone.success,
      'Rejected' => Tone.danger,
      _ => Tone.neutral,
    };

/// Contractor payment requests on a project: the PM approves, the MD (Admin) reviews and releases, either rejects.
/// Renders nothing when there are none or the user may not read them (as the web).
class PaymentRequestsPanel extends StatefulWidget {
  final int projectId;

  /// Bump to reload from outside.
  final Object? reloadKey;
  final VoidCallback? onChanged;
  const PaymentRequestsPanel({super.key, required this.projectId, this.reloadKey, this.onChanged});

  @override
  State<PaymentRequestsPanel> createState() => _PaymentRequestsPanelState();
}

class _PaymentRequestsPanelState extends State<PaymentRequestsPanel> {
  int _tick = 0;
  bool _busy = false; // one tap = one approval / rejection

  Future<void> _act(String url, Map<String, dynamic> body, String ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    final done = await runAction(context, () => context.read<ApiClient>().post(url, data: body), success: ok);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (done) _tick++;
    });
    if (done) widget.onChanged?.call();
  }

  Future<void> _reject(Map<String, dynamic> r) async {
    final n = await promptText(context, title: 'Reject this request?', label: 'Reason (optional)', confirmLabel: 'Reject');
    if (n == null || !mounted) return;
    await _act('/contractor-payments/${r['id']}/reject', {'note': n}, 'Rejected');
  }

  Future<void> _release(Map<String, dynamic> r) async {
    final ok = await showAppSheet<bool>(
      context,
      title: 'Release payment to ${r['vendor_name']}',
      subtitle: () {
        final pos = asMap(r['position']) ?? const {};
        final nmr = toNum(pos['nmr_deducted']);
        return 'Contract ${inr0(pos['contract_value'])} · paid ${inr0(pos['paid'])}'
            '${nmr != 0 ? ' · NMR ${inr0(nmr)} deducted' : ''} · due ${inr0(pos['due'])}. Change the amount if needed.';
      }(),
      builder: (ctx) => _ReleaseForm(request: r),
    );
    if (ok == true && mounted) {
      setState(() => _tick++);
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    return InlineAsync<Map<String, dynamic>>(
      quiet: true,
      depKey: '${widget.reloadKey}|$_tick',
      load: () async => Map<String, dynamic>.from(await context.read<ApiClient>().get('/projects/${widget.projectId}/contractor-payments') as Map),
      builder: (ctx, data, _) {
        final rows = asMaps(data['requests']);
        if (rows.isEmpty) return const SizedBox.shrink();
        final canApprove = data['can_approve'] == true;
        final canRelease = data['can_release'] == true;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader('Contractor payment requests'),
          RowGroup(children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text((r['vendor_name'] ?? '').toString(), style: tt.titleSmall)),
                    Text(inr0(r['released_amount'] ?? r['amount']), style: tabular(tt.titleSmall)),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    StatusChip(r['status'], label: r['status']?.toString(), tone: _stepTone(r['status']), dense: true),
                    if (r['released_amount'] != null && toNum(r['released_amount']) != toNum(r['amount'])) ...[
                      const SizedBox(width: 8),
                      Text('(asked ${inr0(r['amount'])})', style: tt.bodySmall),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    [
                      '${r['contract_number'] ?? ''} · raised by ${r['requested_by'] ?? '—'}',
                      if ((r['note'] ?? '').toString().isNotEmpty) r['note'],
                      if (r['pm_by'] != null) 'PM: ${r['pm_by']}${r['pm_note'] != null ? ' "${r['pm_note']}"' : ''}',
                      if (r['released_by'] != null) 'released by ${r['released_by']}${r['md_note'] != null ? ' "${r['md_note']}"' : ''}',
                    ].join(' · '),
                    style: tt.bodySmall,
                  ),
                  if ((r['status'] == 'Requested' && canApprove) || (r['status'] == 'PM Approved' && canRelease)) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      if (r['status'] == 'Requested' && canApprove)
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: p.success, foregroundColor: Colors.white),
                              onPressed: _busy
                                  ? null
                                  : () => _act('/contractor-payments/${r['id']}/pm-approve', {}, 'Approved — waiting for the MD to release'),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Approve'),
                            ),
                          ),
                        ),
                      if (r['status'] == 'PM Approved' && canRelease)
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: p.success, foregroundColor: Colors.white),
                              onPressed: () => _release(r),
                              icon: const Icon(Icons.payments_outlined, size: 18),
                              label: const Text('Review & release'),
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: p.danger),
                          onPressed: _busy ? null : () => _reject(r),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Reject'),
                        ),
                      ),
                    ]),
                  ],
                ]),
              ),
          ]),
        ]);
      },
    );
  }
}

class _ReleaseForm extends StatefulWidget {
  final Map<String, dynamic> request;
  const _ReleaseForm({required this.request});

  @override
  State<_ReleaseForm> createState() => _ReleaseFormState();
}

class _ReleaseFormState extends State<_ReleaseForm> {
  late final _amount = TextEditingController(text: inputNum(widget.request['amount']));
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post('/contractor-payments/${widget.request['id']}/release',
          data: {'amount': toNum(_amount.text), 'note': _note.text.trim().isEmpty ? null : _note.text.trim()});
      if (!mounted) return;
      showToast(context, 'Payment released');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorText(e);
      });
      showToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(controller: _amount, label: 'Amount to release (₹)', money: true, onChanged: (_) => setState(() {})),
        kFieldGap,
        AppTextField(controller: _note, label: 'Note'),
        const SizedBox(height: 20),
        SheetError(_error),
        SubmitButton(
          label: 'Release ${inr0(toNum(_amount.text))}',
          icon: Icons.payments_outlined,
          busy: _busy,
          onPressed: toNum(_amount.text) > 0 ? _save : null,
        ),
      ]);
}
