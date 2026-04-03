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
      final queue = ref.read(transferQueueProvider);
      final newItems = <TransferItem>[];
      for (final p in paths) {
        final f = File(p);
        if (!f.existsSync()) continue;
        newItems.add(TransferItem(
          id: const Uuid().v4(),
          fileName: p.split(Platform.pathSeparator).last,
          fileSize: f.lengthSync(),
          direction: TransferDirection.sending,
          status: TransferItemStatus.waiting,
          localFile: f,
        ));
      }
      if (newItems.isNotEmpty) {
        queue.addItems(newItems);
        _ft.sendFiles(peerIp, newItems);
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only rebuilds when list structure changes (add/complete/fail) — not on every byte
    final conn = ref.watch(appConnectionProvider);
    final queue = ref.watch(transferQueueProvider);
    final ext = context.appColors;
    final allItems = queue.allSortedItems;

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
                      const SizedBox(height: 24),
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
      // For receiving, we delegate to the queue
      final q = ref.read(transferQueueProvider);
      if (item.isPaused) { q.resumeItem(item.id); } else { q.pauseItem(item.id); }
    }
  }

  void _cancel(TransferItem item) {
    if (item.direction == TransferDirection.sending) {
      _ft.cancelSender(item.id);
    } else {
      ref.read(transferQueueProvider).cancelItem(item.id);
    }
    _conn.sendTransferControl('CANCEL_TRANSFER', item.id);
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

// ─── Summary header — rebuilds only when queue structure changes ───
class _SummaryHeader extends StatelessWidget {
  final AppThemeExtension ext;
  const _SummaryHeader({required this.ext});

  @override
  Widget build(BuildContext context) {
    // This widget is inside a Consumer so it gets the queue rebuild signals
    final queue = FileTransferService().telemetry;
    final activeCount = queue.values
        .where((n) => n.value.state == TelemetryState.active)
        .length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: ext.antiGravityShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activeCount > 0 ? 'Active Transfers' : 'Transfer Session',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  '$activeCount item${activeCount != 1 ? 's' : ''} transferring',
                  style: TextStyle(
                      color: ext.textMuted, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          if (activeCount > 0) _AggregateSpeedBadge(ext: ext),
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

  const _TransferCard({
    required this.item,
    required this.ext,
    required this.index,
    required this.onPause,
    required this.onCancel,
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
                      Text(item.fileName,
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: -0.3,
                              color: Theme.of(context).colorScheme.onSurface),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        '${item.fileSizeFormatted} • ${item.direction.name.toUpperCase()}',
                        style: TextStyle(
                            color: ext.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
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
                else
                  Row(children: [
                    AppAnimations.scaleOnTap(
                      onTap: onPause,
                      child: Icon(
                          item.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                          color: ext.warning, size: 24),
                    ),
                    const SizedBox(width: 12),
                    AppAnimations.scaleOnTap(
                      onTap: onCancel,
                      child: Icon(Icons.close_rounded, color: ext.danger, size: 24),
                    ),
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
