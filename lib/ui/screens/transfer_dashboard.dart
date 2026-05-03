import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:wifi_ftp/core/networking/app_connection.dart' as app;
import 'package:wifi_ftp/core/transfer/transfer_queue.dart';
import 'package:wifi_ftp/core/transfer/file_transfer_service.dart';
import 'package:wifi_ftp/core/transfer/transfer_telemetry.dart';
import 'package:wifi_ftp/core/providers.dart';
import 'package:wifi_ftp/ui/widgets/storage_browser.dart';
import 'package:wifi_ftp/ui/widgets/fs_app_bar.dart';
import 'package:wifi_ftp/ui/theme/app_theme.dart';
import 'package:wifi_ftp/ui/theme/app_animations.dart';

class TransferDashboard extends ConsumerStatefulWidget {
  const TransferDashboard({super.key});

  @override
  ConsumerState<TransferDashboard> createState() => _TransferDashboardState();
}

class _TransferDashboardState extends ConsumerState<TransferDashboard> {
  late final app.AppConnection _conn;
  late final FileTransferService _ft;
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    _conn = ref.read(appConnectionProvider);
    _ft = FileTransferService();
  }

  Future<void> _pickFiles() async {
    if (_isPicking) return;
    _isPicking = true;
    try {
      List<String>? paths;
      if (Platform.isAndroid) {
        paths = await showModalBottomSheet<List<String>>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const StorageBrowser(),
        );
      } else {
        final result = await FilePicker.platform.pickFiles(allowMultiple: true);
        if (result != null) paths = result.paths.whereType<String>().toList();
      }
      if (paths == null || paths.isEmpty || !_conn.isConnected) return;
      final peerIp = _conn.connectedDevice?.ip;
      if (peerIp == null) return;

      _conn.setTransferring();
      final newItems = <TransferItem>[];
      final pathsList = paths.toList();
      for (int i = 0; i < pathsList.length; i++) {
        final p = pathsList[i];
        final f = File(p);
        if (!f.existsSync()) continue;
        newItems.add(TransferItem(
          id: const Uuid().v4(),
          fileName: p.split(Platform.pathSeparator).last,
          fileSize: f.lengthSync(),
          direction: TransferDirection.sending,
          status: TransferItemStatus.waiting,
          localFile: f,
          batchIndex: i + 1,
          batchTotal: pathsList.length,
        ));
      }
      if (newItems.isNotEmpty) {
        ref.read(transferQueueProvider.notifier).addItems(newItems);
        _ft.setPeerIp(peerIp);
        _conn.sendSessionFiles(newItems);
        _ft.processQueue();
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(appConnectionProvider);
    final ext = context.appColors;
    // Watch the queue state — this correctly triggers rebuilds when items change.
    final queueState = ref.watch(transferQueueProvider);
    final currentFilter = ref.watch(transferFilterProvider);

    // Apply filtering (Exhaustive switch)
    final filteredItems = switch (currentFilter) {
      TransferFilter.all => queueState,
      TransferFilter.pending => queueState.where((i) => i.status == TransferItemStatus.waiting || i.status == TransferItemStatus.transferring || i.status == TransferItemStatus.paused).toList(),
      TransferFilter.completed => queueState.where((i) => i.status == TransferItemStatus.completed).toList(),
      TransferFilter.cancelled => queueState.where((i) => i.status == TransferItemStatus.failed || i.isCancelled).toList(),
    };

    // Compute sorted order: Active > Pending > Failed > Completed
    final allItems = [
      ...filteredItems.where((i) => i.status == TransferItemStatus.transferring),
      ...filteredItems.where((i) => i.status == TransferItemStatus.waiting || i.status == TransferItemStatus.paused),
      ...filteredItems.where((i) => i.status == TransferItemStatus.failed),
      ...filteredItems.where((i) => i.status == TransferItemStatus.completed),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(builder: (context, constraints) {
              return Center(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth > 800 ? 800 : double.infinity,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      SizedBox(height: FsAppBar.bodyTopPadding(context)),
                      _SummaryHeader(ext: ext),
                      const SizedBox(height: 20),
                      _FilterChips(ext: ext),
                      const SizedBox(height: 12),
                      Expanded(
                        child: allItems.isEmpty
                            ? _buildEmptyState(ext)
                            : ListView.separated(
                                padding: const EdgeInsets.only(bottom: 120),
                                itemCount: allItems.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 16),
                                itemBuilder: (_, i) => _TransferCard(
                                  item: allItems[i], ext: ext, index: i,
                                  onPause: () => _pauseOrResume(allItems[i]),
                                  onCancel: () => _cancel(allItems[i]),
                                  onResume: () => _resume(allItems[i]),
                                  onRetry: () => _retry(allItems[i]),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),

          // ─── Send Files FAB ───
          if (conn.isConnected)
            Positioned(
              bottom: 30, left: 24, right: 24,
              child: AppAnimations.scaleOnTap(
                onTap: _pickFiles,
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: ext.primaryGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                      blurRadius: 20, offset: const Offset(0, 10),
                    )],
                  ),
                  child: const Center(
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 24),
                      SizedBox(width: 8),
                      Text('Send Files', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
              ),
            ),

          // ─── Floating pill header ───
          FsAppBar(
            title: 'Transfer',
            subtitle: conn.isConnected ? 'Connected to ${conn.connectedDevice?.deviceName}' : 'Disconnected',
            onBack: () => Navigator.popUntil(context, (r) => r.isFirst),
            trailing: conn.isConnected
                ? AppAnimations.scaleOnTap(
                    onTap: _confirmDisconnect,
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: ext.danger.withValues(alpha: 0.15), shape: BoxShape.circle),
                      child: Icon(Icons.power_settings_new_rounded, color: ext.danger, size: 18),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  void _pauseOrResume(TransferItem item) {
    if (item.direction == TransferDirection.sending) {
      if (item.isPaused) {
        _ft.resumeSender(item.id);
        _conn.sendTransferControl('RESUME_TRANSFER', item.id);
      } else {
        _ft.pauseSender(item.id);
        _conn.sendTransferControl('PAUSE_TRANSFER', item.id);
      }
    } else {
      // Receiving side — update queue AND tell the sender device to stop sending
      final q = ref.read(transferQueueProvider.notifier);
      if (item.isPaused) {
        q.resumeItem(item.id);
        _conn.sendTransferControl('RESUME_TRANSFER', item.id);
      } else {
        q.pauseItem(item.id);
        _conn.sendTransferControl('PAUSE_TRANSFER', item.id);
      }
    }
  }

  void _cancel(TransferItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Transfer?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to cancel "${item.fileName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Keep', style: TextStyle(color: Theme.of(context).primaryColor)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (item.direction == TransferDirection.sending) {
                _ft.cancelSender(item.id);
                _conn.sendTransferControl('CANCEL_TRANSFER', item.id);
              } else {
                _conn.sendTransferControl('CANCEL_TRANSFER', item.id);
                ref.read(transferQueueProvider.notifier).cancelItem(item.id);
              }
            },
            child: const Text('Cancel Transfer', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _resume(TransferItem item) {
    // Queue for resume (preserves bytesTransferred), then process
    ref.read(transferQueueProvider.notifier).queueForResume(item.id);
    if (item.direction == TransferDirection.sending) {
      _ft.setPeerIp(_conn.connectedDevice!.ip);
      _ft.processQueue();
    }
  }

  void _retry(TransferItem item) {
    // Full retry from zero bytes
    ref.read(transferQueueProvider.notifier).retryItem(item.id);
    if (item.direction == TransferDirection.sending) {
      _ft.setPeerIp(_conn.connectedDevice!.ip);
      _ft.processQueue();
    }
  }

  Widget _buildEmptyState(AppThemeExtension ext) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome_motion_rounded,
              size: 80, color: Theme.of(context).primaryColor.withValues(alpha: 0.15)),
          const SizedBox(height: 24),
          Text('No Active Transfers',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 8),
          Text('Pick some files to get started',
              style: TextStyle(color: ext.textMuted)),
        ]),
      );

  void _confirmDisconnect() {
    final ext = context.appColors;
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Text('End Session?',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                  letterSpacing: -0.5)),
          content: const Text(
              'This will stop all active transfers and disconnect the device.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Stay', style: TextStyle(fontWeight: FontWeight.w600))),
            ElevatedButton(
              onPressed: () {
                _conn.disconnect();
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

// ─── Summary header — rich breakdown of send/receive queues ───
class _SummaryHeader extends ConsumerWidget {
  final AppThemeExtension ext;
  const _SummaryHeader({required this.ext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(transferQueueProvider);
    final notifier = ref.read(transferQueueProvider.notifier);

    final activeSending = notifier.activeSendingCount;
    final activeReceiving = notifier.activeReceivingCount;
    final waitingSending = q.where((i) => i.direction == TransferDirection.sending && i.status == TransferItemStatus.waiting).length;
    final waitingReceiving = q.where((i) => i.direction == TransferDirection.receiving && i.status == TransferItemStatus.waiting).length;
    final totalActive = activeSending + activeReceiving;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: ext.antiGravityShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      totalActive > 0 ? 'Active Transfers' : 'Transfer Session',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      q.isEmpty ? 'No transfers yet' : '${q.length} file${q.length != 1 ? 's' : ''} in session',
                      style: TextStyle(color: ext.textMuted, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              if (totalActive > 0) _AggregateSpeedBadge(ext: ext),
            ],
          ),
          if (q.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _QueueLane(
                  icon: Icons.upload_rounded,
                  label: 'Sending',
                  active: activeSending,
                  waiting: waitingSending,
                  color: Theme.of(context).primaryColor,
                  ext: ext,
                )),
                const SizedBox(width: 12),
                Expanded(child: _QueueLane(
                  icon: Icons.download_rounded,
                  label: 'Receiving',
                  active: activeReceiving,
                  waiting: waitingReceiving,
                  color: ext.success,
                  ext: ext,
                )),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChips extends ConsumerWidget {
  final AppThemeExtension ext;
  const _FilterChips({required this.ext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(transferFilterProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(ref, 'All', TransferFilter.all, current == TransferFilter.all),
          _chip(ref, 'Pending', TransferFilter.pending, current == TransferFilter.pending),
          _chip(ref, 'Received', TransferFilter.completed, current == TransferFilter.completed),
          _chip(ref, 'Cancelled', TransferFilter.cancelled, current == TransferFilter.cancelled),
        ],
      ),
    );
  }

  Widget _chip(WidgetRef ref, String label, TransferFilter filter, bool active) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AppAnimations.scaleOnTap(
        onTap: () => ref.read(transferFilterProvider.notifier).setFilter(filter),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: active ? Theme.of(ref.context).primaryColor : ext.textMuted.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : ext.textMuted,
              fontWeight: active ? FontWeight.bold : FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact sending or receiving lane display
class _QueueLane extends StatelessWidget {
  final IconData icon;
  final String label;
  final int active;
  final int waiting;
  final Color color;
  final AppThemeExtension ext;

  const _QueueLane({required this.icon, required this.label, required this.active, required this.waiting, required this.color, required this.ext});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
                Text(
                  active > 0
                    ? '$active active${waiting > 0 ? ' • $waiting waiting' : ''}'
                    : waiting > 0 ? '$waiting waiting' : 'idle',
                  style: TextStyle(color: ext.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Aggregates speed from all active TelemetryNotifiers.
/// Uses a ticker to poll at 2fps — avoids listening to N notifiers individually.
class _AggregateSpeedBadge extends StatefulWidget {
  final AppThemeExtension ext;
  const _AggregateSpeedBadge({required this.ext});

  @override
  State<_AggregateSpeedBadge> createState() => _AggregateSpeedBadgeState();
}

class _AggregateSpeedBadgeState extends State<_AggregateSpeedBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMBs = FileTransferService()
        .telemetry
        .values
        .where((n) => n.value.state == TelemetryState.active)
        .fold<double>(0, (sum, n) => sum + n.value.speedMBs);

    return AnimatedBuilder(
      animation: _glow,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).primaryColor
                  .withValues(alpha: 0.2 * _glow.value),
              blurRadius: 15,
            ),
          ],
        ),
        child: Text(
          '${totalMBs.toStringAsFixed(1)} MB/s',
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─── Individual transfer card ───
class _TransferCard extends StatelessWidget {
  final TransferItem item;
  final AppThemeExtension ext;
  final int index;
  final VoidCallback onPause;
  final VoidCallback onCancel;
  final VoidCallback onResume;
  final VoidCallback onRetry;

  const _TransferCard({
    required this.item,
    required this.ext,
    required this.index,
    required this.onPause,
    required this.onCancel,
    required this.onResume,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = item.status == TransferItemStatus.completed;
    final statusColor = switch (item.status) {
      TransferItemStatus.waiting => ext.textMuted,
      TransferItemStatus.transferring => Theme.of(context).primaryColor,
      TransferItemStatus.paused => ext.warning,
      TransferItemStatus.completed => ext.success,
      TransferItemStatus.failed => ext.danger,
    };

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 80)),
      builder: (context, v, child) =>
          Transform.translate(offset: Offset(0, 12 * (1 - v)), child: Opacity(opacity: v, child: child)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: ext.antiGravityShadow,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isCompleted
                        ? Icons.check_circle_rounded
                        : item.isPaused
                            ? Icons.pause_rounded
                            : Icons.insert_drive_file_rounded,
                    color: statusColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(item.fileName,
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    letterSpacing: -0.3,
                                    color: Theme.of(context).colorScheme.onSurface),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (item.batchTotal > 1)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${item.batchIndex} of ${item.batchTotal}',
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.canResume
                            ? '${item.bytesTransferredFormatted} / ${item.fileSizeFormatted} • ${item.direction.name.toUpperCase()}'
                            : (item.batchTotal > 1 
                                ? '${item.batchIndex} of ${item.batchTotal} • ${item.fileSizeFormatted} • ${item.direction.name.toUpperCase()}'
                                : '${item.fileSizeFormatted} • ${item.direction.name.toUpperCase()}'),
                        style: TextStyle(
                            color: item.canResume ? Theme.of(context).primaryColor.withValues(alpha: 0.7) : ext.textMuted,
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                if (isCompleted)
                  AppAnimations.scaleOnTap(
                    onTap: () =>
                        item.localFile != null ? OpenFilex.open(item.localFile!.path) : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: ext.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('Open',
                          style: TextStyle(
                              color: ext.success,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
                  )
                else if (item.status == TransferItemStatus.failed)
                  Row(children: [
                    AppAnimations.scaleOnTap(
                      onTap: onRetry,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded, color: Theme.of(context).primaryColor, size: 14),
                            const SizedBox(width: 4),
                            Text('Retry', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                    if (!item.isCancelled) ...[
                      const SizedBox(width: 12),
                      AppAnimations.scaleOnTap(
                        onTap: onCancel,
                        child: Icon(Icons.close_rounded, color: ext.danger, size: 24),
                      ),
                    ],
                  ])
                else
                  Row(children: [
                    AppAnimations.scaleOnTap(
                      onTap: onPause,
                      child: Icon(
                          item.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                          color: ext.warning, size: 24),
                    ),
                    if (!item.isCancelled) ...[
                      const SizedBox(width: 12),
                      AppAnimations.scaleOnTap(
                        onTap: onCancel,
                        child: Icon(Icons.close_rounded, color: ext.danger, size: 24),
                      ),
                    ],
                  ]),
              ],
            ),
            // ── Progress bar — ONLY this subtree rebuilds on each telemetry tick ──
            if (!isCompleted)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _TelemetryProgressBar(
                  itemId: item.id,
                  isPaused: item.isPaused,
                  color: statusColor,
                  ext: ext,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Subscribes to one [TelemetryNotifier] and rebuilds only the progress bar.
/// The parent card widget never rebuilds on byte ticks.
class _TelemetryProgressBar extends StatelessWidget {
  final String itemId;
  final bool isPaused;
  final Color color;
  final AppThemeExtension ext;

  const _TelemetryProgressBar({
    required this.itemId,
    required this.isPaused,
    required this.color,
    required this.ext,
  });

  @override
  Widget build(BuildContext context) {
    final notifier = FileTransferService().telemetry[itemId];
    if (notifier == null) {
      return _bar(0.0, isPaused, 0.0, '--');
    }
    return ValueListenableBuilder<TransferTelemetry>(
      valueListenable: notifier,
      builder: (_, t, __) => _bar(
        t.progress,
        t.state == TelemetryState.paused || isPaused,
        t.speedMBs,
        t.eta,
      ),
    );
  }

  Widget _bar(double progress, bool paused, double mbPerSec, String eta) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              paused ? 'Paused' : '${(progress * 100).toInt()}%',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 12),
            ),
            if (!paused)
              Text(
                '${mbPerSec.toStringAsFixed(1)} MB/s • ETA $eta',
                style: TextStyle(
                    color: ext.textMuted, fontSize: 11, fontWeight: FontWeight.w500),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: ext.textMuted.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
