import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/widgets/common.dart';
import 'features/auth/auth_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/org/org_provider.dart';
import 'features/shell/app_shell.dart';

class OysterApp extends StatefulWidget {
  const OysterApp({super.key});

  @override
  State<OysterApp> createState() => _OysterAppState();
}

class _OysterAppState extends State<OysterApp> {
  @override
  void initState() {
    super.initState();
    context.read<AuthProvider>().bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeController>().mode;
    final auth = context.watch<AuthProvider>();
    // Keep the company switcher in step with whoever is signed in.
    context.read<OrgProvider>().attach(auth.status == AuthStatus.authenticated ? auth.user : null);

    final Widget home = switch (auth.status) {
      AuthStatus.authenticated => const AppShell(),
      AuthStatus.unauthenticated => const LoginScreen(),
      AuthStatus.unknown => auth.bootError != null ? const _BootError() : const Scaffold(body: LoadingView()),
    };

    return MaterialApp(
      title: 'Oyster Homes',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      locale: const Locale('en', 'IN'),
      supportedLocales: const [Locale('en', 'IN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: KeyedSubtree(key: ValueKey('${auth.status}-${auth.user?.id}'), child: home),
    );
  }
}

class _BootError extends StatelessWidget {
  const _BootError();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: SafeArea(child: Center(child: ErrorRetry(message: auth.bootError ?? '', onRetry: auth.retryBoot))),
    );
  }
}
