import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:wifi_ftp/core/data/models/device_model.dart';
import 'package:wifi_ftp/core/networking/app_connection.dart' as app;
import 'package:wifi_ftp/core/providers.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';
import 'package:wifi_ftp/ui/theme/app_animations.dart';
import 'package:wifi_ftp/ui/widgets/fs_app_bar.dart';

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
    ref.read(transferHistoryProvider).load();

    // Don't disconnect here - if connected, DiscoveryScreen will show connecting/connected states
    // but typically HomeScreen redirects to /dashboard if connected.

    _connection.addListener(_onConnectionStateChanged);
    _startDiscovery();
  }

  void _onConnectionStateChanged() {
    if (_navigatedAway) return;
    if (_connection.isConnected && mounted) {
      _navigatedAway = true;
      // 1. Save last connected device info
      final device = _connection.connectedDevice;
      if (device != null) {
        ref.read(settingsProvider.notifier).setLastDevice(device.deviceName, device.deviceType);
      }
      Navigator.pushReplacementNamed(context, '/dashboard');
    }
  }

  Future<void> _startDiscovery() async {
    String deviceName = ref.read(settingsProvider).deviceName;
    String deviceType = 'unknown';

    // Only fallback to system name if the user hasn't set one AND settings name is the default
    try {
      if (Platform.isAndroid) {
        deviceType = 'android';
        if (deviceName.isEmpty || deviceName == 'android-device') {
          final info = await DeviceInfoPlugin().androidInfo;
          deviceName = '${info.brand} ${info.model}';
        }
      } else if (Platform.isWindows) {
        deviceType = 'windows';
        if (deviceName.isEmpty || deviceName == 'windows-pc') {
          final info = await DeviceInfoPlugin().windowsInfo;
          deviceName = info.computerName;
        }
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
    if (!mounted || _navigatedAway) return;
    if (success) {
      _navigatedAway = true;
      // 2. Save last connected device info
      ref.read(settingsProvider.notifier).setLastDevice(device.deviceName, device.deviceType);
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Connection failed'), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      );
      _startDiscovery();
    }
  }

  @override
  void dispose() {
    _connection.removeListener(_onConnectionStateChanged);
    _connection.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appConnectionProvider);
    final ext = context.appColors;
    final topOffset = FsAppBar.bodyTopPadding(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: StreamBuilder<List<DeviceModel>>(
              stream: _connection.orchestrator.discoveredDevices,
              initialData: const [],
              builder: (context, snapshot) {
                final devices = snapshot.data ?? [];
                if (_connection.state == app.ConnectionState.connecting) {
                  return _buildConnectingState(ext);
                }
                if (devices.isEmpty) {
                  return _buildEmptyState(context, ext);
                }
                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(20, topOffset, 20, 40),
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) =>
                      _buildDeviceCard(context, devices[index], ext, index),
                );
              },
            ),
          ),
          FsAppBar(
            title: 'Nearby Devices',
            onBack: () => Navigator.pop(context),
            trailing: _connection.state == app.ConnectionState.discovering
                ? const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5, strokeCap: StrokeCap.round)),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(BuildContext context, DeviceModel device, AppThemeExtension ext, int index) {
    final isWindows = device.deviceType == 'windows';
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + (index * 100)),
      builder: (context, value, child) => Transform.translate(offset: Offset(0, 20 * (1 - value)), child: Opacity(opacity: value, child: child)),
      child: AppAnimations.scaleOnTap(
        onTap: () => _connectToDevice(device),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(24), boxShadow: ext.antiGravityShadow),
          child: Row(
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(gradient: LinearGradient(colors: [Theme.of(context).primaryColor.withValues(alpha: 0.1), Theme.of(context).primaryColor.withValues(alpha: 0.05)]), shape: BoxShape.circle),
                child: Icon(isWindows ? Icons.desktop_windows_rounded : Icons.phone_android_rounded, color: Theme.of(context).primaryColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.deviceName, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text(isWindows ? 'Windows Desktop' : 'Android Mobile', style: TextStyle(color: ext.textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: ext.textMuted.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectingState(AppThemeExtension ext) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 5, strokeCap: StrokeCap.round)),
          const SizedBox(height: 32),
          Text('Securing Connection...', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 8),
          Text('Keep both devices close', style: TextStyle(color: ext.textMuted)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppThemeExtension ext) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.radar_rounded, size: 80, color: Theme.of(context).primaryColor.withValues(alpha: 0.2)),
          const SizedBox(height: 32),
          Text('Scanning for Devices', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text('Make sure both devices have Bluetooth and Wi-Fi enabled.', textAlign: TextAlign.center, style: TextStyle(color: ext.textMuted, fontSize: 14, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
