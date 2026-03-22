import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
    fileName: json['fileName'] as String,
    fileSize: json['fileSize'] as int,
    direction: json['direction'] as String,
    deviceName: json['deviceName'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
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
class TransferHistory extends ChangeNotifier {
  static final TransferHistory _instance = TransferHistory._internal();
  factory TransferHistory() => _instance;
  TransferHistory._internal();

  final List<TransferRecord> _records = [];
  List<TransferRecord> get records => List.unmodifiable(_records);
  bool _loaded = false;

  List<TransferRecord> get sentRecords =>
      _records.where((r) => r.direction == 'sent').toList();
  List<TransferRecord> get receivedRecords =>
      _records.where((r) => r.direction == 'received').toList();

  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = await _getHistoryFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List;
        _records.clear();
        _records.addAll(
          list.map((e) => TransferRecord.fromJson(e as Map<String, dynamic>)),
        );
        _records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
      _loaded = true;
      debugPrint('[HISTORY] Loaded ${_records.length} records');
    } catch (e) {
      debugPrint('[HISTORY] Load error: $e');
      _loaded = true;
    }
  }

  Future<void> addRecord(TransferRecord record) async {
    await load(); // Ensure we have the existing records before adding/saving
    _records.insert(0, record);
    debugPrint('[HISTORY] Added: ${record.direction} ${record.fileName}');
    notifyListeners();
    await _save();
  }

  // 👇 NEW DELETE METHOD 👇
  Future<void> deleteRecord(TransferRecord recordToRemove) async {
    await load();

    // Remove by matching filename and exact timestamp
    _records.removeWhere(
      (r) =>
          r.fileName == recordToRemove.fileName &&
          r.timestamp == recordToRemove.timestamp,
    );

    debugPrint('[HISTORY] Deleted: ${recordToRemove.fileName}');
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    await load();
    _records.clear();
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _getHistoryFile();
      final json = jsonEncode(_records.map((r) => r.toJson()).toList());
      await file.writeAsString(json);
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
