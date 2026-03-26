import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wifi_ftp/core/providers.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';
import 'package:wifi_ftp/ui/theme/app_animations.dart';
import 'package:wifi_ftp/core/transfer/file_transfer_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final ext = context.appColors;
    final topPadding = MediaQuery.paddingOf(context).top;

    // Sync settings to service singleton
    final service = FileTransferService();
    service.customDownloadPath = settings.downloadPath;
    service.autoResumeEnabled = settings.autoResumeEnabled;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ─── Main Content ───
          Positioned.fill(
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, topPadding + 100, 20, 40),
              children: [
                _buildSectionHeader('DEVICE IDENTITY'),
                _buildSettingItem(
                  context,
                  'Display Name',
                  settings.deviceName,
                  Icons.edit_rounded,
                  () => _showNameDialog(context, ref, settings.deviceName),
                  ext,
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('APPEARANCE'),
                _buildThemeSelector(context, ref, ext),
                const SizedBox(height: 24),
                _buildSectionHeader('TRANSFERS'),
                _buildSettingItem(
                  context,
                  'Default Path',
                  _truncatePath(settings.downloadPath),
                  Icons.folder_open_rounded,
                  () async {
                    String? result = await FilePicker.platform.getDirectoryPath();
                    if (result != null) {
                      ref.read(settingsProvider.notifier).setDownloadPath(result);
                    }
                  },
                  ext,
                ),
                _buildSettingItem(
                  context,
                  'Auto-Resume',
                  settings.autoResumeEnabled ? 'Enabled' : 'Disabled',
                  Icons.refresh_rounded,
                  () => ref.read(settingsProvider.notifier).toggleAutoResume(!settings.autoResumeEnabled),
                  ext,
                  trailing: Switch.adaptive(
                    value: settings.autoResumeEnabled,
                    activeColor: Theme.of(context).primaryColor,
                    onChanged: (v) => ref.read(settingsProvider.notifier).toggleAutoResume(v),
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('ABOUT'),
                _buildSettingItem(
                  context,
                  'Version',
                  '1.0.4',
                  Icons.info_outline_rounded,
                  null,
                  ext,
                ),
                _buildSettingItem(
                  context,
                  'Developer',
                  'FastShare Team',
                  Icons.code_rounded,
                  null,
                  ext,
                ),
              ],
            ),
          ),

          // ─── Frosty Glass Header ───
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: topPadding + 80,
                  padding: EdgeInsets.only(top: topPadding, left: 24, right: 24),
                  decoration: BoxDecoration(
                    color: ext.glassBackground,
                    border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      AppAnimations.scaleOnTap(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                      ),
                      const SizedBox(width: 20),
                      Text(
                        'Settings',
                        style: context.text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                          letterSpacing: -0.5,
                        ),
                      ),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2),
      ),
    );
  }

  String _truncatePath(String path) {
    if (path.length < 30) return path;
    return '...${path.substring(path.length - 27)}';
  }

  Widget _buildThemeSelector(BuildContext context, WidgetRef ref, AppThemeExtension ext) {
    final mode = ref.watch(themeProvider);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: ext.antiGravityShadow,
      ),
      child: Column(
        children: [
          _buildThemeItem(context, 'System Default', Icons.brightness_auto_rounded, ThemeMode.system, mode, ref, ext),
          Divider(height: 1, indent: 56, endIndent: 16, color: Colors.white.withValues(alpha: 0.05)),
          _buildThemeItem(context, 'Light Mode', Icons.light_mode_rounded, ThemeMode.light, mode, ref, ext),
          Divider(height: 1, indent: 56, endIndent: 16, color: Colors.white.withValues(alpha: 0.05)),
          _buildThemeItem(context, 'Dark Mode', Icons.dark_mode_rounded, ThemeMode.dark, mode, ref, ext),
        ],
      ),
    );
  }

  Widget _buildThemeItem(BuildContext context, String title, IconData icon, ThemeMode value, ThemeMode current, WidgetRef ref, AppThemeExtension ext) {
    final isSelected = value == current;
    return AppAnimations.scaleOnTap(
      onTap: () => ref.read(themeProvider.notifier).setTheme(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: Colors.transparent,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: (isSelected ? Theme.of(context).primaryColor : Colors.grey).withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: isSelected ? Theme.of(context).primaryColor : Colors.grey, size: 18),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Theme.of(context).colorScheme.onSurface))),
            if (isSelected) Icon(Icons.check_circle_rounded, color: Theme.of(context).primaryColor, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingItem(BuildContext context, String title, String value, IconData icon, VoidCallback? onTap, AppThemeExtension ext, {Widget? trailing}) {
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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: Theme.of(context).primaryColor, size: 18),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
                  if (onTap != null && trailing == null)
                    Text(value, style: TextStyle(color: ext.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            if (trailing != null) trailing
            else ...[
              if (onTap == null) Text(value, style: TextStyle(color: ext.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              if (onTap != null) Icon(Icons.chevron_right_rounded, color: ext.textMuted.withValues(alpha: 0.3), size: 18),
            ]
          ],
        ),
      ),
    );
  }

  void _showNameDialog(BuildContext context, WidgetRef ref, String current) {
    final controller = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Device Name',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
            letterSpacing: -0.5,
          ),
        ),
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
              ref.read(settingsProvider.notifier).setDeviceName(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
