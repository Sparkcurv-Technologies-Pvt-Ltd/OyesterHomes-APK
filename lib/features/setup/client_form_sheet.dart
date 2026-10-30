import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/common.dart';
import 'setup_kit.dart';

/// The web ClientFormModal as a bottom sheet. Pass [client] to edit. Returns true when saved.
Future<bool> showClientForm(BuildContext context, {Map<String, dynamic>? client}) async {
  final saved = await showAppSheet<bool>(
    context,
    title: client != null ? 'Edit Client' : 'New Client',
    subtitle: client != null ? 'Update client details.' : 'Add a new client to the directory.',
    builder: (_) => _ClientForm(client: client),
  );
  return saved == true;
}

class _ClientForm extends StatefulWidget {
  final Map<String, dynamic>? client;
  const _ClientForm({this.client});

  @override
  State<_ClientForm> createState() => _ClientFormState();
}

class _ClientFormState extends State<_ClientForm> {
  late final _name = TextEditingController(text: (widget.client?['name'] ?? '').toString());
  late final _phone = TextEditingController(text: (widget.client?['phone'] ?? '').toString());
  late final _email = TextEditingController(text: (widget.client?['email'] ?? '').toString());
  late final _address = TextEditingController(text: (widget.client?['address'] ?? '').toString());
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Client name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    final body = {'name': _name.text, 'email': _email.text, 'phone': _phone.text, 'address': _address.text};
    try {
      if (widget.client != null) {
        await api.patch('/clients/${widget.client!['id']}', data: body);
      } else {
        await api.post('/clients', data: body);
      }
      if (!mounted) return;
      showToast(context, widget.client != null ? 'Client updated' : 'Client created');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorText(e);
      });
      showToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(controller: _name, label: 'Name', requiredField: true, capitalization: TextCapitalization.words),
        kFieldGap,
        AppTextField(controller: _phone, label: 'Phone No', keyboardType: TextInputType.phone),
        kFieldGap,
        AppTextField(
            controller: _email,
            label: 'Email',
            keyboardType: TextInputType.emailAddress,
            capitalization: TextCapitalization.none),
        kFieldGap,
        AppTextField(controller: _address, label: 'Address', textInputAction: TextInputAction.done),
        const SizedBox(height: 18),
        SheetError(_error),
        SubmitButton(
            label: widget.client != null ? 'Save Changes' : 'Create Client', busy: _saving, onPressed: _submit),
      ]);
}
