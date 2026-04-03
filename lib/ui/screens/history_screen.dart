import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wifi_ftp/core/providers.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';
import 'package:wifi_ftp/ui/theme/app_animations.dart';
import 'package:wifi_ftp/ui/widgets/fs_app_bar.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(transferHistoryProvider);
    final ext = context.appColors;
    final topOffset = FsAppBar.bodyTopPadding(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: history.records.isEmpty
                ? _buildEmptyState(context, ext)
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(20, topOffset, 20, 40),
                    itemCount: history.records.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _buildHistoryCard(context, history.records[index], ext, index),
                  ),
          ),
          FsAppBar(
            title: 'History',
            onBack: () => Navigator.pop(context),
            trailing: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AppAnimations.scaleOnTap(
                onTap: () => _confirmClear(context, ref),
                child: Text('Clear', style: TextStyle(color: ext.danger, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, dynamic record, AppThemeExtension ext, int index) {
    final isSending = record.direction == 'sent';
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 50)),
      builder: (context, value, child) => Transform.translate(offset: Offset(0, 10 * (1 - value)), child: Opacity(opacity: value, child: child)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20), boxShadow: ext.antiGravityShadow),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: (isSending ? Theme.of(context).primaryColor : ext.success).withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(isSending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, color: isSending ? Theme.of(context).primaryColor : ext.success, size: 18),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.fileName, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 2),
                  Text(record.deviceName, style: TextStyle(color: ext.textMuted, fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(record.fileSizeFormatted, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                Text(_formatDate(record.timestamp), style: TextStyle(color: ext.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) => '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

  Widget _buildEmptyState(BuildContext context, AppThemeExtension ext) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.history_toggle_off_rounded, size: 80, color: Theme.of(context).primaryColor.withValues(alpha: 0.1)), const SizedBox(height: 24), Text('No History Yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)), const SizedBox(height: 8), Text('Your transfers will appear here', style: TextStyle(color: ext.textMuted))]));
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Clear History?',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
            letterSpacing: -0.5,
          ),
        ),
        content: const Text('This will remove all transfer records permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600))),
          TextButton(
            onPressed: () {
              ref.read(transferHistoryProvider).clear();
              Navigator.pop(ctx);
            },
            child: Text('Clear All', style: TextStyle(color: context.appColors.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}