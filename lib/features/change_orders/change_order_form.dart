import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/files.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';

/// Change-order categories (backend routers/change_orders.py CATEGORIES).
const coCategories = ['Client Modification', 'Rework', 'Design Change', 'Site Condition'];

bool isPdfUrl(String? url) => RegExp(r'\.pdf$', caseSensitive: false).hasMatch(url ?? '');

/// The web's ChangeOrderFormModal: a new change order ([co] null) or a revised estimate for [co].
/// Pops `true` when saved.
Future<bool?> showChangeOrderSheet(BuildContext context,
    {required int projectId, required List<dynamic> phases, Map<String, dynamic>? co}) {
  final isRevise = co != null;
  return showAppSheet<bool>(context,
      title: isRevise ? 'Revise ${co['co_number']}' : 'New Change Order',
      subtitle: isRevise
          ? 'Submit an updated cost/time estimate for client review.'
          : 'Propose extra or modified work outside the original contract scope.',
      builder: (ctx) => _ChangeOrderForm(projectId: projectId, phases: phases, co: co));
}

class _ChangeOrderForm extends StatefulWidget {
  final int projectId;
  final List<dynamic> phases;
  final Map<String, dynamic>? co;
  const _ChangeOrderForm({required this.projectId, required this.phases, this.co});

  @override
  State<_ChangeOrderForm> createState() => _ChangeOrderFormState();
}

