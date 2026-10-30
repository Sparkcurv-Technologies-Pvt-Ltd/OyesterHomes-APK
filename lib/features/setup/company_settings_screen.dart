import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/files.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_provider.dart';

/// Company settings (web CompanySettingsPage.jsx): the letterhead logo and the office geofence for staff check-in.
class CompanySettingsScreen extends StatefulWidget {
  const CompanySettingsScreen({super.key});

  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  final _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  /// Web onSaved: refetch the settings and the signed-in user (the logo travels on /auth/me).
  Future<void> _onSaved() async {
    final auth = context.read<AuthProvider>();
    await Future.wait([_view.currentState?.reload() ?? Future.value(), auth.refreshUser()]);
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return Scaffold(
      body: AsyncView<Map<String, dynamic>>(
        key: _view,
        load: () async => Map<String, dynamic>.from(await api.get('/company/settings') as Map),
        builder: (context, settings, reload) => RefreshList(
          onRefresh: reload,
          padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 32),
          children: [
            if ((settings['company_name'] ?? '').toString().isNotEmpty) ...[
              const Eyebrow('Administration'),
              const SizedBox(height: 4),
              Text(settings['company_name'].toString(), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 14),
            ],
            _LogoSection(settings: settings, onSaved: _onSaved),
            const SizedBox(height: 16),
            _OfficeSection(settings: settings, onSaved: _onSaved),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────── logo

class _LogoSection extends StatefulWidget {
  final Map<String, dynamic> settings;
  final Future<void> Function() onSaved;
  const _LogoSection({required this.settings, required this.onSaved});

  @override
  State<_LogoSection> createState() => _LogoSectionState();
}

class _LogoSectionState extends State<_LogoSection> {
  bool _busy = false;

  Future<void> _save(String? url) async {
    await context.read<ApiClient>().patch('/company/settings', data: {'logo_url': url});
    await widget.onSaved();
  }

  Future<void> _upload() async {
    final api = context.read<ApiClient>();
    setState(() => _busy = true);
    try {
      final up = await pickAndUpload(context, api, imagesOnly: true);
      if (up == null || !mounted) return;
      final url = (up['url'] ?? '').toString();
      if (!RegExp(r'\.(png|jpe?g|webp|gif)$', caseSensitive: false).hasMatch(url)) {
        showToast(context, 'Choose a PNG, JPG, WEBP or GIF image', error: true);
        return;
      }
      await runAction(context, () => _save(url), success: 'Logo saved. It now prints on every invoice.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (!await confirmDialog(context, title: 'Remove the company logo from invoices?', confirmLabel: 'Remove', destructive: true)) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    await runAction(context, () => _save(null), success: 'Logo removed');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final logo = (widget.settings['logo_url'] ?? '').toString();
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Company logo', style: tt.titleMedium),
        const SizedBox(height: 4),
        Text(
          "Printed at the top of every document: BOQ, invoices, quotations, purchase orders, balance sheets and change orders. "
          "Under it goes the project's company name, address and GSTIN (Setup → Companies & branches). "
          'A wide PNG with a transparent background works best.',
          style: tt.bodySmall,
        ),
        const SizedBox(height: 14),
        Container(
          height: 112,
          padding: const EdgeInsets.all(16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.inputBorder),
          ),
          child: logo.isNotEmpty
              ? Image.network(
                  ApiConfig.fileUrl(logo),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Text('Could not load the logo', style: TextStyle(color: Color(0xFF8B96A8))),
                )
              : const Text('No logo yet — documents show the Sitera logo',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Color(0xFF8B96A8))),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _busy ? null : _upload,
                icon: _busy
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.onPrimaryBtn))
                    : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(logo.isNotEmpty ? 'Replace logo' : 'Upload logo'),
              ),
            ),
          ),
          if (logo.isNotEmpty) ...[
            const SizedBox(width: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _remove,
                style: OutlinedButton.styleFrom(foregroundColor: p.danger),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove'),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────── office geofence

/// OpenStreetMap's free geocoder (no key), as the web's utils/geo.js. Light use only: one request per tap.
final _nominatim = Dio(BaseOptions(
  baseUrl: 'https://nominatim.openstreetmap.org',
  connectTimeout: const Duration(seconds: 12),
  receiveTimeout: const Duration(seconds: 15),
  headers: {'Accept-Language': 'en', 'User-Agent': 'OysterHomes-Sitera-Android'},
));

Future<List<({String name, double lat, double lng})>> _searchPlace(String q) async {
  try {
    final r = await _nominatim.get('/search', queryParameters: {'format': 'json', 'limit': 5, 'countrycodes': 'in', 'q': q});
    return [
      for (final x in (r.data as List))
        (
          name: (x['display_name'] ?? '').toString(),
          lat: double.parse(x['lat'].toString()),
          lng: double.parse(x['lon'].toString()),
        ),
    ];
  } catch (_) {
    throw ApiException('Address search is not available right now');
  }
}

Future<String?> _placeName(double lat, double lng) async {
  try {
    final r = await _nominatim.get('/reverse', queryParameters: {'format': 'json', 'zoom': 16, 'lat': lat, 'lon': lng});
    return (r.data as Map)['display_name']?.toString();
  } catch (_) {
    return null;
  }
}

/// "11.0168, 76.9558" or a Google / OpenStreetMap link → (lat, lng), else null (web parseMapLink).
(double, double)? _parseMapLink(String text) {
  String s;
  try {
    s = Uri.decodeFull(text.trim());
  } catch (_) {
    s = text.trim();
  }
  final patterns = [
    RegExp(r'!3d(-?\d{1,2}\.\d+)!4d(-?\d{1,3}\.\d+)'),
    RegExp(r'@(-?\d{1,2}\.\d+),\s*(-?\d{1,3}\.\d+)'),
    RegExp(r'[?&](?:q|ll|query|destination)=(-?\d{1,2}\.\d+),\s*(-?\d{1,3}\.\d+)'),
    RegExp(r'[?&]mlat=(-?\d{1,2}\.\d+)&mlon=(-?\d{1,3}\.\d+)'),
    RegExp(r'^(-?\d{1,2}\.\d+)\s*[, ]\s*(-?\d{1,3}\.\d+)$'),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(s);
    if (m != null) {
      final lat = double.parse(m[1]!), lng = double.parse(m[2]!);
      if (lat.abs() <= 90 && lng.abs() <= 180) return (lat, lng);
    }
  }
  return null;
}

class _OfficeSection extends StatefulWidget {
  final Map<String, dynamic> settings;
  final Future<void> Function() onSaved;
  const _OfficeSection({required this.settings, required this.onSaved});

  @override
  State<_OfficeSection> createState() => _OfficeSectionState();
}

class _OfficeSectionState extends State<_OfficeSection> {
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _radius = TextEditingController();
  final _find = TextEditingController();
  String _savedKey = '';
  List<({String name, double lat, double lng})>? _results;
  bool _busy = false;
  bool _searching = false;
  String? _where;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _syncFromSettings();
    _lat.addListener(_onPointChanged);
    _lng.addListener(_onPointChanged);
    _onPointChanged();
  }

  @override
  void didUpdateWidget(covariant _OfficeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromSettings();
  }

  /// Reset only when the saved values change, so a fresh entry is never overwritten by a refetch.
  void _syncFromSettings() {
    final s = widget.settings;
    final key = '${s['office_lat']}|${s['office_lng']}|${s['office_radius_m']}';
    if (key == _savedKey) return;
    _savedKey = key;
    _lat.text = s['office_lat']?.toString() ?? '';
    _lng.text = s['office_lng']?.toString() ?? '';
    _radius.text = (s['office_radius_m'] ?? 200).toString();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_lat, _lng, _radius, _find]) {
      c.dispose();
    }
    super.dispose();
  }

  (double, double)? get _point {
    final lat = double.tryParse(_lat.text.trim()), lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) return null;
    return (lat, lng);
  }

  /// Name the place under the pin (debounced), so a wrong point is obvious before saving.
  void _onPointChanged() {
    _debounce?.cancel();
    final pt = _point;
    if (pt == null) {
      if (_where != null && mounted) setState(() => _where = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 700), () async {
      final name = await _placeName(pt.$1, pt.$2);
      if (mounted) setState(() => _where = name);
    });
  }

  void _setPoint(double lat, double lng) {
    _lat.text = lat.toStringAsFixed(6);
    _lng.text = lng.toStringAsFixed(6);
    setState(() {});
  }

  Future<void> _findPlace() async {
    final q = _find.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    final pasted = _parseMapLink(q);
    if (pasted != null) {
      _setPoint(pasted.$1, pasted.$2);
      setState(() => _results = null);
      showToast(context, 'Point taken from the link. Check the map, then save.');
      return;
    }
    if (RegExp(r'goo\.gl|maps\.app').hasMatch(q)) {
      showToast(context, "Short links can't be read. Open the link, then copy the full address from the browser bar.", error: true);
      return;
    }
    setState(() => _searching = true);
    try {
      final r = await _searchPlace(q);
      if (!mounted) return;
      setState(() => _results = r);
      if (r.isEmpty) showToast(context, 'No match. Try the area and city, e.g. "RS Puram, Coimbatore".', error: true);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    final lat = double.tryParse(_lat.text.trim()), lng = double.tryParse(_lng.text.trim());
    final radius = int.tryParse(_radius.text.trim());
    if (lat == null || lng == null) {
      showToast(context, 'Enter the office latitude and longitude', error: true);
      return;
    }
    if (radius == null || radius < 20 || radius > 50000) {
      showToast(context, 'Radius must be a whole number between 20 and 50,000 metres', error: true);
      return;
    }
    setState(() => _busy = true);
    await runAction(context, () async {
      await context.read<ApiClient>().patch('/company/settings',
          data: {'office_lat': lat, 'office_lng': lng, 'office_radius_m': radius});
      await widget.onSaved();
    }, success: 'Office location saved. Staff check-in is now location-checked.');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _turnOff() async {
    if (!await confirmDialog(context,
        title: 'Turn off the location check?',
        message: 'Staff will be able to check in from anywhere.',
        confirmLabel: 'Turn off')) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    await runAction(context, () async {
      await context.read<ApiClient>().patch('/company/settings',
          data: {'office_lat': null, 'office_lng': null, 'office_radius_m': null});
      await widget.onSaved();
    }, success: 'Location check turned off');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final on = widget.settings['geofence_on'] == true;
    final pt = _point;
    const decimal = TextInputType.numberWithOptions(decimal: true, signed: true);
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text('Office location for check-in', style: tt.titleMedium)),
          const SizedBox(width: 8),
          StatusChip(on ? 'on' : 'off',
              label: on ? 'Location check on' : 'Location check off', tone: on ? Tone.success : Tone.neutral, dense: true),
        ]),
        const SizedBox(height: 4),
        Text(
          'Site Engineers, Accountants and Procurement Officers can only check in within this distance of the office. '
          'For a direct site visit they request a one-day exception, which you approve under Users → Leave Requests.',
          style: tt.bodySmall,
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: AppTextField(controller: _lat, label: 'Latitude', hint: '13.082680', number: true, keyboardType: decimal)),
          const SizedBox(width: 10),
          Expanded(child: AppTextField(controller: _lng, label: 'Longitude', hint: '80.270718', number: true, keyboardType: decimal)),
        ]),
        kFieldGap,
        AppTextField(
            controller: _radius,
            label: 'Allowed radius (m)',
            number: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 16),
        const Eyebrow('Find the office'),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _find,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _findPlace(),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Search an address, or paste a Google Maps link or coordinates'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _find.text.trim().isEmpty || _searching ? null : _findPlace,
              icon: _searching
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search, size: 18),
              label: const Text('Find'),
            ),
          ),
        ]),
        if (_results != null && _results!.isNotEmpty) ...[
          const SizedBox(height: 8),
          RowGroup(margin: EdgeInsets.zero, children: [
            for (final r in _results!)
              RowTile(
                title: r.name,
                onTap: () {
                  _setPoint(r.lat, r.lng);
                  setState(() => _results = null);
                },
              ),
          ]),
        ],
        const SizedBox(height: 6),
        Text('Most exact: in Google Maps, long-press your building, copy the link (or the numbers shown) and paste it here.',
            style: tt.bodySmall),
        if (pt != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.muted, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_where != null)
                Text.rich(TextSpan(style: tt.bodySmall, children: [
                  const TextSpan(text: 'Pin is at: '),
                  TextSpan(text: _where, style: TextStyle(fontWeight: FontWeight.w700, color: p.fg)),
                  const TextSpan(text: '. '),
                ])),
              Text('Check the pin is on your building before saving.', style: tt.bodySmall),
              const SizedBox(height: 6),
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: p.accentText),
                onPressed: () => openExternal(context,
                    'https://www.google.com/maps?q=${Uri.encodeComponent(_lat.text.trim())},${Uri.encodeComponent(_lng.text.trim())}'),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Check on map'),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        Text('Phone GPS indoors can be off by 50–100 m, so keep the radius at 150 m or more.', style: tt.bodySmall),
        const SizedBox(height: 16),
        SubmitButton(label: 'Save location', busy: _busy, onPressed: _save),
        if (on) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: TextButton(
              onPressed: _busy ? null : _turnOff,
              style: TextButton.styleFrom(foregroundColor: p.fgMuted),
              child: const Text('Turn off'),
            ),
          ),
        ],
      ]),
    );
  }
}
