import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/storage/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/common.dart';
import 'auth_provider.dart';

/// Web LoginPage: logo, "Sign in", email + password, theme toggle. Plus "Server settings" so the
/// backend URL can be changed without a new build.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  Future<void> _submit() async {
    final e = _email.text.trim(), p = _password.text;
    if (e.isEmpty || p.isEmpty) {
      setState(() => _error = 'Email and password are required');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().login(e, p);
    } catch (err) {
      if (mounted) setState(() => _error = errorText(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _serverSettings() async {
    final c = TextEditingController(text: await ApiConfig.getBaseUrl());
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server settings'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('The address of the Sitera server. The app calls <address>/api.'),
          const SizedBox(height: 14),
          TextField(
            controller: c,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Server address', hintText: ApiConfig.defaultUrl),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () {
                c.text = ApiConfig.defaultUrl;
              },
              child: const Text('Reset')),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true && c.text.trim().isNotEmpty) {
      await ApiConfig.setBaseUrl(c.text);
      if (mounted) showToast(context, 'Server set to ${ApiConfig.baseUrlSync}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final theme = context.watch<ThemeController>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? Slate.s950 : Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const Spacer(),
                    IconButton(
                      tooltip: dark ? 'Switch to light theme' : 'Switch to dark theme',
                      onPressed: () => theme.set(dark ? ThemeMode.light : ThemeMode.dark),
                      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 20),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Image.asset(
                      dark ? 'assets/images/sitera-logo-horizontal-on-dark.png' : 'assets/images/sitera-logo-horizontal.png',
                      height: 52,
                      semanticLabel: 'Sitera ERP',
                    ),
                  ),
                  const SizedBox(height: 36),
                  Text('Sign in', style: tt.headlineLarge),
                  const SizedBox(height: 6),
                  Text('Access your project command center', style: tt.bodyMedium?.copyWith(color: p.fgMuted)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email, AutofillHints.username],
                    decoration: const InputDecoration(labelText: 'Email', hintText: 'you@company.com'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    obscureText: !_show,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        tooltip: _show ? 'Hide password' : 'Show password',
                        icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                        onPressed: () => setState(() => _show = !_show),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, style: tt.bodyMedium?.copyWith(color: p.danger)),
                  ],
                  const SizedBox(height: 22),
                  SubmitButton(label: 'SIGN IN', busy: _busy, onPressed: _submit),
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton.icon(
                      onPressed: _serverSettings,
                      icon: Icon(Icons.dns_outlined, size: 16, color: p.fgMuted),
                      label: Text('Server settings', style: TextStyle(color: p.fgMuted, fontSize: 13)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
