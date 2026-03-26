import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_ftp/core/providers.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';
import 'package:wifi_ftp/ui/theme/app_animations.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _requestPermissionsAndNavigate(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await [
      Permission.location,
      Permission.storage,
      Permission.nearbyWifiDevices,
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
    final settings = ref.watch(settingsProvider);
    final ext = context.appColors;
    final topPadding = MediaQuery.paddingOf(context).top;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ─── Main Content ───
          ListView(
            padding: EdgeInsets.fromLTRB(24, topPadding + 100, 24, 40),
            children: [
              // ─── Status Banner & Active Session ───
              if (connection.isConnected)
                _buildActiveSessionCard(context, connection, ext)
              else
                _buildStatusBanner(context, settings, ext),

              const SizedBox(height: 32),

              // ─── The Single Entry Point: Nearby Devices ───
              AppAnimations.scaleOnTap(
                onTap: () => _requestPermissionsAndNavigate(context, ref),
                child: Container(
                  width: double.infinity,
                  height: 300,
                  decoration: BoxDecoration(
                    gradient: ext.primaryGradient,
                    borderRadius: BorderRadius.circular(36),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).primaryColor.withValues(alpha: 0.25),
                        blurRadius: 40,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.radar_rounded,
                          size: 72,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Nearby Devices',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        connection.isConnected
                            ? 'Connected to ${connection.connectedDevice?.deviceName}'
                            : 'Discoverable as ${settings.deviceName}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ─── Recent Device (User Requested) ───
              if (settings.lastDeviceName != null)
                _buildRecentDeviceCard(context, settings, ext),

              const SizedBox(height: 32),

              // ─── Secondary Actions ───
              Row(
                children: [
                  Expanded(
                    child: _buildSecondaryCard(
                      context,
                      'History',
                      Icons.history_rounded,
                      () => Navigator.pushNamed(context, '/history'),
                      ext,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSecondaryCard(
                      context,
                      'Settings',
                      Icons.settings_rounded,
                      () => Navigator.pushNamed(context, '/settings'),
                      ext,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ─── Frosty Glass Header ───
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  height: topPadding + 80,
                  padding: EdgeInsets.only(
                    top: topPadding,
                    left: 24,
                    right: 24,
                  ),
                  color: ext.glassBackground,
                  child: Row(
                    children: [
                      Text(
                        'WiFi Transfer',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      const Spacer(),
                      _buildOnlineIndicator(ext),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(
    BuildContext context,
    SettingsState settings,
    AppThemeExtension ext,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ext.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ext.success.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: ext.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Click On Near By Devices',
            style: TextStyle(
              color: ext.success,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          // Text(
          //   'v1.0.4',
          //   style: TextStyle(
          //     color: ext.textMuted.withValues(alpha: 0.5),
          //     fontSize: 11,
          //     fontWeight: FontWeight.bold,
          //   ),
          // ),
        ],
      ),
    );
  }

  Widget _buildRecentDeviceCard(
    BuildContext context,
    SettingsState settings,
    AppThemeExtension ext,
  ) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceMuted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Recent Connection',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: onSurfaceMuted,
              letterSpacing: 1.5,
            ),
          ),
        ),
        AppAnimations.scaleOnTap(
          onTap: () => Navigator.pushNamed(context, '/discovery'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: ext.antiGravityShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    settings.lastDeviceType == 'windows'
                        ? Icons.desktop_windows_rounded
                        : Icons.phone_android_rounded,
                    color: Theme.of(context).primaryColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.lastDeviceName ?? 'Unknown',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Last shared recently',
                        style: TextStyle(
                          color: onSurfaceMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.bolt_rounded,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSecondaryCard(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap,
    AppThemeExtension ext,
  ) {
    return AppAnimations.scaleOnTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(28),
          boxShadow: ext.antiGravityShadow,
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: Theme.of(context).primaryColor),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionCard(BuildContext context, dynamic conn, AppThemeExtension ext) {
    final device = conn.connectedDevice;
    return AppAnimations.scaleOnTap(
      onTap: () => Navigator.pushNamed(context, '/dashboard'),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [ext.success, const Color(0xFF30D158)]),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: ext.success.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Row(
          children: [
            const Icon(Icons.sync_rounded, color: Colors.white, size: 32),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Active Session', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                  Text('Connected to ${device?.deviceName ?? 'Device'}', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineIndicator(AppThemeExtension ext) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ext.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: ext.success, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(
            'Live',
            style: TextStyle(
              color: ext.success,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
