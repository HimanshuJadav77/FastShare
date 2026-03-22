import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_ftp/core/providers.dart';
import 'package:wifi_ftp/ui/widgets/app_app_bar.dart';
import 'package:wifi_ftp/ui/widgets/app_button.dart';
import 'package:wifi_ftp/ui/widgets/app_card.dart';
import 'package:wifi_ftp/ui/widgets/connection_banner.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _requestPermissionsAndNavigate(BuildContext context, WidgetRef ref) async {
    await [
      Permission.location,
      Permission.storage,
      Permission.nearbyWifiDevices,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.manageExternalStorage,
    ].request();

    if (!context.mounted) return;

    final connection = ref.read(appConnectionProvider);
    if (connection.isConnected) {
      Navigator.pushNamed(context, '/dashboard');
    } else {
      Navigator.pushNamed(context, '/discovery');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(appConnectionProvider);
    final ext = context.appColors;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppAppBar(
        title: 'FAST SHARE',
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: ext.textMuted),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ─── Persistent Connection Banner ───
            GestureDetector(
              onTap: connection.isConnected ? () => Navigator.pushNamed(context, '/dashboard') : null,
              child: const ConnectionBanner(),
            ),

            // ─── Main Content ───
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Column(
                  children: [
                    const Spacer(),
                    
                    // ─── Action Cards ───
                    Row(
                      children: [
                        Expanded(
                          child: AppCard(
                            onTap: () => _requestPermissionsAndNavigate(context, ref),
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            child: Column(
                              children: [
                                Icon(Icons.arrow_upward_rounded, size: 48, color: Theme.of(context).primaryColor),
                                const SizedBox(height: 16),
                                Text('SEND', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: AppCard(
                            onTap: () => _requestPermissionsAndNavigate(context, ref),
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            child: Column(
                              children: [
                                Icon(Icons.arrow_downward_rounded, size: 48, color: ext.success),
                                const SizedBox(height: 16),
                                Text('RECEIVE', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 48),
                    
                    // ─── Nearby Devices Button ───
                    AppButton(
                      isFullWidth: true,
                      outlined: connection.isConnected,
                      text: connection.isConnected ? 'ALREADY CONNECTED' : 'NEARBY DEVICES',
                      icon: connection.isConnected ? Icons.check_circle_outline : Icons.radar,
                      onPressed: connection.isConnected ? null : () => _requestPermissionsAndNavigate(context, ref),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // ─── History Link ───
                    TextButton.icon(
                      onPressed: () => Navigator.pushNamed(context, '/history'),
                      icon: Icon(Icons.history, color: ext.textMuted, size: 20),
                      label: Text('View History', style: TextStyle(color: ext.textMuted, fontWeight: FontWeight.w600)),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

