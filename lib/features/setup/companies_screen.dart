import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../org/org_provider.dart';
import 'setup_kit.dart';

/// Companies and their branches (web CompaniesPage.jsx). Admin only.
class CompaniesScreen extends StatefulWidget {
  const CompaniesScreen({super.key});

  @override
  State<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends State<CompaniesScreen> {
  final _view = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();
  List<Map<String, dynamic>> _companies = const [];

  /// Reloads this list and the company switcher (web: invalidates org-companies-admin + org-companies).
  Future<void> _refresh() async {
    final org = context.read<OrgProvider>();
    await Future.wait([_view.currentState?.reload() ?? Future.value(), org.reload()]);
  }

  Future<void> _companyForm([Map<String, dynamic>? company]) async {
    final ok = await showAppSheet<bool>(context,
        title: company != null ? 'Edit company' : 'Add company', builder: (_) => _CompanyForm(company: company));
    if (ok == true) _refresh();
  }

  Future<void> _branchForm([Map<String, dynamic>? branch]) async {
    final ok = await showAppSheet<bool>(context,
        title: branch != null ? 'Edit branch' : 'Add branch',
        builder: (_) => _BranchForm(branch: branch, companies: _companies));
    if (ok == true) _refresh();
  }

  Future<void> _remove(String kind, Map<String, dynamic> item) async {
    final name = (item['name'] ?? '').toString();
    if (!await confirmDialog(context, title: 'Delete $name?', confirmLabel: 'Delete', destructive: true)) return;
    if (!mounted) return;
    final api = context.read<ApiClient>();
    final ok = await runAction(context, () => api.delete('/org/$kind/${item['id']}'), success: '$name deleted');
    if (ok) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _companyForm(), icon: const Icon(Icons.add), label: const Text('Company')),
      body: AsyncView<List<Map<String, dynamic>>>(
        key: _view,
        load: () async {
          final list = asMaps(await api.get('/org/companies'));
          _companies = list;
          return list;
        },
        builder: (context, companies, reload) {
          final branches = companies.fold<int>(0, (n, c) => n + (c['branches'] as List? ?? const []).length);
          final projects = companies.fold<int>(0, (n, c) => n + ((c['project_count'] as num?)?.toInt() ?? 0));
          final tt = Theme.of(context).textTheme;
          return RefreshList(
            onRefresh: _refresh,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 8),
                child: Row(children: [
                  Expanded(
                    child: Text('${companies.length} companies · $branches branches · $projects projects',
                        style: tabular(tt.bodySmall)),
                  ),
                  OutlinedButton.icon(
                    onPressed: companies.isEmpty ? null : () => _branchForm(),
                    icon: const Icon(Icons.call_split, size: 18),
                    label: const Text('Branch'),
                  ),
                ]),
              ),
              if (companies.isEmpty) const EmptyState(icon: Icons.domain_outlined, title: 'No companies yet.'),
              for (final c in companies) ...[
                _CompanyCard(
                  company: c,
                  onEdit: () => _companyForm(c),
                  onDelete: () => _remove('companies', c),
                  onEditBranch: (b) => _branchForm(b),
                  onDeleteBranch: (b) => _remove('branches', b),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CompanyCard extends StatelessWidget {
  final Map<String, dynamic> company;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<Map<String, dynamic>> onEditBranch;
  final ValueChanged<Map<String, dynamic>> onDeleteBranch;
  const _CompanyCard(
      {required this.company,
      required this.onEdit,
      required this.onDelete,
      required this.onEditBranch,
      required this.onDeleteBranch});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = context.pal;
    final c = company;
    final code = (c['code'] ?? '').toString();
    final gstin = (c['gstin'] ?? '').toString();
    final address = (c['address'] ?? '').toString();
    final branches = asMaps(c['branches']);
    return RowGroup(
      header: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text((c['name'] ?? '').toString(), style: tt.titleMedium),
                if (code.isNotEmpty) CodeTag(code),
                if (c['is_active'] == false) const StatusChip('Inactive', tone: Tone.danger, dense: true),
              ]),
              const SizedBox(height: 3),
              Text(
                '${gstin.isNotEmpty ? 'GSTIN $gstin' : 'No GSTIN'}${address.isNotEmpty ? ' · $address' : ''}',
                style: tt.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          _Menu(onEdit: onEdit, onDelete: onDelete),
        ]),
      ),
      children: [
        for (final b in branches)
          RowTile(
            padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
            title: (b['name'] ?? '').toString(),
            subtitleWidget: Row(children: [
              if ((b['code'] ?? '').toString().isNotEmpty) ...[
                Text(b['code'].toString(), style: TextStyle(fontFamily: monoFamily, fontSize: 11, color: p.fgSubtle)),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(dashOr(b['city']), style: tt.bodySmall, overflow: TextOverflow.ellipsis)),
            ]),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                Text('${b['project_count'] ?? 0}', style: tabular(tt.titleSmall)),
                Text('projects', style: tt.bodySmall),
              ]),
              _Menu(onEdit: () => onEditBranch(b), onDelete: () => onDeleteBranch(b)),
            ]),
          ),
      ],
    );
  }

  static String dashOr(dynamic v) => (v == null || v.toString().trim().isEmpty) ? '—' : v.toString();
}

