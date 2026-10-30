import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/network/api_client.dart';
import 'core/storage/api_config.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_provider.dart';
import 'features/org/org_provider.dart';
import 'features/shell/notifications_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await ApiConfig.getBaseUrl();

  final tokens = TokenStorage();
  final api = ApiClient(tokens);
  final theme = ThemeController();
  await theme.load();

  runApp(MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider.value(value: theme),
      ChangeNotifierProvider(create: (_) => AuthProvider(api, tokens)),
      ChangeNotifierProvider(create: (_) => OrgProvider(api)),
      ChangeNotifierProvider(create: (_) => NotificationCount(api)),
    ],
    child: const OysterApp(),
  ));
}
