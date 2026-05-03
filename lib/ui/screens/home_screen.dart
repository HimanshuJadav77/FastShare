import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_ftp/core/providers.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';
import 'package:wifi_ftp/ui/theme/app_animations.dart';
import 'package:wifi_ftp/ui/widgets/fs_app_bar.dart';

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
    final topOffset = FsAppBar.bodyTopPadding(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(24, topOffset + 10, 24, 40),
            children: [
              // ── Header ──
              Text(
                'Hello, ${settings.deviceName}',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ready to share files?',
                style: TextStyle(
                  fontSize: 15,
                  color: ext.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 40),

              // ── Primary Scan Action ──
              AppAnimations.scaleOnTap(
                onTap: () => _requestPermissionsAndNavigate(context, ref),
                child: Container(
                  width: double.infinity,
                  height: 300,
                  decoration: BoxDecoration(
                    gradient: ext.primaryGradient,
                    borderRadius: BorderRadius.circular(42),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).primaryColor.withValues(alpha: 0.3),
                        blurRadius: 40,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildRadarVisual(),
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          connection.isConnected
                              ? 'Connected to ${connection.connectedDevice?.deviceName}'
                              : 'Tap to start scanning',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── Recent / History / Settings ──
              if (!connection.isConnected &&
                  settings.lastDeviceName != null) ...[
                _buildRecentDeviceCard(context, settings, ext),
                const SizedBox(height: 32),
              ],

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

          // ── App Bar ──
          FsAppBar(title: 'FastShare'),
        ],
      ),
    );
  }

  Widget _buildRadarVisual() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Pulsing rings can be added here with animations
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.radar_rounded, size: 64, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildRecentDeviceCard(
    BuildContext context,
    SettingsState settings,
    AppThemeExtension ext,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'RECENT',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: ext.textMuted,
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
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'Last connected',
                        style: TextStyle(
                          color: ext.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
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
}

// class _OnlineChip extends StatelessWidget {
//   final AppThemeExtension ext;
//   const _OnlineChip({required this.ext});

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
//       margin: const EdgeInsets.only(right: 4),
//       decoration: BoxDecoration(
//         color: ext.success.withValues(alpha: 0.15),
//         borderRadius: BorderRadius.circular(20),
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Container(
//             width: 6,
//             height: 6,
//             decoration: BoxDecoration(
//               color: ext.success,
//               shape: BoxShape.circle,
//             ),
//           ),
//           const SizedBox(width: 6),
//           Text(
//             'Live',
//             style: TextStyle(
//               color: ext.success,
//               fontWeight: FontWeight.w900,
//               fontSize: 11,
//               letterSpacing: 0.5,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