class _Menu extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _Menu({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 20, color: p.fgMuted),
      onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'))),
        PopupMenuItem(
            value: 'delete',
            child: ListTile(
                leading: Icon(Icons.delete_outline, color: p.danger), title: Text('Delete', style: TextStyle(color: p.danger)))),
      ],
    );
  }
}

/// Short code field: 8 characters, mono, capitals (web `maxLength={8}` + `font-mono uppercase`).
class _CodeField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  const _CodeField({required this.controller, this.hint});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [LengthLimitingTextInputFormatter(8)],
        style: const TextStyle(fontFamily: monoFamily),
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(labelText: 'Short code', hintText: hint),
      );
}

class _CompanyForm extends StatefulWidget {
  final Map<String, dynamic>? company;
  const _CompanyForm({this.company});

  @override
  State<_CompanyForm> createState() => _CompanyFormState();
}

class _CompanyFormState extends State<_CompanyForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: (widget.company?['name'] ?? '').toString());
  final _city = TextEditingController();
  late final _code = TextEditingController(text: (widget.company?['code'] ?? '').toString());
  late final _gstin = TextEditingController(text: (widget.company?['gstin'] ?? '').toString());
  late final _address = TextEditingController(text: (widget.company?['address'] ?? '').toString());
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.company?['id'] != null;

  @override
  void dispose() {
    for (final c in [_name, _city, _code, _gstin, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    final body = {
      'name': _name.text,
      'code': orNull(_code.text),
      'gstin': orNull(_gstin.text),
      'address': orNull(_address.text),
    };
    try {
      if (_isEdit) {
        await api.patch('/org/companies/${widget.company!['id']}', data: body);
      } else {
        await api.post('/org/companies', data: {...body, 'city': _city.text});
      }
      if (!mounted) return;
      showToast(context, _isEdit ? 'Company updated' : 'Company added with a Head Office branch');
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
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppTextField(controller: _name, label: 'Company name', requiredField: true, capitalization: TextCapitalization.words),
          if (!_isEdit) ...[
            kFieldGap,
            AppTextField(
                controller: _city,
                label: 'City (Head Office branch)',
                requiredField: true,
                capitalization: TextCapitalization.words),
          ],
          kFieldGap,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _CodeField(controller: _code, hint: 'e.g. OHBC')),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _gstin,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontFamily: monoFamily),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'GSTIN'),
              ),
            ),
          ]),
          kFieldGap,
          AppTextField(controller: _address, label: 'Address', textInputAction: TextInputAction.done),
          const SizedBox(height: 18),
          SheetError(_error),
          SubmitButton(label: _busy ? 'Saving…' : 'Save', busy: _busy, onPressed: _save),
        ]),
      );
}

class _BranchForm extends StatefulWidget {
  final Map<String, dynamic>? branch;
  final List<Map<String, dynamic>> companies;
  const _BranchForm({this.branch, required this.companies});

  @override
  State<_BranchForm> createState() => _BranchFormState();
}

class _BranchFormState extends State<_BranchForm> {
  final _form = GlobalKey<FormState>();
  int? _companyId;
  late final _name = TextEditingController(text: (widget.branch?['name'] ?? '').toString());
  late final _city = TextEditingController(text: (widget.branch?['city'] ?? '').toString());
  late final _code = TextEditingController(text: (widget.branch?['code'] ?? '').toString());
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.branch?['id'] != null;

  @override
  void dispose() {
    for (final c in [_name, _city, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    final body = {'name': _name.text, 'code': orNull(_code.text), 'city': orNull(_city.text)};
    try {
      if (_isEdit) {
        await api.patch('/org/branches/${widget.branch!['id']}', data: body);
      } else {
        await api.post('/org/branches', data: {...body, 'company_id': _companyId});
      }
      if (!mounted) return;
      showToast(context, _isEdit ? 'Branch updated' : 'Branch added');
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
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!_isEdit) ...[
            AppDropdown<int>(
              label: 'Company',
              hint: 'Choose a company',
              requiredField: true,
              value: _companyId,
              items: [for (final c in widget.companies) (c['id'] as int, (c['name'] ?? '').toString())],
              onChanged: (v) => setState(() => _companyId = v),
            ),
            kFieldGap,
          ],
          AppTextField(controller: _name, label: 'Branch name', requiredField: true, capitalization: TextCapitalization.words),
          kFieldGap,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: AppTextField(
                    controller: _city, label: 'City', requiredField: true, capitalization: TextCapitalization.words)),
            const SizedBox(width: 12),
            Expanded(child: _CodeField(controller: _code)),
          ]),
          const SizedBox(height: 18),
          SheetError(_error),
          SubmitButton(label: _busy ? 'Saving…' : 'Save', busy: _busy, onPressed: _save),
        ]),
      );
}
