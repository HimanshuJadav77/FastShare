import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wifi_ftp/core/networking/app_connection.dart';
import 'package:wifi_ftp/core/transfer/file_transfer_service.dart';
import 'package:wifi_ftp/core/transfer/transfer_history.dart';
import 'package:wifi_ftp/ui/screens/home_screen.dart';
import 'package:wifi_ftp/ui/screens/discovery_screen.dart';
import 'package:wifi_ftp/ui/screens/transfer_dashboard.dart';
import 'package:wifi_ftp/ui/screens/history_screen.dart';
import 'package:wifi_ftp/ui/screens/settings_screen.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';
import 'package:wifi_ftp/ui/theme/app_animations.dart';
import 'package:wifi_ftp/core/providers/theme_provider.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppConnection.navigatorKey = _navigatorKey;
  FileTransferService.navigatorKey = _navigatorKey;
  TransferHistory().load();
  runApp(const ProviderScope(child: FastShareApp()));
}

class FastShareApp extends ConsumerWidget {
  const FastShareApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Fast Share',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      initialRoute: '/',
      onGenerateRoute: (settings) {
        Widget page;
        switch (settings.name) {
          case '/':
            page = const HomeScreen();
            break;
          case '/discovery':
            page = const DiscoveryScreen();
            break;
          case '/dashboard':
            page = const TransferDashboard();
            break;
          case '/history':
            page = const HistoryScreen();
            break;
          case '/settings':
            page = const SettingsScreen();
            break;
          default:
            page = const HomeScreen();
        }

        return AppAnimations.createRoute(page);
      },
    );
  }
}
