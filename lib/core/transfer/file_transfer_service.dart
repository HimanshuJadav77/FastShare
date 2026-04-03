import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:wifi_ftp/core/transfer/transfer_queue.dart';
import 'package:wifi_ftp/core/transfer/transfer_history.dart';
import 'package:wifi_ftp/core/transfer/transfer_telemetry.dart';
import 'package:wifi_ftp/core/transfer/isolate_sender.dart';
import 'package:wifi_ftp/core/transfer/isolate_receiver.dart';

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
  final int dataPort = 45557;
  final int parallelStreams = 3;         // 3 streams is optimal for WiFi; 6 was overkill
  final int chunkSize = 4 * 1024 * 1024; // 4 MB — 4× fewer iterations vs 1 MB
  // ────────────────────────────────────────────────────────────────────────

  final TransferQueue _queue = TransferQueue();
  final TransferHistory _history = TransferHistory();
  bool _receiving = false;

  String? customDownloadPath;
  bool autoResumeEnabled = true;

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
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {}
      
      if (Platform.isAndroid && dir == null) {
        final d = Directory('/storage/emulated/0/Download');
        try { if (!d.existsSync()) d.createSync(recursive: true); } catch (_) {}
        dir = d;
      }
      dir ??= await getApplicationDocumentsDirectory();
    }
    final saveDirStr = customDownloadPath != null
        ? dir.path
        : p.join(dir.path, 'FastShare');

    final replyPort = ReceivePort();
    final args = ReceiverIsolateArgs(
      replyPort: replyPort.sendPort,
      dataPort: dataPort,
      saveDirectory: saveDirStr,
      autoResumeEnabled: autoResumeEnabled,
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
        telemetry[msg.id] = TelemetryNotifier(fileSize: msg.size, initialBytes: 0);
        if (!_queue.items.any((i) => i.id == msg.id)) {
          _queue.addItem(TransferItem(
            id: msg.id, fileName: msg.name, fileSize: msg.size,
            direction: TransferDirection.receiving,
            status: TransferItemStatus.transferring,
            localFile: File('$saveDirStr/${msg.name}'),
          ));
        }
      } else if (msg is ReceiverTelemetryMsg) {
        final t = telemetry[msg.id];
        if (t != null) {
          t.updateFromIsolate(msg.bytesDone, msg.speedBps);
          // speed is set purely from isolate's 500ms precise chunks
          
          if (msg.isDone) {
            t.markDone();
            _queue.completeItem(msg.id);
            final item = _queue.items.firstWhere((i) => i.id == msg.id, orElse: () => _dummyItem);
            unawaited(_history.addRecord(TransferRecord(
              fileName: item.fileName, fileSize: item.fileSize,
              direction: 'received', deviceName: connectedDeviceName,
              timestamp: DateTime.now(),
            )));
          }
        }
      }
    });

    debugPrint('[FILE-RX] Background Receiver Isolate active on port $dataPort');
  }

  void updateReceiverConfig() {
    if (_receiverCmdPort != null) {
      // Re-resolve in main thread and pass update (mostly used if user changes settings mid-session)
      // Since directory resolution requires platform channels, we can't do it purely in isolate easily
      getDownloadsDirectory().then((dir) async {
        if (Platform.isAndroid && dir == null) {
          final d = Directory('/storage/emulated/0/Download');
          try { if (!d.existsSync()) d.createSync(recursive: true); } catch (_) {}
          dir = d;
        }
        dir ??= await getApplicationDocumentsDirectory();
        final saveDirStr = customDownloadPath != null
            ? customDownloadPath!
            : p.join(dir.path, 'FastShare');
            
        _receiverCmdPort!.send(ReceiverUpdateConfigMsg(
          saveDirectory: saveDirStr, 
          autoResumeEnabled: autoResumeEnabled,
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

  Future<void> sendFiles(String peerIp, List<TransferItem> items) async {
    for (final item in items.where((i) => i.status == TransferItemStatus.waiting)) {
      if (!item.localFile!.existsSync()) continue;
      final fileSize = item.localFile!.lengthSync();

      telemetry[item.id] ??= TelemetryNotifier(fileSize: fileSize);
      telemetry[item.id]!.setState(TelemetryState.active);

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
          } else if (msg.isError) {
            notifier.markError();
            _queue.failItem(item.id);
            _activeSenders.remove(item.id);
            replyPort.close();
          } else {
            notifier.updateFromIsolate(msg.bytesDone, msg.speedBps);
          }
        }
      });
    }
  }

  // ── Transfer controls ──

  void pauseSender(String itemId) {
    _activeSenders[itemId]?.$2?.send(SenderCmd.pause);
    telemetry[itemId]?.setState(TelemetryState.paused);
    _queue.pauseItem(itemId);
  }

  void resumeSender(String itemId) {
    _activeSenders[itemId]?.$2?.send(SenderCmd.resume);
    telemetry[itemId]?.setState(TelemetryState.active);
    _queue.resumeItem(itemId);
  }

  void cancelSender(String itemId) {
    _activeSenders[itemId]?.$2?.send(SenderCmd.cancel);
    telemetry[itemId]?.markError();
    _queue.cancelItem(itemId);
    _activeSenders.remove(itemId);
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
}
