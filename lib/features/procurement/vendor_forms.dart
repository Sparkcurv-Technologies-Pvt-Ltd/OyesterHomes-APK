import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import 'proc_common.dart';

// Web: components/VendorFormModal.jsx and components/ProductFormModal.jsx, as bottom sheets.

const _vendorTypes = ['Supplier', 'Subcontractor', 'Consultant'];
const _vendorStatuses = ['Active', 'Inactive', 'Blacklisted'];

/// Add / edit a vendor (POST /vendors, PATCH /vendors/{id}). Returns the saved vendor, or null if cancelled.
Future<Map<String, dynamic>?> showVendorForm(BuildContext context, {Map<String, dynamic>? vendor}) async {
  final api = context.read<ApiClient>();
  final isEdit = vendor != null;
  final res = await showAppSheet<Map<String, dynamic>>(
    context,
    title: isEdit ? 'Edit Vendor' : 'Add Vendor',
    subtitle: isEdit ? 'Update details for ${vendor['name']}.' : 'Register a supplier, subcontractor or consultant.',
    builder: (ctx) => _VendorForm(api: api, vendor: vendor),
  );
  if (res != null && context.mounted) showToast(context, isEdit ? 'Vendor updated' : 'Vendor created');
  return res;
}

class _VendorForm extends StatefulWidget {
  final ApiClient api;
  final Map<String, dynamic>? vendor;
  const _VendorForm({required this.api, this.vendor});

  @override
  State<_VendorForm> createState() => _VendorFormState();
}

class _VendorFormState extends State<_VendorForm> {
  late final Map<String, TextEditingController> _c;
  late String _type;
  late String _status;
  String? _insurance;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.vendor != null;