class _ChangeOrderFormState extends State<_ChangeOrderForm> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  late final _cost = TextEditingController(text: widget.co == null ? '' : inputNum(widget.co!['estimated_cost']));
  late final _days =
      TextEditingController(text: widget.co == null ? '0' : '${toInt(widget.co!['estimated_time_impact_days'])}');
  final _note = TextEditingController();
  String _category = 'Client Modification';
  int? _phaseId;
  bool _submitNow = true;
  bool _saving = false;
  bool _uploading = false;
  final List<Map<String, dynamic>> _attachments = [];

  bool get _isRevise => widget.co != null;

  @override
  void dispose() {
    for (final c in [_title, _description, _cost, _days, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid {
    final cost = toNumOrNull(_cost.text);
    final costOk = _cost.text.trim().isNotEmpty && cost != null && cost >= 0;
    return _isRevise ? costOk : _title.text.trim().isNotEmpty && costOk;
  }

  int get _daysValue => toNum(_days.text).truncate();

  Future<void> _addAttachment() async {
    final api = context.read<ApiClient>();
    setState(() => _uploading = true);
    final res = await pickAndUpload(context, api, extensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'pdf']);
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (res != null) _attachments.add({'url': res['url'], 'filename': res['filename']});
    });
  }

  Future<void> _submit() async {
    if (!_valid) return;
    final api = context.read<ApiClient>();
    final co = widget.co;
    final cost = toNum(_cost.text);
    setState(() => _saving = true);
    final ok = await runAction(
      context,
      () async {
        if (co != null) {
          await api.post('/change-orders/${co['id']}/revise', data: {
            'estimated_cost': cost,
            'estimated_time_impact_days': _daysValue,
            'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
          });
        } else {
          await api.post('/projects/${widget.projectId}/change-orders', data: {
            'title': _title.text.trim(),
            'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
            'category': _category,
            'phase_id': _phaseId,
            'estimated_cost': cost,
            'estimated_time_impact_days': _daysValue,
            'attachments': _attachments,
            'submit': _submitNow,
          });
        }
      },
      success: co != null
          ? 'Revised estimate submitted for ${co['co_number']}'
          : _submitNow
              ? 'Change order sent to client for review'
              : 'Change order saved as draft',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context, true);
  }

  void _changed(String _) => setState(() {});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!_isRevise) ...[
        AppTextField(
            controller: _title,
            label: 'Title',
            requiredField: true,
            hint: 'e.g. Client requested marble flooring upgrade',
            onChanged: _changed),
        kFieldGap,
        AppDropdown<String>(
          label: 'Category',
          value: _category,
          items: [for (final c in coCategories) (c, c)],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        kFieldGap,
        AppDropdown<int?>(
          label: 'Linked Phase',
          hint: 'Optional',
          value: _phaseId,
          items: [
            (null, '— None —'),
            for (final ph in widget.phases)
              if (ph is Map) (toInt(ph['id']), '${ph['name']}'),
          ],
          onChanged: (v) => setState(() => _phaseId = v),
        ),
        kFieldGap,
        AppTextField(
          controller: _description,
          label: 'Scope Description',
          hint: 'Describe the extra / modified work and why it is outside the original scope',
          maxLines: 4,
          minLines: 3,
        ),
        kFieldGap,
      ],
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: AppTextField(
                controller: _cost, label: 'Estimated Cost (₹)', money: true, requiredField: true, onChanged: _changed)),
        const SizedBox(width: 12),
        Expanded(
            child: AppTextField(
                controller: _days, label: 'Time Impact (days)', keyboardType: TextInputType.number, number: true)),
      ]),
      kFieldGap,
      if (_isRevise)
        AppTextField(controller: _note, label: 'Revision Note', hint: 'What changed in this estimate?', maxLines: 3, minLines: 2)
      else ...[
        const Eyebrow('Photos / Drawings'),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < _attachments.length; i++)
            Stack(clipBehavior: Clip.none, children: [
              AttachmentThumb(attachment: _attachments[i], width: 84, height: 68),
              Positioned(
                top: -8,
                right: -8,
                child: Material(
                  color: p.danger,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _attachments.removeAt(i)),
                    child: const Padding(padding: EdgeInsets.all(5), child: Icon(Icons.close, size: 14, color: Colors.white)),
                  ),
                ),
              ),
            ]),
          InkWell(
            onTap: _uploading ? null : _addAttachment,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 84,
              height: 68,
              decoration: BoxDecoration(
                border: Border.all(color: p.inputBorder),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: _uploading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.add_photo_alternate_outlined, color: p.fgSubtle),
            ),
          ),
        ]),
        if (_uploading) ...[const SizedBox(height: 6), Text('Uploading…', style: tt.bodySmall)],
        const SizedBox(height: 6),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _submitNow,
          onChanged: (v) => setState(() => _submitNow = v ?? true),
          title: Text('Send to client for review immediately (uncheck to save as draft)', style: tt.bodyMedium),
        ),
      ],
      const SizedBox(height: 14),
      SubmitButton(
        label: _isRevise
            ? 'Submit Revised Estimate'
            : _submitNow
                ? 'Create & Send'
                : 'Save Draft',
        busy: _saving,
        onPressed: !_valid || _uploading ? null : _submit,
      ),
    ]);
  }
}

/// Thumbnail of a change-order attachment (image preview, or a PDF tile). Tapping opens it.
class AttachmentThumb extends StatelessWidget {
  final Map<String, dynamic> attachment;
  final double width;
  final double height;
  const AttachmentThumb({super.key, required this.attachment, this.width = 96, this.height = 80});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final url = (attachment['url'] ?? '').toString();
    final name = (attachment['filename'] ?? '').toString();
    final radius = BorderRadius.circular(6);
    Widget pdfTile() => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.picture_as_pdf_outlined, size: 22, color: p.danger),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(name.isEmpty ? 'Document' : name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: p.fgMuted)),
          ),
        ]);
    return Tooltip(
      message: name,
      child: InkWell(
        borderRadius: radius,
        onTap: url.isEmpty ? null : () => openServerFile(context, context.read<ApiClient>(), url, name: name.isEmpty ? null : name),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(color: p.muted, border: Border.all(color: p.border), borderRadius: radius),
          clipBehavior: Clip.antiAlias,
          child: isPdfUrl(url)
              ? pdfTile()
              : Image.network(
                  ApiConfig.fileUrl(url),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(Icons.insert_drive_file_outlined, color: p.fgSubtle),
                ),
        ),
      ),
    );
  }
}
