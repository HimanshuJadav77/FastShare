import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:wifi_ftp/core/transfer/transfer_queue.dart';
import 'package:wifi_ftp/core/transfer/transfer_history.dart';
import 'package:wifi_ftp/core/transfer/transfer_telemetry.dart';
import 'package:wifi_ftp/core/transfer/isolate_sender.dart';
import 'package:wifi_ftp/core/transfer/isolate_receiver.dart';
import 'package:wifi_ftp/core/transfer/background_service.dart';
import 'package:wifi_ftp/core/providers.dart';
import 'package:wifi_ftp/main.dart';
import 'package:storage_space/storage_space.dart';

/// High-performance file transfer coordinator.
///
/// SENDER  → background Dart Isolate owns all sockets end-to-end.
///           No per-chunk SHA-256. 4 MB chunks. Flush only every 32 MB.
///
/// RECEIVER → background Dart Isolate handles socket I/O + Direct to Disk.
///            Prevents thousands of JSON/Buffer ops from choking UI thread.
///            UI updates only through ValueNotifier — never ChangeNotifier hot path.
class FileTransferService {
  static final FileTransferService _instance = FileTransferService._internal();
  factory FileTransferService() => _instance;
  FileTransferService._internal();

  // ── Tuning ──────────────────────────────────────────────────────────────
  int dataPort = 45557;
  int parallelStreams = 3;         // 3 streams is optimal for WiFi; 6 was overkill
  int chunkSize = 4 * 1024 * 1024; // 4 MB — 4× fewer iterations vs 1 MB
  bool autoResume = true;
  // ────────────────────────────────────────────────────────────────────────

  TransferQueueNotifier get _queue => appProviderContainer.read(transferQueueProvider.notifier);
  TransferHistoryNotifier get _history => appProviderContainer.read(transferHistoryProvider.notifier);
  bool _receiving = false;

  String? customDownloadPath;

  static GlobalKey<NavigatorState>? navigatorKey;
  String connectedDeviceName = 'Unknown';

  /// Per-item [TelemetryNotifier]. UI binds via [ValueListenableBuilder].
  final Map<String, TelemetryNotifier> telemetry = {};

  // Active sender isolates
  final Map<String, (Isolate, SendPort?)> _activeSenders = {};

  // Active receiver isolate
  Isolate? _receiverIsolate;
  SendPort? _receiverCmdPort;

  // ─────────────────────────── RECEIVER ───────────────────────────────────

