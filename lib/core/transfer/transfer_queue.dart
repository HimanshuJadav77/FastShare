import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fully immutable. copyWith is the only way to change fields.
class TransferItem {
  final String id;
  final String fileName;
  final int fileSize;
  final TransferDirection direction;
  final double progress;        // 0.0 – 1.0
  final double speedBytesPerSec;
  final int bytesTransferred;   // Absolute bytes done — survives disconnect for resume
  final TransferItemStatus status;
  final File? localFile;
  final bool isPaused;
  final bool isCancelled;
  final bool isTempFile;
  final int batchIndex;         // 1-indexed (e.g. 1)
  final int batchTotal;         // Total in session (e.g. 5)

  const TransferItem({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.direction,
    this.progress = 0.0,
    this.speedBytesPerSec = 0.0,
    this.bytesTransferred = 0,
    this.status = TransferItemStatus.waiting,
    this.localFile,
    this.isPaused = false,
    this.isCancelled = false,
    this.isTempFile = false,
    this.batchIndex = 1,
    this.batchTotal = 1,
  });

  TransferItem copyWith({
    String? id,
    String? fileName,
    int? fileSize,
    TransferDirection? direction,
    double? progress,
    double? speedBytesPerSec,
    int? bytesTransferred,
    TransferItemStatus? status,
    File? localFile,
    bool? isPaused,
    bool? isCancelled,
    bool? isTempFile,
    int? batchIndex,
    int? batchTotal,
  }) {
    return TransferItem(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      direction: direction ?? this.direction,
      progress: progress ?? this.progress,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      status: status ?? this.status,
      localFile: localFile ?? this.localFile,
      isPaused: isPaused ?? this.isPaused,
      isCancelled: isCancelled ?? this.isCancelled,
      isTempFile: isTempFile ?? this.isTempFile,
      batchIndex: batchIndex ?? this.batchIndex,
      batchTotal: batchTotal ?? this.batchTotal,
    );
  }

  /// Whether this interrupted item can be resumed (has partial data)
  bool get canResume => bytesTransferred > 0 && bytesTransferred < fileSize;

  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1024 * 1024 * 1024) return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get bytesTransferredFormatted {
    if (bytesTransferred < 1024) return '$bytesTransferred B';
    if (bytesTransferred < 1024 * 1024) return '${(bytesTransferred / 1024).toStringAsFixed(1)} KB';
    if (bytesTransferred < 1024 * 1024 * 1024) return '${(bytesTransferred / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytesTransferred / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get speedFormatted {
    if (speedBytesPerSec < 1024) return '${speedBytesPerSec.toStringAsFixed(0)} B/s';
    if (speedBytesPerSec < 1024 * 1024) return '${(speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}

enum TransferDirection { sending, receiving }
enum TransferItemStatus { waiting, transferring, paused, completed, failed }

class TransferQueueNotifier extends Notifier<List<TransferItem>> {
  @override
  List<TransferItem> build() => [];

  /// Sorted for UI: Active → Pending/Paused → Failed → Completed
  List<TransferItem> get allSortedItems => [
    ...state.where((i) => i.status == TransferItemStatus.transferring),
    ...state.where((i) => i.status == TransferItemStatus.waiting || i.status == TransferItemStatus.paused),
    ...state.where((i) => i.status == TransferItemStatus.failed),
    ...state.where((i) => i.status == TransferItemStatus.completed),
  ];

  bool get hasActiveTransfers => state.any((i) => i.status == TransferItemStatus.transferring);

  int get sendingCount => state.where((i) =>
    i.direction == TransferDirection.sending &&
    (i.status == TransferItemStatus.transferring || i.status == TransferItemStatus.waiting)
  ).length;

  int get receivingCount => state.where((i) =>
    i.direction == TransferDirection.receiving &&
    (i.status == TransferItemStatus.transferring || i.status == TransferItemStatus.waiting)
  ).length;

  int get activeSendingCount => state.where((i) =>
    i.direction == TransferDirection.sending &&
    i.status == TransferItemStatus.transferring
  ).length;

  int get activeReceivingCount => state.where((i) =>
    i.direction == TransferDirection.receiving &&
    i.status == TransferItemStatus.transferring
  ).length;

  double get totalSpeed => state
    .where((i) => i.status == TransferItemStatus.transferring)
    .fold(0.0, (sum, i) => sum + i.speedBytesPerSec);

  void addItem(TransferItem item) {
    if (state.any((i) => i.id == item.id)) return;
    state = [...state, item];
  }

  void addItems(List<TransferItem> items) {
    final existing = state.map((i) => i.id).toSet();
    final newItems = items.where((i) => !existing.contains(i.id)).toList();
    if (newItems.isEmpty) return;
    state = [...state, ...newItems];
  }

  void updateProgress(String id, double progress, double speed, int bytesTransferred) {
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(
            progress: progress,
            speedBytesPerSec: speed,
            bytesTransferred: bytesTransferred,
            status: item.status == TransferItemStatus.waiting
                ? TransferItemStatus.transferring
                : item.status,
          )
        else
          item,
    ];
  }

  void updateItemStatus(String id, TransferItemStatus status, {File? localFile}) {
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(status: status, localFile: localFile ?? item.localFile)
        else
          item,
    ];
  }

  void completeItem(String id) {
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(progress: 1.0, bytesTransferred: item.fileSize, status: TransferItemStatus.completed)
        else
          item,
    ];
    final name = state.firstWhere((i) => i.id == id, orElse: () => state.first).fileName;
    debugPrint('[TRANSFER] Completed: $name');
  }

  void failItem(String id) {
    // IMPORTANT: preserve progress + bytesTransferred so resume can continue from this offset
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(status: TransferItemStatus.failed)
        else
          item,
    ];
    debugPrint('[TRANSFER] Failed/interrupted: $id');
  }

  void pauseItem(String id) {
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(isPaused: true, status: TransferItemStatus.paused)
        else
          item,
    ];
  }

  void resumeItem(String id) {
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(isPaused: false, status: TransferItemStatus.waiting)
        else
          item,
    ];
  }

  void cancelItem(String id) {
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(isCancelled: true, status: TransferItemStatus.failed)
        else
          item,
    ];
  }

  /// Resume from where we left off (bytesTransferred preserved)
  void queueForResume(String id) {
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(
            isCancelled: false,
            isPaused: false,
            status: TransferItemStatus.waiting,
          )
        else
          item,
    ];
  }

  /// Full retry from zero bytes
  void retryItem(String id) {
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(
            isCancelled: false,
            isPaused: false,
            progress: 0.0,
            speedBytesPerSec: 0.0,
            bytesTransferred: 0,
            status: TransferItemStatus.waiting,
          )
        else
          item,
    ];
  }

  void clear() => state = [];
}
