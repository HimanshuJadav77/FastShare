import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wifi_ftp/core/providers.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';
import 'package:wifi_ftp/ui/theme/app_animations.dart';
import 'package:wifi_ftp/core/transfer/file_transfer_service.dart';
import 'package:wifi_ftp/ui/widgets/fs_app_bar.dart';
import 'package:wifi_ftp/core/transfer/background_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final ext = context.appColors;

    final svc = FileTransferService();
    svc.customDownloadPath = settings.downloadPath;
    svc.chunkSize = settings.chunkSizeMB * 1024 * 1024;
    svc.parallelStreams = settings.parallelStreams;
    svc.dataPort = settings.dataPort;
    svc.autoResume = settings.autoResume;

    final conn = ref.watch(appConnectionProvider);
    conn.orchestrator.wifiService.discoveryPort = settings.discoveryPort;
    conn.orchestrator.wifiService.broadcastIntervalSeconds = settings.broadcastIntervalSeconds;

    BackgroundService().showProgressEnabled = settings.showProgressNotification;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, FsAppBar.bodyTopPadding(context), 20, 40),
              children: [

                // ─────────────────── DEVICE ──────────────────────────────────
                _sectionHeader('DEVICE'),
                _settingItem(context, ext,
                  title: 'Display Name',
                  value: settings.deviceName,
                  icon: Icons.badge_rounded,
                  onTap: () => _showNameDialog(context, ref, settings.deviceName),
                ),
                const SizedBox(height: 24),

                // ─────────────────── APPEARANCE ──────────────────────────────
                _sectionHeader('APPEARANCE'),
                _buildThemeSelector(context, ref, ext),
                const SizedBox(height: 24),

                // ─────────────────── TRANSFER ────────────────────────────────
                _sectionHeader('TRANSFER'),

                // Save location
                _settingItem(context, ext,
                  title: 'Save Location',
                  value: _truncatePath(settings.downloadPath),
                  icon: Icons.folder_open_rounded,
                  onTap: () async {
                    final result = await FilePicker.platform.getDirectoryPath();
                    if (result != null) {
                      ref.read(settingsProvider.notifier).setDownloadPath(result);
                    }
                  },
                ),
                const SizedBox(height: 8),

                // Chunk size
                _buildChunkSizeSelector(context, ref, settings.chunkSizeMB, ext),
                const SizedBox(height: 8),

                // Parallel streams
                _buildParallelStreamsSelector(context, ref, settings.parallelStreams, ext),
                const SizedBox(height: 24),

                // ─────────────────── NOTIFICATIONS ───────────────────────────
                if (Platform.isAndroid) ...[
                  _sectionHeader('NOTIFICATIONS'),
                  _buildToggleItem(context, ext,
                    title: 'Progress Notification',
                    subtitle: 'Show transfer progress in status bar',
                    icon: Icons.notifications_active_rounded,
                    value: settings.showProgressNotification,
                    onChanged: (v) => ref.read(settingsProvider.notifier).setShowProgressNotification(v),
                  ),
                  const SizedBox(height: 24),
                ],

                // ─────────────────── DISPLAY ─────────────────────────────────
                _sectionHeader('DISPLAY'),
                _buildToggleItem(context, ext,
                  title: 'Keep Screen On',
                  subtitle: 'Prevent screen sleep during transfers',
                  icon: Icons.screen_lock_portrait_rounded,
                  value: settings.keepScreenOn,
                  onChanged: (v) => ref.read(settingsProvider.notifier).setKeepScreenOn(v),
                ),
                const SizedBox(height: 24),

                // Auto-resume
                _buildToggleItem(context, ext,
                  title: 'Auto-Resume',
                  subtitle: 'Pick up partial transfers automatically',
                  icon: Icons.replay_rounded,
                  value: settings.autoResume,
                  onChanged: (v) => ref.read(settingsProvider.notifier).setAutoResume(v),
                ),
                const SizedBox(height: 24),

                // ─────────────────── DATA ────────────────────────────────────
                _sectionHeader('DATA'),
                _settingItem(context, ext,
                  title: 'Clear Transfer History',
                  value: 'Remove all history records',
                  icon: Icons.delete_sweep_rounded,
                  iconColor: ext.danger,
                  onTap: () => _confirmClearHistory(context, ref, ext),
                ),
                const SizedBox(height: 24),

                // ─────────────────── ABOUT ───────────────────────────────────
                _sectionHeader('ABOUT'),
                _settingItem(context, ext, title: 'Version', value: '1.2.0', icon: Icons.info_outline_rounded),
                const SizedBox(height: 8),
                _settingItem(context, ext, title: 'Developer', value: 'FastShare Team', icon: Icons.code_rounded),
              ],
            ),
          ),
          FsAppBar(title: 'Settings', onBack: () => Navigator.pop(context)),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(left: 12, bottom: 12),
    child: Text(
      title,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2),
    ),
  );

  String _truncatePath(String path) {
    if (path.length < 32) return path;
    return '...${path.substring(path.length - 29)}';
  }

  // ── Theme selector ───────────────────────────────────────────────────────

  Widget _buildThemeSelector(BuildContext context, WidgetRef ref, AppThemeExtension ext) {
    final mode = ref.watch(themeProvider);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: ext.antiGravityShadow,
      ),
      child: Column(children: [
        _themeItem(context, 'System Default', Icons.brightness_auto_rounded, ThemeMode.system, mode, ref, ext),
        Divider(height: 1, indent: 56, endIndent: 16, color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
        _themeItem(context, 'Light Mode', Icons.light_mode_rounded, ThemeMode.light, mode, ref, ext),
        Divider(height: 1, indent: 56, endIndent: 16, color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
        _themeItem(context, 'Dark Mode', Icons.dark_mode_rounded, ThemeMode.dark, mode, ref, ext),
      ]),
    );
  }

  Widget _themeItem(BuildContext context, String title, IconData icon, ThemeMode value, ThemeMode current, WidgetRef ref, AppThemeExtension ext) {
    final isSelected = value == current;
    return AppAnimations.scaleOnTap(
      onTap: () => ref.read(themeProvider.notifier).setTheme(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: Colors.transparent,
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isSelected ? Theme.of(context).primaryColor : Colors.grey).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isSelected ? Theme.of(context).primaryColor : Colors.grey, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Theme.of(context).colorScheme.onSurface))),
          if (isSelected) Icon(Icons.check_circle_rounded, color: Theme.of(context).primaryColor, size: 20),
        ]),
      ),
    );
  }

  // ── Chunk size ────────────────────────────────────────────────────────────

  Widget _buildChunkSizeSelector(BuildContext context, WidgetRef ref, int current, AppThemeExtension ext) {
    const options = [1, 4, 8];
    return _buildSegmentedRow(
      context: context,
      ext: ext,
      icon: Icons.memory_rounded,
      title: 'Chunk Size',
      subtitle: 'Larger = faster on stable WiFi',
      options: options.map((mb) => '${mb}MB').toList(),
      selectedIndex: options.indexOf(current).clamp(0, 2),
      onSelected: (i) => ref.read(settingsProvider.notifier).setChunkSizeMB(options[i]),
    );
  }

  // ── Parallel streams ──────────────────────────────────────────────────────

  Widget _buildParallelStreamsSelector(BuildContext context, WidgetRef ref, int current, AppThemeExtension ext) {
    const options = [1, 2, 3, 4, 6];
    final selectedIndex = options.indexOf(current).clamp(0, options.length - 1);
    return _buildSegmentedRow(
      context: context,
      ext: ext,
      icon: Icons.cable_rounded,
      title: 'Parallel Streams',
      subtitle: 'More streams = higher bandwidth use',
      options: options.map((n) => '$n').toList(),
      selectedIndex: selectedIndex,
      onSelected: (i) => ref.read(settingsProvider.notifier).setParallelStreams(options[i]),
    );
  }

  // ── Generic segmented-button row ──────────────────────────────────────────

  Widget _buildSegmentedRow({
    required BuildContext context,
    required AppThemeExtension ext,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<String> options,
    required int selectedIndex,
    required void Function(int) onSelected,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: ext.antiGravityShadow,
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, color: Theme.of(context).primaryColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
            Text(subtitle, style: TextStyle(color: ext.textMuted, fontSize: 11)),
          ],
        )),
        const SizedBox(width: 8),
        Wrap(
          spacing: 5,
          children: List.generate(options.length, (i) {
            final isSelected = i == selectedIndex;
            return AppAnimations.scaleOnTap(
              onTap: () => onSelected(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected ? Theme.of(context).primaryColor : Theme.of(context).primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  options[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Theme.of(context).primaryColor,
                  ),
                ),
              ),
            );
          }),
        ),
      ]),
    );
  }

  // ── Toggle item ───────────────────────────────────────────────────────────

  Widget _buildToggleItem(BuildContext context, AppThemeExtension ext, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required void Function(bool) onChanged,
    Color? iconColor,
  }) {
    final color = iconColor ?? Theme.of(context).primaryColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: ext.antiGravityShadow,
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
            Text(subtitle, style: TextStyle(color: ext.textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        )),
        Switch.adaptive(
          value: value,
          activeTrackColor: Theme.of(context).primaryColor.withValues(alpha: 0.5),
          activeThumbColor: Theme.of(context).primaryColor,
          onChanged: onChanged,
        ),
      ]),
    );
  }

  // ── Standard setting item ─────────────────────────────────────────────────

  Widget _settingItem(BuildContext context, AppThemeExtension ext, {
    required String title,
    required String value,
    required IconData icon,
    VoidCallback? onTap,
    Color? iconColor,
  }) {
    final color = iconColor ?? Theme.of(context).primaryColor;
    return AppAnimations.scaleOnTap(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: ext.antiGravityShadow,
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
              Text(value, style: TextStyle(color: ext.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          )),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: ext.textMuted.withValues(alpha: 0.4), size: 18),
        ]),
      ),
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showNameDialog(BuildContext context, WidgetRef ref, String current) {
    final controller = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Device Name',
          style: TextStyle(fontWeight: FontWeight.w900,
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
            letterSpacing: -0.5)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            labelText: 'Custom Name',
            labelStyle: TextStyle(color: context.appColors.textMuted),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600))),
          TextButton(
            onPressed: () {
              ref.read(settingsProvider.notifier).setDeviceName(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }



  void _confirmClearHistory(BuildContext context, WidgetRef ref, AppThemeExtension ext) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Clear History?',
          style: TextStyle(fontWeight: FontWeight.w900,
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
        content: const Text('This will permanently remove all transfer history records.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600))),
          TextButton(
            onPressed: () {
              ref.read(transferHistoryProvider.notifier).clear();
              Navigator.pop(ctx);
            },
            child: Text('Clear', style: TextStyle(color: ext.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
