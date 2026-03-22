import 'dart:io';
import 'package:flutter/foundation.dart';

class TransferItem {
  final String id;
  final String fileName;
  final int fileSize;
  final TransferDirection direction;
  double progress; // 0.0 - 1.0
  double speedBytesPerSec;
  TransferItemStatus status;
  File? localFile;
  bool isPaused;
  bool isCancelled;

  TransferItem({
    required this.id,
    required this.fileName, 
    required this.fileSize,
    required this.direction,
    this.progress = 0.0,
    this.speedBytesPerSec = 0.0,
    this.status = TransferItemStatus.waiting,
    this.localFile,
    this.isPaused = false,
    this.isCancelled = false,
  });

  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1024 * 1024 * 1024) return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get speedFormatted {
    if (speedBytesPerSec < 1024) return '${speedBytesPerSec.toStringAsFixed(0)} B/s';
    if (speedBytesPerSec < 1024 * 1024) return '${(speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String get etaFormatted {
    if (speedBytesPerSec <= 0 || progress >= 1.0) return '--';
    final remaining = fileSize * (1.0 - progress);
    final seconds = remaining / speedBytesPerSec;
    if (seconds < 60) return '${seconds.toStringAsFixed(0)}s';
    if (seconds < 3600) return '${(seconds / 60).toStringAsFixed(0)}m';
    return '${(seconds / 3600).toStringAsFixed(1)}h';
  }
}

enum TransferDirection { sending, receiving }
enum TransferItemStatus { waiting, transferring, paused, completed, failed }

class TransferQueue extends ChangeNotifier {
  static final TransferQueue _instance = TransferQueue._internal();
  factory TransferQueue() => _instance;
  TransferQueue._internal();

  final List<TransferItem> _items = [];
  List<TransferItem> get items => List.unmodifiable(_items);

  /// Unified list for UI (Active > Pending > Completed)
  List<TransferItem> get allSortedItems {
    final active = <TransferItem>[];
    final pending = <TransferItem>[];
    final completed = <TransferItem>[];

    for (final item in _items) {
      if (item.status == TransferItemStatus.transferring) {
        active.add(item);
      } else if (item.status == TransferItemStatus.waiting || item.status == TransferItemStatus.paused) {
        pending.add(item);
      } else if (item.status == TransferItemStatus.completed) {
        completed.add(item);
      }
    }
    return [...active, ...pending, ...completed];
  }

  bool get hasActiveTransfers => _items.any((i) => i.status == TransferItemStatus.transferring);
  
  List<TransferItem> get activeItems => _items.where((i) => i.status == TransferItemStatus.transferring).toList();
  List<TransferItem> get pendingItems => _items.where((i) => 
    i.status == TransferItemStatus.waiting || 
    i.status == TransferItemStatus.paused
  ).toList();
  List<TransferItem> get completedItems => _items.where((i) => i.status == TransferItemStatus.completed).toList();

  String get receivedCountInfo {
    final total = _items.length;
    final completed = completedItems.length;
    return '$completed of $total Received';
  }

  double get totalProgress {
    if (_items.isEmpty) return 0;
    return _items.fold(0.0, (sum, i) => sum + i.progress) / _items.length;
  }

  double get totalSpeed {
    return activeItems.fold(0.0, (sum, i) => sum + i.speedBytesPerSec);
  }

  void addItem(TransferItem item) {
    _items.add(item);
    notifyListeners();
  }

  void addItems(List<TransferItem> items) {
    _items.addAll(items);
    notifyListeners();
  }

  void updateProgress(String id, double progress, double speed) {
    final item = _items.firstWhere((i) => i.id == id, orElse: () => throw Exception('Item not found'));
    item.progress = progress;
    item.speedBytesPerSec = speed;
    if (item.status == TransferItemStatus.waiting) {
      item.status = TransferItemStatus.transferring;
    }
    notifyListeners();
  }

  void completeItem(String id) {
    final item = _items.firstWhere((i) => i.id == id, orElse: () => throw Exception('Item not found'));
    item.progress = 1.0;
    item.status = TransferItemStatus.completed;
    debugPrint('[TRANSFER] Completed: ${item.fileName}');
    notifyListeners();
  }

  void failItem(String id) {
    final item = _items.firstWhere((i) => i.id == id, orElse: () => throw Exception('Item not found'));
    item.status = TransferItemStatus.failed;
    debugPrint('[TRANSFER] Failed: ${item.fileName}');
    notifyListeners();
  }

  void pauseItem(String id) {
    final item = _items.firstWhere((i) => i.id == id, orElse: () => throw Exception('Item not found'));
    item.isPaused = true;
    item.status = TransferItemStatus.paused;
    notifyListeners();
  }

  void resumeItem(String id) {
    final item = _items.firstWhere((i) => i.id == id, orElse: () => throw Exception('Item not found'));
    item.isPaused = false;
    item.status = TransferItemStatus.transferring;
    notifyListeners();
  }

  void cancelItem(String id) {
    final item = _items.firstWhere((i) => i.id == id, orElse: () => throw Exception('Item not found'));
    item.isCancelled = true;
    item.status = TransferItemStatus.failed; // Or cancelled
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
