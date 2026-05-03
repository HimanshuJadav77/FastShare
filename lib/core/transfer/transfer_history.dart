import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A single completed transfer record
class TransferRecord {
  final String fileName;
  final int fileSize;
  final String direction; // 'sent' or 'received'
  final String deviceName;
  final DateTime timestamp;
  final String? filePath;

  TransferRecord({
    required this.fileName,
    required this.fileSize,
    required this.direction,
    required this.deviceName,
    required this.timestamp,
    this.filePath,
  });

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'fileSize': fileSize,
    'direction': direction,
    'deviceName': deviceName,
    'timestamp': timestamp.toIso8601String(),
    'filePath': filePath,
  };

  factory TransferRecord.fromJson(Map<String, dynamic> json) => TransferRecord(
    fileName: json['fileName'] as String? ?? 'Unknown File',
    fileSize: json['fileSize'] as int? ?? 0,
    direction: json['direction'] as String? ?? 'unknown',
    deviceName: json['deviceName'] as String? ?? 'Unknown Device',
    timestamp: json['timestamp'] != null 
        ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
        : DateTime.now(),
    filePath: json['filePath'] as String?,
  );

  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get timeFormatted {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }
}


/// Persistent transfer history — saved to JSON file
class TransferHistoryNotifier extends Notifier<List<TransferRecord>> {
  @override
  List<TransferRecord> build() {
    return [];
  }
  
  bool _loaded = false;

  List<TransferRecord> get sentRecords =>
      state.where((r) => r.direction == 'sent').toList();
  List<TransferRecord> get receivedRecords =>
      state.where((r) => r.direction == 'received').toList();

  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = await _getHistoryFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List;
        final List<TransferRecord> loaded = [];
        for (final e in list) {
          if (e is Map<String, dynamic>) {
            try {
              loaded.add(TransferRecord.fromJson(e));
            } catch (err) {
              debugPrint('[HISTORY] Skip invalid record: $err');
            }
          }
        }
        loaded.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        state = loaded;
      }
      _loaded = true;
      debugPrint('[HISTORY] Loaded ${state.length} records');
    } catch (e) {
      debugPrint('[HISTORY] Load error: $e');
      _loaded = true;
    }
  }

  Future<void> addRecord(TransferRecord record) async {
    await load(); // Ensure we have the existing records before adding/saving
    final newState = [record, ...state];
    debugPrint('[HISTORY] Added: ${record.direction} ${record.fileName}');
    state = newState;
    await _save();
  }

  // 👇 NEW DELETE METHOD 👇
  Future<void> deleteRecord(TransferRecord recordToRemove) async {
    await load();

    final newState = state.where(
      (r) =>
          !(r.fileName == recordToRemove.fileName &&
            r.timestamp == recordToRemove.timestamp),
    ).toList();

    debugPrint('[HISTORY] Deleted: ${recordToRemove.fileName}');
    state = newState;
    await _save();
  }

  Future<void> clear() async {
    await load();
    state = [];
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _getHistoryFile();
      final jsonStr = jsonEncode(state.map((r) => r.toJson()).toList());
      await file.writeAsString(jsonStr);
    } catch (e) {
      debugPrint('[HISTORY] Save error: $e');
    }
  }

  Future<File> _getHistoryFile() async {
    String basePath;
    if (Platform.isWindows) {
      final userDir =
          Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Public';
      basePath = '$userDir\\.fastshare';
    } else {
      final dir = await getApplicationDocumentsDirectory();
      basePath = '${dir.path}/.fastshare';
    }
    final directory = Directory(basePath);
    if (!await directory.exists()) await directory.create(recursive: true);
    return File('$basePath${Platform.pathSeparator}transfer_history.json');
  }
}
