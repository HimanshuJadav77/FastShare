import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:wifi_ftp/core/data/models/device_model.dart';
import 'package:wifi_ftp/core/networking/app_connection.dart' as app;
import 'package:wifi_ftp/core/providers.dart';
import 'package:wifi_ftp/ui/widgets/app_app_bar.dart';
import 'package:wifi_ftp/ui/widgets/app_card.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  late final app.AppConnection _connection;
  bool _navigatedAway = false;

  @override
  void initState() {
    super.initState();
    _connection = ref.read(appConnectionProvider);

    // Warm up history loading
    ref.read(transferHistoryProvider).load();

    // If already connected, go straight to dashboard
    if (_connection.isConnected) {
      _navigatedAway = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pushReplacementNamed(context, '/dashboard');
      });
      return;
    }

    // Listen for state changes (e.g. OTHER device connected to us via TCP)
    _connection.addListener(_onConnectionStateChanged);

    _startDiscovery();
  }

  void _onConnectionStateChanged() {
    if (_navigatedAway) return;
    if (_connection.isConnected && mounted) {
      _navigatedAway = true;
      debugPrint('[UI] Other device connected to us — navigating to dashboard');
      Navigator.pushReplacementNamed(context, '/dashboard');
    }
  }

  Future<void> _startDiscovery() async {
    if (_connection.state == app.ConnectionState.discovering) return;

    String deviceName = ref.read(settingsProvider).deviceName;
    String deviceType = 'unknown';
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        deviceName = '${info.brand} ${info.model}';
        deviceType = 'android';
      } else if (Platform.isWindows) {
        final info = await DeviceInfoPlugin().windowsInfo;
        deviceName = info.computerName;
        deviceType = 'windows';
      }
    } catch (_) {}

    final localDevice = DeviceModel(
      deviceId: const Uuid().v4(),
      deviceName: deviceName,
      deviceType: deviceType,
      ip: '',
      port: 45556,
    );

    await _connection.startDiscovery(localDevice);
  }

  Future<void> _connectToDevice(DeviceModel device) async {
    final success = await _connection.connectToDevice(device);
    if (_navigatedAway) return;
    if (!mounted) return;
    if (success) {
      _navigatedAway = true;
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection failed. Try again.')),
      );
      _startDiscovery();
    }
  }

  @override
  void dispose() {
    _connection.removeListener(_onConnectionStateChanged);
    // Don't stop discovery in dispose — let it run if not connected
    // The connection singleton manages its own lifecycle
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appConnectionProvider);
    final ext = context.appColors;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppAppBar(
        title: 'NEARBY DEVICES',
        actions: [
          if (_connection.state == app.ConnectionState.discovering)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<DeviceModel>>(
          stream: _connection.orchestrator.discoveredDevices,
          initialData: const [],
          builder: (context, snapshot) {
            final devices = snapshot.data ?? [];

            if (_connection.state == app.ConnectionState.connecting) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: ext.warning),
                    const SizedBox(height: 24),
                    Text('Connecting...', style: TextStyle(color: ext.warning, fontSize: 18, fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }

            if (devices.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.radar, size: 64, color: Colors.grey),
                    const SizedBox(height: 24),
                    Text('Searching for nearby devices...', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text('Ensure both devices are on the same Wi-Fi', style: TextStyle(color: ext.textMuted, fontSize: 13)),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              itemCount: devices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final device = devices[index];
                return AppCard(
                  padding: const EdgeInsets.all(12),
                  onTap: () => _connectToDevice(device),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          device.deviceType == 'windows' ? Icons.computer : Icons.phone_android,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(device.deviceName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(device.deviceType.toUpperCase(), style: TextStyle(color: ext.textMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: ext.textMuted),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
