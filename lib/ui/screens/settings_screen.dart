import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wifi_ftp/core/providers/theme_provider.dart';
import 'package:wifi_ftp/core/providers/settings_provider.dart';
import 'package:wifi_ftp/ui/widgets/app_app_bar.dart';
import 'package:wifi_ftp/ui/widgets/app_card.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final ext = context.appColors;

    return Scaffold(
      appBar: const AppAppBar(title: 'SETTINGS'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader('DEVICE', ext),
            AppCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: const Text('Device Name'),
                subtitle: Text(ref.watch(settingsProvider).deviceName, style: TextStyle(color: ext.textMuted)),
                trailing: Icon(Icons.edit, size: 20, color: ext.textMuted),
                onTap: () => _showRenameDialog(context, ref),
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionHeader('APPEARANCE', ext),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  RadioListTile<ThemeMode>(
                    title: const Text('System Default'),
                    value: ThemeMode.system,
                    groupValue: themeMode,
                    activeColor: Theme.of(context).primaryColor,
                    onChanged: (mode) => mode != null ? ref.read(themeProvider.notifier).setTheme(mode) : null,
                  ),
                  const Divider(height: 1),
                  RadioListTile<ThemeMode>(
                    title: const Text('Light'),
                    value: ThemeMode.light,
                    groupValue: themeMode,
                    activeColor: Theme.of(context).primaryColor,
                    onChanged: (mode) => mode != null ? ref.read(themeProvider.notifier).setTheme(mode) : null,
                  ),
                  const Divider(height: 1),
                  RadioListTile<ThemeMode>(
                    title: const Text('Dark'),
                    value: ThemeMode.dark,
                    groupValue: themeMode,
                    activeColor: Theme.of(context).primaryColor,
                    onChanged: (mode) => mode != null ? ref.read(themeProvider.notifier).setTheme(mode) : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionHeader('ABOUT', ext),
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Fast Share', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Version 1.0.0', style: TextStyle(color: ext.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: ref.read(settingsProvider).deviceName);
    final ext = context.appColors;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.appColors.textMuted.withValues(alpha: 0.2)),
        ),
        title: const Text('Rename Device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter name',
            hintStyle: TextStyle(color: ext.textMuted),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ext.textMuted.withValues(alpha: 0.2))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: TextStyle(color: ext.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref.read(settingsProvider.notifier).setDeviceName(controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, AppThemeExtension ext) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: ext.textMuted,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