  Future<void> startReceiver() async {
    if (_receiving) return;
    _receiving = true;

    Directory? dir;
    if (customDownloadPath != null && customDownloadPath!.isNotEmpty) {
      dir = Directory(customDownloadPath!);
    } else {
      if (Platform.isAndroid) {
        final d = Directory('/storage/emulated/0/download');
        try { if (!d.existsSync()) d.createSync(recursive: true); } catch (_) {}
        dir = d;
      } else {
        try {
          dir = await getDownloadsDirectory();
        } catch (_) {}
        dir ??= await getApplicationDocumentsDirectory();
      }
    }
    final saveDirStr = customDownloadPath != null
        ? dir.path
        : p.join(dir.path, 'Fastshare');

    final replyPort = ReceivePort();
    final args = ReceiverIsolateArgs(
      replyPort: replyPort.sendPort,
      dataPort: dataPort,
      saveDirectory: saveDirStr,
      autoResumeEnabled: autoResume, // Use setting value
      chunkSize: chunkSize,
    );

    _receiverIsolate = await Isolate.spawn(isolateReceiverEntry, args);

    replyPort.listen((msg) {
      if (msg is SendPort) {
        _receiverCmdPort = msg;
      } else if (msg is String && msg.startsWith('ERROR:')) {
        debugPrint('[FILE-RX] $msg');
        _receiving = false;
      } else if (msg is ReceiverOfferMsg) {
        // Check for storage space first
        _hasEnoughSpace(msg.size).then((hasSpace) {
          if (!hasSpace) {
             _showError('Storage Full', 'Not enough space to receive "${msg.name}".');
             _queue.failItem(msg.id);
             return;
          }
          
          telemetry[msg.id] = TelemetryNotifier(fileSize: msg.size, initialBytes: 0);
          BackgroundService().startBackgroundTransfer(msg.name, fileIndex: msg.batchIndex, totalFiles: msg.batchTotal);
          
          final localFile = File('$saveDirStr/${msg.name}');
          final existingIdx = appProviderContainer.read(transferQueueProvider).indexWhere((i) => i.id == msg.id);
          
          if (existingIdx >= 0) {
            _queue.updateItemStatus(msg.id, TransferItemStatus.transferring, localFile: localFile);
          } else {
            _queue.addItem(TransferItem(
              id: msg.id, fileName: msg.name, fileSize: msg.size,
              direction: TransferDirection.receiving,
              status: TransferItemStatus.transferring,
              localFile: localFile,
              batchIndex: msg.batchIndex,
              batchTotal: msg.batchTotal,
            ));
          }
        });
      } else if (msg is ReceiverTelemetryMsg) {
        final t = telemetry[msg.id];
        if (t != null) {
          t.updateFromIsolate(msg.bytesDone, msg.speedBps);
          
          if (t.fileSize > 0) {
            final item = appProviderContainer.read(transferQueueProvider)
                .cast<TransferItem?>().firstWhere((i) => i?.id == msg.id, orElse: () => null);
            final fileName = item?.fileName ?? 'file';
            BackgroundService().updateProgress(
              fileName: fileName,
              bytesDone: msg.bytesDone,
              totalBytes: t.fileSize,
              fileIndex: item?.batchIndex ?? 1,
              totalFiles: item?.batchTotal ?? 1,
            );
            _queue.updateProgress(msg.id, msg.bytesDone / t.fileSize, msg.speedBps, msg.bytesDone);
          }
          
          if (msg.isDone) {
            t.markDone();
            _queue.completeItem(msg.id);
            final item = appProviderContainer.read(transferQueueProvider).firstWhere((i) => i.id == msg.id, orElse: () => _dummyItem);
            unawaited(_history.addRecord(TransferRecord(
              fileName: item.fileName, fileSize: item.fileSize,
              direction: 'received', deviceName: connectedDeviceName,
              timestamp: DateTime.now(),
            )));
            
            // If all items complete, show completion notification
            final queueList = appProviderContainer.read(transferQueueProvider);
            if (queueList.isNotEmpty && queueList.every((i) => i.status == TransferItemStatus.completed || i.status == TransferItemStatus.failed)) {
               BackgroundService().showCompletionNotification();
            }
          }
        }
      }
    });

    debugPrint('[FILE-RX] Background Receiver Isolate active on port $dataPort');
  }

  void updateReceiverConfig() {
    if (_receiverCmdPort != null) {
      // Re-resolve in main thread and pass update
      Future(() async {
        final Directory dir;
        if (Platform.isAndroid) {
          final d = Directory('/storage/emulated/0/download');
          try { if (!d.existsSync()) d.createSync(recursive: true); } catch (_) {}
          dir = d;
        } else {
          Directory? d;
          try {
            d = await getDownloadsDirectory();
          } catch (_) {}
          dir = d ?? await getApplicationDocumentsDirectory();
        }
        final saveDirStr = customDownloadPath != null
            ? customDownloadPath!
            : p.join(dir.path, 'Fastshare');
            
        _receiverCmdPort!.send(ReceiverUpdateConfigMsg(
          saveDirectory: saveDirStr,
          autoResumeEnabled: autoResume,
        ));
      });
    }
  }

  static final _dummyItem = TransferItem(
    id: 'dummy', fileName: '', fileSize: 1,
    direction: TransferDirection.receiving,
    status: TransferItemStatus.transferring,
    localFile: File(''),
  );

  // ─────────────────────────── SENDER ─────────────────────────────────────

  String? _currentPeerIp;

  void setPeerIp(String ip) {
    _currentPeerIp = ip;
  }

  void processQueue() {
    if (_currentPeerIp == null) return;
    if (_activeSenders.isNotEmpty) return; // Strict Sequential Constraint!

    final nextItem = appProviderContainer.read(transferQueueProvider).cast<TransferItem?>().firstWhere(
      (i) => i!.status == TransferItemStatus.waiting && i.direction == TransferDirection.sending, 
      orElse: () => null
    );

    if (nextItem == null) {
      final queueList = appProviderContainer.read(transferQueueProvider);
      if (queueList.isNotEmpty && queueList.every((i) => i.status == TransferItemStatus.completed || i.status == TransferItemStatus.failed)) {
        BackgroundService().showCompletionNotification();
      }
      return;
    }

    BackgroundService().startBackgroundTransfer(
      'Sending ${nextItem.fileName}', 
      fileIndex: nextItem.batchIndex, 
      totalFiles: nextItem.batchTotal,
      initialProgress: nextItem.bytesTransferred,
      initialMax: nextItem.fileSize,
    );
    _sendSingleFile(_currentPeerIp!, nextItem);
  }

