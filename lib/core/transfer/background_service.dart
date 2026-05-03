import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:wifi_ftp/core/providers.dart';
import 'package:wifi_ftp/core/transfer/transfer_queue.dart';
import 'package:wifi_ftp/main.dart';

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  /// Set to false via Settings → Progress Notification toggle to suppress progress updates.
  bool showProgressEnabled = true;

  Future<void> init() async {
    if (_isInitialized) return;
    if (!Platform.isAndroid) return;

    await FlutterForegroundTask.requestNotificationPermission();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'fastshare_transfer_channel',
        channelName: 'File Transfers',
        channelDescription: 'Maintains background file transfers',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    const AndroidInitializationSettings initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: initAndroid);
    await _notificationsPlugin.initialize(settings: initSettings);

    _isInitialized = true;
  }

  /// [fileName] — file name only
  /// [fileIndex] — 1-indexed current file (e.g. 1)
  /// [totalFiles] — total files in batch (e.g. 5)
  Future<void> startBackgroundTransfer(String fileName, {int fileIndex = 1, int totalFiles = 1, int initialProgress = 0, int initialMax = 100}) async {
    if (!Platform.isAndroid) return;
    final shortName = _truncateName(fileName);
    final title = 'FastShare — Transferring ($fileIndex of $totalFiles)';
    final pct = initialMax > 0 ? (initialProgress / initialMax * 100).toStringAsFixed(1) : '0.0';
    try {
      await FlutterForegroundTask.startService(
        serviceId: 888,
        notificationTitle: title,
        notificationText: '$shortName — $pct%',
      );
      _showProgressNotification(
        fileName: fileName,
        progress: initialProgress,
        maxProgress: initialMax,
        fileIndex: fileIndex,
        totalFiles: totalFiles,
      );
    } catch (_) {}
  }

  /// Update progress with session-wide context
  Future<void> updateProgress({
    required String fileName,
    required int bytesDone,
    required int totalBytes,
    required int fileIndex,
    required int totalFiles,
  }) async {
    if (!Platform.isAndroid) return;
    final pct = totalBytes > 0 ? (bytesDone / totalBytes * 100).toStringAsFixed(1) : '0.0';
    final shortName = _truncateName(fileName);
    final title = 'FastShare — Transferring ($fileIndex of $totalFiles)';
    
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: '$shortName — $pct%',
      );
      _showProgressNotification(
        fileName: fileName,
        progress: bytesDone,
        maxProgress: totalBytes,
        fileIndex: fileIndex,
        totalFiles: totalFiles,
      );
    } catch (_) {}
  }

  /// Truncates [name] to 10 visible chars + "…" for compact notification text.
  String _truncateName(String name) {
    if (name.length <= 10) return name;
    return '${name.substring(0, 10)}…';
  }

  void _showProgressNotification({
    required String fileName,
    required int progress,
    required int maxProgress,
    required int fileIndex,
    required int totalFiles,
  }) {
    if (!showProgressEnabled) return;

    final pct = maxProgress > 0 ? (progress / maxProgress * 100).toStringAsFixed(1) : '0.0';
    final shortName = _truncateName(fileName);
    
    // Collapsed line: "1 of 5 files • movie_sh… (42.3%)"
    final collapsedBody = '$fileIndex of $totalFiles files • $shortName ($pct%)';
    
    // Expanded text: full file name + progress + upcoming files
    final queue = appProviderContainer.read(transferQueueProvider);
    final waiting = queue.where((i) => i.status == TransferItemStatus.waiting).toList();
    String expandedBody = '$fileName\n$pct% complete  •  ${_formatBytes(progress)} of ${_formatBytes(maxProgress)}';
    
    if (waiting.isNotEmpty) {
      final names = waiting.take(3).map((i) => '• ${i.fileName}').join('\n');
      expandedBody += '\n\nUpcoming:\n$names';
      if (waiting.length > 3) expandedBody += '\n...and ${waiting.length - 3} more';
    }

    _notificationsPlugin.show(
      id: 888,
      title: 'FastShare — Transferring ($fileIndex of $totalFiles)',
      body: collapsedBody,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'fastshare_transfer_channel',
          'File Transfers',
          channelDescription: 'Maintains background file transfers',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: true,
          maxProgress: maxProgress > 0 ? maxProgress : 100,
          progress: progress,
          indeterminate: false,
          ongoing: true,
          onlyAlertOnce: true,
          styleInformation: BigTextStyleInformation(
            expandedBody,
            contentTitle: 'FastShare — Transferring ($fileIndex of $totalFiles)',
            summaryText: collapsedBody,
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> stopBackgroundTransfer() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.stopService();
      await _notificationsPlugin.cancel(id: 888);
    } catch (_) {}
  }

  /// Use id: 888 to overwrite the progress notification when complete
  Future<void> showCompletionNotification([String? customMessage]) async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.stopService();
      
      final queue = appProviderContainer.read(transferQueueProvider);
      final completed = queue.where((i) => i.status == TransferItemStatus.completed).toList();
      final total = queue.length;
      
      final isReceiving = queue.any((i) => i.direction == TransferDirection.receiving);
      final actionStr = isReceiving ? 'received' : 'sent';
      
      final title = '✅ All $total files $actionStr';
      final summary = customMessage ?? '$total files $actionStr successfully';
      
      final fileList = completed.take(8).map((i) => '✓ ${i.fileName}').join('\n');
      String expandedBody = fileList;
      if (completed.length > 8) expandedBody += '\n...and ${completed.length - 8} more';

      await _notificationsPlugin.show(
        id: 888, // OVERWRITE the progress notification
        title: title,
        body: summary,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'fastshare_transfer_channel',
            'File Transfers',
            importance: Importance.high,
            priority: Priority.high,
            ongoing: false,
            showProgress: true,
            maxProgress: 100,
            progress: 100,
            indeterminate: false,
            styleInformation: BigTextStyleInformation(
              expandedBody,
              contentTitle: title,
              summaryText: summary,
            ),
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> showDisconnectionNotification(String deviceName) async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.stopService();
      await _notificationsPlugin.show(
        id: 888,
        title: '❌ Disconnected',
        body: 'Connection with $deviceName was lost.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'fastshare_transfer_channel',
            'File Transfers',
            importance: Importance.high,
            priority: Priority.high,
            ongoing: false,
            icon: 'ic_launcher',
          ),
        ),
      );
    } catch (_) {}
  }
}
