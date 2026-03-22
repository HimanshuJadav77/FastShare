import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wifi_ftp/core/networking/app_connection.dart' as app;
import 'package:wifi_ftp/core/providers.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';

class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(appConnectionProvider);
    final ext = context.appColors;

    final isConnected = connection.isConnected;
    final isDisconnected = connection.state == app.ConnectionState.disconnected;

    if (!isConnected && !isDisconnected) return const SizedBox.shrink();

    final bgColor = isConnected ? ext.connectionActive.withValues(alpha: 0.1) : ext.connectionInactive.withValues(alpha: 0.1);
    final fgColor = isConnected ? ext.connectionActive : ext.connectionInactive;
    final icon = isConnected ? Icons.link : Icons.link_off;
    final text = isConnected ? 'Connected to ${connection.connectedDevice?.deviceName ?? "Unknown"}' : 'Disconnected';

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Container(
          key: ValueKey(isConnected),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border(bottom: BorderSide(color: fgColor.withValues(alpha: 0.5), width: 0.5)),
          ),
          child: Row(
            children: [
              Icon(icon, color: fgColor, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: fgColor, fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isConnected)
                Icon(Icons.chevron_right, color: fgColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
