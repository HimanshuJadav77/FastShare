import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:wifi_ftp/core/transfer/transfer_history.dart';
import 'package:wifi_ftp/core/providers.dart';
import 'package:wifi_ftp/ui/widgets/app_app_bar.dart';
import 'package:wifi_ftp/ui/widgets/app_card.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final TransferHistory _history;

  @override
  void initState() {
    super.initState();
    _history = ref.read(transferHistoryProvider);
    _history.load();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(transferHistoryProvider);

    final records = _history.records;
    final sent = _history.sentRecords;
    final received = _history.receivedRecords;

    final ext = context.appColors;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppAppBar(
        title: 'HISTORY',
        actions: [
          if (records.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep, color: ext.danger),
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: records.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 80, color: Theme.of(context).disabledColor),
                  const SizedBox(height: 16),
                  Text('No transfer history', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: ext.textMuted)),
                  const SizedBox(height: 8),
                  Text('Completed transfers will appear here', style: TextStyle(color: ext.textMuted, fontSize: 13)),
                ],
              ),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Stats bar
                  _buildStatsBar(sent.length, received.length, ext),
                  const SizedBox(height: 24),

                  if (sent.isNotEmpty) ...[
                    _sectionHeader('SENT', Icons.arrow_upward, sent.length),
                    ...sent.map(_buildRecordTile),
                    const SizedBox(height: 20),
                  ],

                  if (received.isNotEmpty) ...[
                    _sectionHeader('RECEIVED', Icons.arrow_downward, received.length),
                    ...received.map(_buildRecordTile),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStatsBar(int sentCount, int receivedCount, AppThemeExtension ext) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statColumn('Total', '${sentCount + receivedCount}', Theme.of(context).primaryColor),
          _statColumn('Sent', '$sentCount', ext.success),
          _statColumn('Received', '$receivedCount', ext.warning),
        ],
      ),
    );
  }

  Widget _statColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28, color: color)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: context.appColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon, int count) {
    final ext = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
        children: [
          Icon(icon, color: ext.textMuted, size: 18),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(color: ext.textMuted, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5)),
          const Spacer(),
          Text('$count files', style: TextStyle(color: ext.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildRecordTile(TransferRecord record) {
    final isSent = record.direction == 'sent';
    final ext = context.appColors;
    final color = isSent ? Theme.of(context).primaryColor : ext.success;

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              // Direction icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSent ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),

              // File info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.fileName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${isSent ? "To" : "From"} ${record.deviceName} • ${record.timeFormatted}',
                      style: TextStyle(color: ext.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),

              // Size
              Text(record.fileSizeFormatted, style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: () {
                  if (record.filePath != null) {
                    OpenFilex.open(record.filePath!);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('File path not found.', style: TextStyle(color: ext.textMuted)), backgroundColor: Theme.of(context).cardColor));
                  }
                },
                icon: Icon(Icons.folder_open, size: 18, color: ext.textMuted),
                label: Text('OPEN', style: TextStyle(color: ext.textMuted, fontSize: 12)),
              ),
              TextButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Share intents not connected.', style: TextStyle(color: ext.textMuted)), backgroundColor: Theme.of(context).cardColor));
                },
                icon: Icon(Icons.share, size: 18, color: ext.textMuted),
                label: Text('SHARE', style: TextStyle(color: ext.textMuted, fontSize: 12)),
              ),
              TextButton.icon(
                onPressed: () => _confirmDeleteRecord(record),
                icon: Icon(Icons.delete_outline, size: 18, color: ext.danger),
                label: Text('DELETE', style: TextStyle(color: ext.danger, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── PERFECT DELETE LOGIC ───
  void _confirmDeleteRecord(TransferRecord record) {
    bool deletePhysicalFile = false;
    final fileExists = record.filePath != null && File(record.filePath!).existsSync();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: context.appColors.textMuted.withValues(alpha: 0.2)),
            ),
            title: const Text('Delete Record?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Remove "${record.fileName}" from history?',
                  style: TextStyle(color: context.appColors.textMuted),
                ),
                if (fileExists) ...[
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: context.appColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.appColors.danger.withValues(alpha: 0.3)),
                    ),
                    child: CheckboxListTile(
                      value: deletePhysicalFile,
                      activeColor: context.appColors.danger,
                      checkColor: Colors.white,
                      title: const Text(
                        'Also delete actual file from device',
                        style: TextStyle(fontSize: 13, color: Colors.white),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setState(() => deletePhysicalFile = val ?? false);
                      },
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('CANCEL', style: TextStyle(color: context.appColors.textMuted, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  
                  // 1. Delete the physical file if requested
                  if (deletePhysicalFile && fileExists) {
                    try {
                      await File(record.filePath!).delete();
                    } catch (e) {
                      debugPrint('Failed to delete physical file: $e');
                    }
                  }

                  // 2. Delete from history state
                  _history.deleteRecord(record);

                  // 3. Show success
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Record deleted successfully', style: TextStyle(color: context.appColors.textMuted)),
                        backgroundColor: Theme.of(context).cardColor,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: context.appColors.danger),
                child: const Text('DELETE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.appColors.textMuted.withValues(alpha: 0.2)),
        ),
        title: const Text('Clear History?'),
        content: Text('This will permanently remove all transfer records.', style: TextStyle(color: context.appColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: TextStyle(color: context.appColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () {
              _history.clear();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: context.appColors.danger),
            child: const Text('CLEAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}