  @override
  void initState() {
    super.initState();
    final v = widget.vendor ?? const {};
    String s(String k) => (v[k] ?? '').toString();
    _c = {
      for (final k in ['name', 'trade', 'contact_name', 'email', 'phone', 'address', 'tax_id'])
        k: TextEditingController(text: s(k)),
    };
    _type = _vendorTypes.contains(v['vendor_type']) ? v['vendor_type'] as String : 'Supplier';
    _status = _vendorStatuses.contains(v['status']) ? v['status'] as String : 'Active';
    final ins = s('insurance_expiry');
    _insurance = ins.isEmpty ? null : ins;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(String k) => _c[k]!.text.isEmpty ? null : _c[k]!.text;

  Future<void> _submit() async {
    final name = _c['name']!.text.trim();
    if (name.isEmpty) return _fail('Vendor name is required');
    if (!_isEdit && _insurance != null && _insurance!.compareTo(todayIso()) < 0) {
      return _fail('Insurance expiry date cannot be in the past');
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = {
      'name': name,
      'vendor_type': _type,
      'trade': _opt('trade'),
      'contact_name': _opt('contact_name'),
      'email': _opt('email'),
      'phone': _opt('phone'),
      'insurance_expiry': _insurance,
      'address': _opt('address'),
      'tax_id': _opt('tax_id'),
      'status': _status,
    };
    try {
      final res = _isEdit
          ? await widget.api.patch('/vendors/${widget.vendor!['id']}', data: payload)
          : await widget.api.post('/vendors', data: payload);
      if (mounted) Navigator.pop(context, Map<String, dynamic>.from(res as Map));
    } catch (e) {
      _fail(errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() => _error = msg);
    showToast(context, msg, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTextField(controller: _c['name'], label: 'Name', requiredField: true, capitalization: TextCapitalization.words),
      kFieldGap,
      AppDropdown<String>(
        label: 'Type',
        value: _type,
        items: [for (final t in _vendorTypes) (t, t)],
        onChanged: (v) => setState(() => _type = v ?? _type),
      ),
      kFieldGap,
      AppTextField(controller: _c['trade'], label: 'Trade', hint: 'Steel, Glazing…'),
      kFieldGap,
      AppTextField(controller: _c['contact_name'], label: 'Contact Name', capitalization: TextCapitalization.words),
      kFieldGap,
      AppTextField(
          controller: _c['email'], label: 'Email', keyboardType: TextInputType.emailAddress, capitalization: TextCapitalization.none),
      kFieldGap,
      AppTextField(controller: _c['phone'], label: 'Phone', keyboardType: TextInputType.phone),
      kFieldGap,
      AppTextField(controller: _c['address'], label: 'Address'),
      kFieldGap,
      AppTextField(controller: _c['tax_id'], label: 'GST / Tax ID', capitalization: TextCapitalization.characters),
      kFieldGap,
      DateField(
        label: 'Insurance Expiry',
        value: _insurance,
        firstDate: _isEdit ? null : DateTime(now.year, now.month, now.day),
        onChanged: (v) => setState(() => _insurance = v),
      ),
      kFieldGap,
      AppDropdown<String>(
        label: 'Status',
        value: _status,
        items: [for (final s in _vendorStatuses) (s, s)],
        onChanged: (v) => setState(() => _status = v ?? _status),
      ),
      const SizedBox(height: 20),
      SheetError(_error),
      SubmitButton(label: _isEdit ? 'Save Changes' : 'Create Vendor', busy: _saving, onPressed: _submit),
    ]);
  }
}

// ───────────────────────────────────────────────────────── product

const _units = ['nos', 'bag', 'ton', 'kg', 'sqft', 'cft', 'litre', 'metre', 'roll', 'box'];
const _categories = ['Cement', 'Steel', 'Electrical', 'Plumbing', 'Aggregate', 'Timber', 'Paint', 'Hardware', 'Other'];

/// Names are words (mirrors PRODUCT_NAME in routers/quotations_v2.py): letters, spaces and . , & ( ) ' / -,
/// starting with a letter. Sizes and grades (12mm, 53 grade) go in the description.
final _productName = RegExp(r"^[A-Za-z][A-Za-z .,&()'/-]*$");
final _nameChars = RegExp(r"[^A-Za-z .,&()'/-]");

/// Add / edit a global catalog product (POST /products, PATCH /products/{id}). Returns the saved product, or null.
///
/// [vendorId] is accepted for callers that open it from a vendor context; the catalog is global
/// (the web's ProductFormModal has no vendor), so it is not sent.
Future<Map<String, dynamic>?> showProductForm(BuildContext context, {Map<String, dynamic>? product, int? vendorId}) async {
  final api = context.read<ApiClient>();
  final res = await showAppSheet<Map<String, dynamic>>(
    context,
    title: product != null ? 'Edit Product' : 'Add Product',
    subtitle: 'Global catalog item — any vendor can be quoted against it.',
    builder: (ctx) => _ProductForm(api: api, product: product),
  );
  if (res != null && context.mounted) showToast(context, product != null ? 'Product updated' : 'Product created');
  return res;
}

class _ProductForm extends StatefulWidget {
  final ApiClient api;
  final Map<String, dynamic>? product;
  const _ProductForm({required this.api, this.product});

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  late final TextEditingController _name, _price, _desc;
  late String _unit;
  String? _category;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.product ?? const {};
    _name = TextEditingController(text: (p['name'] ?? '').toString());
    _price = TextEditingController(text: inputNum(p['default_price']));
    _desc = TextEditingController(text: (p['description'] ?? '').toString());
    _unit = (p['unit'] as String?)?.isNotEmpty == true ? p['unit'] as String : 'nos';
    final cat = (p['category'] as String?) ?? '';
    _category = cat.isEmpty ? null : cat;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) return _fail('Product name is required');
    if (!_productName.hasMatch(name) && name != ((widget.product?['name'] as String?) ?? '')) {
      return _fail('Product name: letters only, starting with a letter. Put sizes or grades like 12mm in Description.');
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = {
      'name': name,
      'unit': _unit.isEmpty ? 'nos' : _unit,
      'category': _category,
      'description': _desc.text.isEmpty ? null : _desc.text,
      'default_price': _price.text.trim().isEmpty ? null : toNum(_price.text.trim()),
    };
    try {
      final res = widget.product != null
          ? await widget.api.patch('/products/${widget.product!['id']}', data: payload)
          : await widget.api.post('/products', data: payload);
      if (mounted) Navigator.pop(context, Map<String, dynamic>.from(res as Map));
    } catch (e) {
      _fail(errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() => _error = msg);
    showToast(context, msg, error: true);
  }

  @override
  Widget build(BuildContext context) {
    // The current unit/category stay selectable even if they are not in the web's fixed lists.
    final units = [..._units, if (!_units.contains(_unit)) _unit];
    final cats = [..._categories, if (_category != null && !_categories.contains(_category)) _category!];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextFormField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        inputFormatters: [FilteringTextInputFormatter.deny(_nameChars)],
        decoration: const InputDecoration(
          labelText: 'Product Name *',
          hintText: 'e.g. Portland Cement (grade / size go in Description)',
        ),
      ),
      kFieldGap,
      AppDropdown<String>(
        label: 'Unit',
        value: _unit,
        items: [for (final u in units) (u, u)],
        onChanged: (v) => setState(() => _unit = v ?? _unit),
      ),
      kFieldGap,
      AppDropdown<String>(
        label: 'Category',
        value: _category,
        hint: 'Optional',
        items: [for (final c in cats) (c, c)],
        onChanged: (v) => setState(() => _category = v ?? _category),
      ),
      kFieldGap,
      AppTextField(
        controller: _price,
        label: 'Default Price (₹, reference)',
        money: true,
        hint: 'Pre-fills quotations, editable there',
      ),
      kFieldGap,
      AppTextField(controller: _desc, label: 'Description'),
      const SizedBox(height: 20),
      SheetError(_error),
      SubmitButton(label: widget.product != null ? 'Save Changes' : 'Create Product', busy: _saving, onPressed: _submit),
    ]);
  }
}