  Future<void> _sendSingleFile(String peerIp, TransferItem item) async {
    if (!item.localFile!.existsSync()) {
      _queue.failItem(item.id);
      processQueue();
      return;
    }
    final fileSize = item.localFile!.lengthSync();

    telemetry[item.id] ??= TelemetryNotifier(fileSize: fileSize);
    telemetry[item.id]!.setState(TelemetryState.active);

    // Compute resume offset from previously transferred bytes
    final resumeFromChunk = (item.bytesTransferred / chunkSize).floor();

    final replyPort = ReceivePort();
    final args = SenderIsolateArgs(
      replyPort: replyPort.sendPort,
      peerIp: peerIp,
      dataPort: dataPort,
      fileId: item.id,
      fileName: item.fileName,
      filePath: item.localFile!.path,
      fileSize: fileSize,
      chunkSize: chunkSize,
      parallelStreams: parallelStreams,
      resumeFromChunk: resumeFromChunk,
      batchIndex: item.batchIndex,
      batchTotal: item.batchTotal,
    );

    final isolate = await Isolate.spawn(isolateSenderEntry, args);
    _activeSenders[item.id] = (isolate, null);

    replyPort.listen((msg) {
      if (msg is SendPort) {
        _activeSenders[item.id] = (isolate, msg);
      } else if (msg is SenderTelemetry) {
        final notifier = telemetry[msg.fileId];
        if (notifier == null) return;
        if (msg.isDone) {
          notifier.markDone();
          _queue.completeItem(item.id);
          _activeSenders.remove(item.id);
          replyPort.close();
          unawaited(_history.addRecord(TransferRecord(
            fileName: item.fileName,
            fileSize: fileSize,
            direction: 'sent',
            deviceName: connectedDeviceName,
            timestamp: DateTime.now(),
          )));
          processQueue(); // Automatically start the next file!
        } else if (msg.isError) {
          notifier.markError();
          _queue.failItem(item.id);
          _activeSenders.remove(item.id);
          replyPort.close();
          processQueue(); // Automatically start the next file!
        } else {
          notifier.updateFromIsolate(msg.bytesDone, msg.speedBps);
          if (fileSize > 0) {
            BackgroundService().updateProgress(
              fileName: item.fileName,
              bytesDone: msg.bytesDone,
              totalBytes: fileSize,
              fileIndex: item.batchIndex,
              totalFiles: item.batchTotal,
            );
            _queue.updateProgress(item.id, msg.bytesDone / fileSize, msg.speedBps, msg.bytesDone);
          }
        }
      }
    });
  }

  // ── Transfer controls ──

  void pauseSender(String itemId) {
    _activeSenders[itemId]?.$2?.send(SenderCmd.pause);
    telemetry[itemId]?.setState(TelemetryState.paused);
    _queue.pauseItem(itemId);
  }

  void resumeSender(String itemId) {
    if (_activeSenders.containsKey(itemId)) {
      _activeSenders[itemId]?.$2?.send(SenderCmd.resume);
      telemetry[itemId]?.setState(TelemetryState.active);
      _queue.resumeItem(itemId);
    } else {
      // Isolate is dead (disconnect/failure) — restart fresh from saved offset
      _queue.queueForResume(itemId);
      processQueue();
    }
  }

  void cancelSender(String itemId) {
    _activeSenders[itemId]?.$2?.send(SenderCmd.cancel);
    telemetry[itemId]?.markError();
    _queue.cancelItem(itemId);
    _activeSenders.remove(itemId);
    processQueue(); // Automatically start the next file if this was the active one!
  }

  void pauseAllSenders() {
    for (final id in _activeSenders.keys.toList()) {
      pauseSender(id);
    }
  }

  void stopReceiver() {
    _receiving = false;
    _receiverCmdPort?.send(ReceiverCmd.stop);
    _receiverCmdPort = null;
    
    // Give isolate time to flush sockets then kill
    Future.delayed(const Duration(milliseconds: 200), () {
       _receiverIsolate?.kill(priority: Isolate.immediate);
       _receiverIsolate = null;
    });
  }

  bool get isReceiving => _receiving;

  Future<bool> _hasEnoughSpace(int bytes) async {
    if (!Platform.isAndroid) return true;
    try {
      final space = await getStorageSpace(lowOnSpaceThreshold: 200 * 1024 * 1024, fractionDigits: 2);
      return space.free >= bytes;
    } catch (e) {
      debugPrint('[STORAGE] Check failed: $e');
      return true;
    }
  }

  void _showError(String title, String message) {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) return;
    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }
}
