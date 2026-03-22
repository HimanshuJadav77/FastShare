import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:wifi_ftp/core/networking/app_connection.dart' as app;
import 'package:wifi_ftp/core/transfer/transfer_queue.dart';
import 'package:wifi_ftp/core/providers.dart';
import 'package:wifi_ftp/ui/widgets/app_app_bar.dart';
import 'package:wifi_ftp/ui/widgets/app_card.dart';
import 'package:wifi_ftp/ui/widgets/app_button.dart';
import 'package:wifi_ftp/ui/widgets/connection_banner.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';

class TransferDashboard extends ConsumerStatefulWidget {
  const TransferDashboard({super.key});

  @override
  ConsumerState<TransferDashboard> createState() => _TransferDashboardState();
}

class _TransferDashboardState extends ConsumerState<TransferDashboard> {
  late final app.AppConnection _connection;
  late final TransferQueue _queue;

  @override
  void initState() {
    super.initState();
    _connection = ref.read(appConnectionProvider);
    _queue = ref.read(transferQueueProvider);
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || result.files.isEmpty) return;
      if (!_connection.isConnected) return;

      final peerIp = _connection.connectedDevice?.ip;
      if (peerIp == null) return;

      _connection.setTransferring();

      final newItems = result.files
          .where((f) => f.path != null)
          .map((f) => TransferItem(
                id: const Uuid().v4(),
                fileName: f.name,
                fileSize: f.size,
                direction: TransferDirection.sending,
                status: TransferItemStatus.waiting,
                localFile: File(f.path!),
              ))
          .toList();

      _queue.addItems(newItems);
      _connection.fileTransfer.sendFiles(peerIp, newItems);
    } catch (e) {
      debugPrint('Error picking files: $e');
    }
  }

  void _confirmDisconnect() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.appColors.textMuted.withValues(alpha: 0.2)),
        ),
        title: const Text('Disconnect?'),
        content: Text(
          'Are you sure you want to disconnect from ${_connection.connectedDevice?.deviceName ?? "this device"}? Any active transfers will be cancelled.',
          style: TextStyle(color: context.appColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: TextStyle(color: context.appColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _connection.disconnect();
              if (mounted) {
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: context.appColors.danger),
            child: const Text('DISCONNECT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch for reactive updates
    ref.watch(appConnectionProvider);
    ref.watch(transferQueueProvider);

    final allItems = _queue.allSortedItems;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppAppBar(
        title: 'TRANSFERS',
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: Theme.of(context).appBarTheme.iconTheme?.color),
          onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
        ),
        actions: [
          if (_connection.isConnected)
            IconButton(
              icon: Icon(Icons.power_settings_new, color: context.appColors.danger),
              onPressed: _confirmDisconnect,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const ConnectionBanner(),
            _buildTopProgressBanner(),
  
            // ─── Unified Content List ───
            Expanded(
              child: allItems.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: allItems.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _buildTransferTile(allItems[index]),
                    ),
            ),
  
            // ─── Pick Files Button ───
            if (_connection.isConnected)
              Padding(
                padding: const EdgeInsets.all(16),
                child: AppButton(
                  isFullWidth: true,
                  text: 'PICK FILES',
                  icon: Icons.add,
                  onPressed: _pickFiles,
                ),
              ),
          ],
        ),
      ),
    );
  }

    // Eliminated custom buildConnectionBanner in favor of reusable ConnectionBanner

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swap_vert, size: 80, color: Colors.white12),
          SizedBox(height: 16),
          Text('No transfers yet', style: TextStyle(color: Colors.white38, fontSize: 18)),
          SizedBox(height: 8),
          Text('Tap PICK FILES to send something', style: TextStyle(color: Colors.white24, fontSize: 14)),
        ],
      ),
    );
  }



  Widget _buildTopProgressBanner() {
    final speedMB = _queue.totalSpeed / (1024 * 1024);
    final ext = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: ext.textMuted.withValues(alpha: 0.1))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _queue.receivedCountInfo,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          if (_queue.hasActiveTransfers)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${speedMB.toStringAsFixed(1)} MB/s',
                style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTransferTile(TransferItem item) {
    final ext = context.appColors;
    final statusColor = switch (item.status) {
      TransferItemStatus.waiting => ext.textMuted,
      TransferItemStatus.transferring => Theme.of(context).primaryColor,
      TransferItemStatus.paused => ext.warning,
      TransferItemStatus.completed => ext.success,
      TransferItemStatus.failed => ext.danger,
    };

    final statusIcon = switch (item.status) {
      TransferItemStatus.waiting => Icons.schedule,
      TransferItemStatus.transferring => Icons.sync,
      TransferItemStatus.paused => Icons.pause_circle_filled,
      TransferItemStatus.completed => Icons.check_circle_rounded,
      TransferItemStatus.failed => Icons.error_rounded,
    };

    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: () {
        if (item.status == TransferItemStatus.completed && item.localFile != null) {
          OpenFilex.open(item.localFile!.path);
        }
      },
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon, color: statusColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.fileName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(item.fileSizeFormatted, style: TextStyle(color: ext.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              if (item.status == TransferItemStatus.transferring || item.status == TransferItemStatus.paused)
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (item.isPaused) {
                          ref.read(transferQueueProvider).resumeItem(item.id);
                          app.AppConnection().sendTransferControl('RESUME_TRANSFER', item.id);
                        } else {
                          ref.read(transferQueueProvider).pauseItem(item.id);
                          app.AppConnection().sendTransferControl('PAUSE_TRANSFER', item.id);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: ext.warning.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: Icon(item.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: ext.warning, size: 18),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        ref.read(transferQueueProvider).cancelItem(item.id);
                        app.AppConnection().sendTransferControl('CANCEL_TRANSFER', item.id);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: ext.danger.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: Icon(Icons.close_rounded, color: ext.danger, size: 18),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (item.status == TransferItemStatus.transferring || item.status == TransferItemStatus.paused)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${(item.progress * 100).toStringAsFixed(0)}%', style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('${item.speedFormatted} • ETA ${item.etaFormatted}', style: TextStyle(color: ext.textMuted, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: item.progress),
                      duration: const Duration(milliseconds: 250),
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        backgroundColor: ext.textMuted.withValues(alpha: 0.1),
                        color: statusColor,
                        minHeight: 6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
