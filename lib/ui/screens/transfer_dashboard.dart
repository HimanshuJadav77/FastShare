import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:wifi_ftp/core/networking/app_connection.dart' as app;
import 'package:wifi_ftp/core/transfer/transfer_queue.dart';
import 'package:wifi_ftp/core/providers.dart';
import 'package:wifi_ftp/ui/widgets/storage_browser.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';
import 'package:wifi_ftp/ui/theme/app_animations.dart';

class TransferDashboard extends ConsumerStatefulWidget {
  const TransferDashboard({super.key});

  @override
  ConsumerState<TransferDashboard> createState() => _TransferDashboardState();
}

class _TransferDashboardState extends ConsumerState<TransferDashboard> {
  late final app.AppConnection _connection;
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    _connection = ref.read(appConnectionProvider);
  }

  Future<void> _pickFiles() async {
    if (_isPicking) return;
    _isPicking = true;
    try {
      List<String>? paths;
      if (Platform.isAndroid) {
        paths = await showModalBottomSheet<List<String>>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => const StorageBrowser());
      } else {
        final result = await FilePicker.platform.pickFiles(allowMultiple: true);
        if (result != null) paths = result.paths.whereType<String>().toList();
      }
      if (paths == null || paths.isEmpty || !_connection.isConnected) return;
      final peerIp = _connection.connectedDevice?.ip;
      if (peerIp == null) return;
      _connection.setTransferring();
      final queue = ref.read(transferQueueProvider);
      final newItems = <TransferItem>[];
      for (final p in paths) {
        final f = File(p);
        if (!f.existsSync()) continue;
        newItems.add(TransferItem(id: const Uuid().v4(), fileName: p.split(Platform.pathSeparator).last, fileSize: f.lengthSync(), direction: TransferDirection.sending, status: TransferItemStatus.waiting, localFile: f));
      }
      if (newItems.isNotEmpty) {
        queue.addItems(newItems);
        _connection.fileTransfer.sendFiles(peerIp, newItems);
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(appConnectionProvider);
    final queue = ref.watch(transferQueueProvider);
    final ext = context.appColors;
    final allItems = queue.allSortedItems;
    final topPadding = MediaQuery.paddingOf(context).top;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ─── Main Content ───
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                return Center(
                  child: Container(
                    constraints: BoxConstraints(maxWidth: isWide ? 800 : double.infinity),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        SizedBox(height: topPadding + 100),
                        _buildSummaryHeader(queue, ext),
                        const SizedBox(height: 24),
                        Expanded(
                          child: allItems.isEmpty
                              ? _buildEmptyState(ext)
                              : ListView.separated(
                                  padding: const EdgeInsets.only(bottom: 120),
                                  itemCount: allItems.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                                  itemBuilder: (context, index) => _buildTransferCard(allItems[index], ext, index),
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // ─── Pick Files Action ───
          if (conn.isConnected)
            Positioned(
              bottom: 30, left: 24, right: 24,
              child: AppAnimations.scaleOnTap(
                onTap: _pickFiles,
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(gradient: ext.primaryGradient, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))]),
                  child: const Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_rounded, color: Colors.white, size: 24), SizedBox(width: 8), Text('Send Files', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold))])),
                ),
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
                      AppAnimations.scaleOnTap(onTap: () => Navigator.popUntil(context, (r) => r.isFirst), child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20)),
                      const SizedBox(width: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Transfer', 
                            style: context.text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: Theme.of(context).colorScheme.onSurface,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(conn.isConnected ? 'Connected to ${conn.connectedDevice?.deviceName}' : 'Disconnected', style: TextStyle(color: ext.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const Spacer(),
                      if (conn.isConnected)
                        AppAnimations.scaleOnTap(onTap: _confirmDisconnect, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: ext.danger.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(Icons.power_settings_new_rounded, color: ext.danger, size: 20))),
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

  Widget _buildSummaryHeader(TransferQueue queue, AppThemeExtension ext) {
    final speedMB = queue.totalSpeed / (1024 * 1024);
    final isTransferring = queue.hasActiveTransfers;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(28), boxShadow: ext.antiGravityShadow),
      child: Row(
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(isTransferring ? 'Active Transfers' : 'Transfer Session', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)), const SizedBox(height: 4), Text(queue.receivedCountInfo, style: TextStyle(color: ext.textMuted, fontSize: 13, fontWeight: FontWeight.w500))])),
          if (isTransferring) _ActiveSpeedGlow(speedMB: speedMB, ext: ext),
        ],
      ),
    );
  }

  Widget _buildTransferCard(TransferItem item, AppThemeExtension ext, int index) {
    final isCompleted = item.status == TransferItemStatus.completed;
    final isPaused = item.status == TransferItemStatus.paused;
    final statusColor = switch (item.status) { TransferItemStatus.waiting => ext.textMuted, TransferItemStatus.transferring => Theme.of(context).primaryColor, TransferItemStatus.paused => ext.warning, TransferItemStatus.completed => ext.success, TransferItemStatus.failed => ext.danger };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 80)),
      builder: (context, value, child) => Transform.translate(offset: Offset(0, 15 * (1 - value)), child: Opacity(opacity: value, child: child)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(24), boxShadow: ext.antiGravityShadow),
        child: Column(
          children: [
            Row(
              children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(isCompleted ? Icons.check_circle_rounded : (isPaused ? Icons.pause_rounded : Icons.insert_drive_file_rounded), color: statusColor, size: 22)),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.fileName, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: -0.3, color: Theme.of(context).colorScheme.onSurface), overflow: TextOverflow.ellipsis), const SizedBox(height: 2), Text('${item.fileSizeFormatted} • ${item.direction.name.toUpperCase()}', style: TextStyle(color: ext.textMuted, fontSize: 12, fontWeight: FontWeight.w600))])),
                if (!isCompleted) _buildActionButtons(item, ext),
                if (isCompleted) AppAnimations.scaleOnTap(onTap: () => item.localFile != null ? OpenFilex.open(item.localFile!.path) : null, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: ext.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Text('Open', style: TextStyle(color: ext.success, fontWeight: FontWeight.bold, fontSize: 12)))),
              ],
            ),
            if (!isCompleted) Padding(padding: const EdgeInsets.only(top: 16), child: _buildProgressBar(item, statusColor, ext)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(TransferItem item, AppThemeExtension ext) {
    return Row(children: [AppAnimations.scaleOnTap(onTap: () { if (item.isPaused) { ref.read(transferQueueProvider).resumeItem(item.id); _connection.sendTransferControl('RESUME_TRANSFER', item.id); } else { ref.read(transferQueueProvider).pauseItem(item.id); _connection.sendTransferControl('PAUSE_TRANSFER', item.id); } }, child: Icon(item.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: ext.warning, size: 24)), const SizedBox(width: 12), AppAnimations.scaleOnTap(onTap: () { ref.read(transferQueueProvider).cancelItem(item.id); _connection.sendTransferControl('CANCEL_TRANSFER', item.id); }, child: Icon(Icons.close_rounded, color: ext.danger, size: 24))]);
  }

  Widget _buildProgressBar(TransferItem item, Color color, AppThemeExtension ext) {
    return Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(item.status == TransferItemStatus.paused ? 'Paused' : '${(item.progress * 100).toInt()}%', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)), if (item.status != TransferItemStatus.paused) Text('${item.speedFormatted} • ETA ${item.etaFormatted}', style: TextStyle(color: ext.textMuted, fontSize: 11, fontWeight: FontWeight.w500))]), const SizedBox(height: 8), ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: item.progress, minHeight: 8, backgroundColor: ext.textMuted.withValues(alpha: 0.1), valueColor: AlwaysStoppedAnimation<Color>(color)))]);
  }

  Widget _buildEmptyState(AppThemeExtension ext) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome_motion_rounded, size: 80, color: Theme.of(context).primaryColor.withValues(alpha: 0.15)), const SizedBox(height: 24), Text('No Active Transfers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)), const SizedBox(height: 8), Text('Pick some files to get started', style: TextStyle(color: ext.textMuted))]));
  }

  void _confirmDisconnect() {
    final ext = context.appColors;
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Text(
            'End Session?',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
              letterSpacing: -0.5,
            ),
          ),
          content: const Text('This will stop all active transfers and disconnect the device.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Stay', style: TextStyle(fontWeight: FontWeight.w600))),
            ElevatedButton(
              onPressed: () {
                _connection.disconnect();
                Navigator.popUntil(context, (r) => r.isFirst);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: ext.danger,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Disconnect', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveSpeedGlow extends StatefulWidget {
  final double speedMB;
  final AppThemeExtension ext;
  const _ActiveSpeedGlow({required this.speedMB, required this.ext});
  @override
  State<_ActiveSpeedGlow> createState() => _ActiveSpeedGlowState();
}

class _ActiveSpeedGlowState extends State<_ActiveSpeedGlow> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true); }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) { return AnimatedBuilder(animation: _ctrl, builder: (context, _) => Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.2 * _ctrl.value), blurRadius: 15)]), child: Text('${widget.speedMB.toStringAsFixed(1)} MB/s', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.w900, fontSize: 13)))); }
}
