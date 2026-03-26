import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wifi_ftp/core/transfer/transfer_queue.dart';
import 'package:wifi_ftp/core/transfer/transfer_history.dart';

/// Handles high-performance file transfer by using parallel TCP streams.
/// Protocol on data port 45557:
///   1. Header as JSON line: {"type":"CHUNK","id":"uuid","name":"file.ext","offset":0,"size":4096000}\n
///   2. Payload: Exactly "size" bytes of raw binary.
///   3. Streams: Up to 4 parallel sockets can contribute chunks to the same file.
class FileTransferService {
  static final FileTransferService _instance = FileTransferService._internal();
  factory FileTransferService() => _instance;
  FileTransferService._internal();

  final int dataPort = 45557;
  final int parallelStreams = 6;
  final int chunkSize = 1024 * 1024 * 6; // 6MB Chunks for balanced speed

  ServerSocket? _dataServer;
  final TransferQueue _queue = TransferQueue();
  final TransferHistory _history = TransferHistory();
  bool _receiving = false;

  /// Custom download path from settings
  String? customDownloadPath;
  
  /// Whether to automatically resume partial transfers
  bool autoResumeEnabled = true;

  // Track active files on receiver to allow parallel writes
  final Map<String, RandomAccessFile> _activeReceivingFiles = {};
  final Map<String, int> _activeReceivedBytes = {};
  final Map<String, int> _sessionStartBytes = {};
  final Map<String, Stopwatch> _activeStopwatches = {};
  final Map<String, String> _activeFileNames = {};
  final Map<String, Future<void>> _writeLocks = {};
  final Map<String, Future<void>> _initLocks = {};

  /// Global navigator key for completion popups — shared with AppConnection
  static GlobalKey<NavigatorState>? navigatorKey;

  /// Name of the connected device (set by AppConnection)
  String connectedDeviceName = 'Unknown';

  // ─── RECEIVER SIDE ───

  Future<void> startReceiver() async {
    if (_dataServer != null) return;
    try {
      _dataServer = await ServerSocket.bind(InternetAddress.anyIPv4, dataPort);
      _receiving = true;
      _dataServer!.listen(_handleIncomingDataSocket);
    } catch (e) {
      debugPrint('[FILE-RX] Bind error: $e');
    }
  }

  void _handleIncomingDataSocket(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    final chunks = <Uint8List>[];
    int bufferLength = 0;

    String? currentFileId;
    int currentChunkSize = 0;
    int currentOffset = 0;
    int currentChunkReceived = 0;

    StreamSubscription<Uint8List>? sub;
    bool isProcessing = false;

    Future<void> processQueue() async {
      if (isProcessing) return;
      isProcessing = true;
      try {
        while (chunks.isNotEmpty) {
          if (currentFileId != null && currentChunkSize > 0) {
            // RECEIVING PAYLOAD
            final data = chunks.first;
            final remaining = currentChunkSize - currentChunkReceived;
            final toWrite = data.length <= remaining ? data.length : remaining;

            final raf = _activeReceivingFiles[currentFileId];
            if (raf != null) {
              final fileId = currentFileId!;
              final writeOffset = currentOffset + currentChunkReceived;

              // Serialize writes to this file to avoid "async operation pending"
              _writeLocks[fileId] = (_writeLocks[fileId] ?? Future.value())
                  .then((_) async {
                    await raf.setPosition(writeOffset);
                    // Zero-copy write using range
                    await raf.writeFrom(data, 0, toWrite);
                  });

              // IMPORTANT: Don't await here! Allow the network to keep reading into the
              // processQueue buffer (limited to 16MB by sub?.pause()).
              // This decouples Wi-Fi speed from Disk speed.
            }

            currentChunkReceived += toWrite;
            _activeReceivedBytes[currentFileId!] =
                (_activeReceivedBytes[currentFileId] ?? 0) + toWrite;

            if (data.length <= remaining) {
              chunks.removeAt(0);
              bufferLength -= data.length;
            } else {
              chunks[0] = data.sublist(toWrite);
              bufferLength -= toWrite;
            }

            // Progress: Use sliding window-like logic or at least total average
            final totalReceived = _activeReceivedBytes[currentFileId!] ?? 0;
            final sw = _activeStopwatches[currentFileId!];

            // Update UI every 12MB or completion
            if (totalReceived % (12 * 1024 * 1024) < toWrite ||
                currentChunkReceived >= currentChunkSize) {
              final elapsed = (sw?.elapsedMilliseconds ?? 0) / 1000.0;
              // For a more 'instant' feel, we could track the last 2 seconds,
              // but let's stick to total average for now to ensure consistency
              // Calculate speed based on the bytes received IN THIS SESSION
              final bytesInSession = totalReceived - (_sessionStartBytes[currentFileId] ?? 0);
              final speed = elapsed > 0 ? bytesInSession / elapsed : 0.0;
              
              // We'll trust the queue items list for total size
              final item = _queue.items.firstWhere(
                (i) => i.id == currentFileId,
                orElse: () => TransferItem(
                  id: 'dummy',
                  fileName: '',
                  fileSize: 1,
                  direction: TransferDirection.receiving,
                  status: TransferItemStatus.transferring,
                  localFile: File(''),
                ),
              );
              if (item.id != 'dummy') {
                _queue.updateProgress(
                  currentFileId!,
                  totalReceived / item.fileSize,
                  speed,
                );
              }
            }

            final String lastFileId = currentFileId!;
            if (currentChunkReceived >= currentChunkSize) {
              currentFileId = null;
              currentChunkSize = 0;
            }

            // ─── FILE COMPLETE CHECK ───
            final item = _queue.items.firstWhere(
              (i) => i.id == lastFileId,
              orElse: () => TransferItem(
                id: 'dummy',
                fileName: '',
                fileSize: 1,
                direction: TransferDirection.receiving,
                status: TransferItemStatus.transferring,
                localFile: File(''),
              ),
            );
            if (item.id != 'dummy' &&
                totalReceived >= item.fileSize &&
                _activeReceivingFiles.containsKey(item.id)) {
              // Wait for ALL pending writes in the chain to finish before closing
              await (_writeLocks[item.id] ?? Future.value());

              final raf = _activeReceivingFiles.remove(item.id);
              if (raf != null) {
                await raf.flush();
                await raf.close();
                final name = _activeFileNames.remove(item.id) ?? 'File';
                _activeReceivedBytes.remove(item.id);
                _activeStopwatches.remove(item.id);
                _writeLocks.remove(item.id);
                _queue.completeItem(item.id);

                await _history.addRecord(
                  TransferRecord(
                    fileName: name,
                    fileSize: item.fileSize,
                    direction: 'received',
                    deviceName: connectedDeviceName,
                    timestamp: DateTime.now(),
                  ),
                );
              }
            }
          } else {
            // PARSING HEADER
            // Efficiently find newline without expanding all chunks
            int nl = -1;
            int accumulated = 0;
            for (final chunk in chunks) {
              final idx = chunk.indexOf(10);
              if (idx != -1) {
                nl = accumulated + idx;
                break;
              }
              accumulated += chunk.length;
            }
            if (nl == -1) break;

            final headerBytes = Uint8List(nl);
            int currentCopyOffset = 0;
            for (final chunk in chunks) {
              final bytesToCopy = (nl - currentCopyOffset).clamp(
                0,
                chunk.length,
              );
              headerBytes.setRange(
                currentCopyOffset,
                currentCopyOffset + bytesToCopy,
                chunk,
              );
              currentCopyOffset += bytesToCopy;
              if (currentCopyOffset >= nl) break;
            }
            final headerStr = utf8.decode(headerBytes);

            // Consume header from chunks
            int toConsume = nl + 1;
            while (toConsume > 0 && chunks.isNotEmpty) {
              if (chunks.first.length <= toConsume) {
                toConsume -= chunks.first.length;
                bufferLength -= chunks.first.length;
                chunks.removeAt(0);
              } else {
                chunks[0] = chunks.first.sublist(toConsume);
                bufferLength -= toConsume;
                toConsume = 0;
              }
            }

            try {
              final header = jsonDecode(headerStr);
              if (header['type'] == 'CHUNK') {
                currentFileId = header['id'];
                currentChunkSize = header['size'];
                currentOffset = header['offset'];
                currentChunkReceived = 0;

                if (!_activeReceivingFiles.containsKey(currentFileId)) {
                  final String id = currentFileId!;
                  _initLocks[id] = (_initLocks[id] ?? Future.value()).then((_) async {
                    // Re-check after gaining the lock
                    if (!_activeReceivingFiles.containsKey(id)) {
                      Directory? downloadDir;
                      if (customDownloadPath != null && customDownloadPath!.isNotEmpty) {
                        downloadDir = Directory(customDownloadPath!);
                      } else {
                        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
                          downloadDir = await getDownloadsDirectory();
                        }
                        downloadDir ??= await getApplicationDocumentsDirectory();
                      }
                      
                      final fastShareDir = customDownloadPath != null ? downloadDir : Directory('${downloadDir.path}/FastShare');
                      if (!await fastShareDir.exists()) {
                        await fastShareDir.create(recursive: true);
                      }

                      final path = '${fastShareDir.path}/${header['name']}';
                      final file = File(path);
                      
                      // RESUME SUPPORT: Strictly follow the Sender's offset IF enabled
                      final int senderOffset = header['offset'] ?? 0;
                      final bool exists = await file.exists();
                      
                      if (senderOffset == 0 || !autoResumeEnabled) {
                        // NEW TRANSFER or Resume Disabled: Always start fresh!
                        if (exists) await file.delete();
                        _activeReceivingFiles[id] = await file.open(mode: FileMode.write);
                        _activeReceivedBytes[id] = 0;
                        _sessionStartBytes[id] = 0;
                      } else {
                        // RESUME: Append to what we already have
                        _activeReceivingFiles[id] = await file.open(
                          mode: exists ? FileMode.append : FileMode.write,
                        );
                        final currentOnDisk = exists ? await file.length() : 0;
                        _activeReceivedBytes[id] = currentOnDisk;
                        _sessionStartBytes[id] = currentOnDisk;
                      }

                      _activeStopwatches[id] = Stopwatch()..start();
                      _activeFileNames[id] = header['name'];

                      // ─── ADD TO UI QUEUE ───
                      final existing = _queue.items.any((i) => i.id == id);
                      if (!existing) {
                        _queue.addItem(
                          TransferItem(
                            id: id,
                            fileName: header['name'],
                            fileSize: header['total'] ?? 0,
                            direction: TransferDirection.receiving,
                            status: TransferItemStatus.transferring,
                            localFile: file,
                          ),
                        );
                      }
                    }
                  });
                  // Essential: Wait for initialization to finish before this socket
                  // starts processing its payload, otherwise lines 80-96 will skip raf.
                  await _initLocks[id];
                }
              } else if (header['type'] == 'FILE_END') {
                // Now handled by size-check for parallel safety
              }
            } catch (e) {
              debugPrint('[FILE-RX] Parse error: $e');
            }
            if (sub != null && sub.isPaused && bufferLength < 1024 * 1024 * 8) {
              sub.resume();
            }
          }
        }
      } finally {
        isProcessing = false;
      }
    }

    sub = socket.listen((data) {
      chunks.add(data);
      bufferLength += data.length;
      if (bufferLength > 1024 * 1024 * 16) sub?.pause();
      processQueue();
    });
  }

  // ─── SENDER SIDE ───

  Future<void> sendFiles(String peerIp, List<TransferItem> items) async {
    final validItems = items
        .where((i) => i.status == TransferItemStatus.waiting)
        .toList();
    if (validItems.isEmpty) return;

    // Open parallel sockets
    final List<Socket> sockets = [];
    try {
      for (int i = 0; i < parallelStreams; i++) {
        final s = await Socket.connect(peerIp, dataPort);
        s.setOption(SocketOption.tcpNoDelay, true);
        sockets.add(s);
      }
    } catch (e) {
      debugPrint('[FILE-TX] Connection failed: $e');
      return;
    }

    for (final item in validItems) {
      final file = item.localFile!;
      final fileSize = await file.length();

      int bytesSent = (item.progress * fileSize).toInt();
      _sessionStartBytes[item.id] = bytesSent;
      final raf = await file.open(mode: FileMode.read);
      if (bytesSent > 0) await raf.setPosition(bytesSent);
      final sw = Stopwatch()..start();

      // Use parallel streams to send chunks
      int streamIndex = 0;
      while (bytesSent < fileSize) {
        // ALWAYS fetch the latest status from the queue to avoid stale references
        final latest = _queue.items.firstWhere((i) => i.id == item.id, orElse: () => item);
        if (latest.isCancelled) break;

        // ─── PAUSE LOCK ───
        while (latest.isPaused && !latest.isCancelled) {
          await Future.delayed(const Duration(milliseconds: 500));
          // Refresh status inside the loop
          final inside = _queue.items.firstWhere((i) => i.id == item.id, orElse: () => item);
          if (inside.isCancelled || !inside.isPaused) break;
        }
        if (latest.isCancelled) break;

        final currentOffset = bytesSent;
        final currentSize = (bytesSent + chunkSize > fileSize)
            ? fileSize - bytesSent
            : chunkSize;
        bytesSent += currentSize;

        final chunk = await raf.read(currentSize);
        final socket = sockets[streamIndex % sockets.length];
        streamIndex++;

        final header = jsonEncode({
          'type': 'CHUNK',
          'id': item.id,
          'name': item.fileName,
          'offset': currentOffset,
          'size': currentSize,
          'total': fileSize,
        });

        socket.write('$header\n');
        socket.add(chunk);

        // Flush logic restored for 6x6 stability
        // Flush logic restored for 6x6 stability
        if (streamIndex % parallelStreams == 0) {
          final elapsed = sw.elapsedMilliseconds / 1000.0;
          final progress = bytesSent / fileSize;
          
          // Speed: partial bytes sent / elapsed seconds
          final speed = (elapsed > 0) ? (bytesSent - (_sessionStartBytes[item.id] ?? 0)) / elapsed : 0.0;
          
          _queue.updateProgress(item.id, progress, speed);
          
          await socket.flush();
          await Future.delayed(Duration.zero);
        }
      }

      // Signal file end on all sockets (broadcasting completion)
      final endHeader = jsonEncode({'type': 'FILE_END', 'id': item.id});
      for (final s in sockets) {
        s.write('$endHeader\n');
        await s.flush();
      }

      await raf.close();
      _queue.completeItem(item.id);

      await _history.addRecord(
        TransferRecord(
          fileName: item.fileName,
          fileSize: fileSize,
          direction: 'sent',
          deviceName: connectedDeviceName,
          timestamp: DateTime.now(),
        ),
      );
    }

    for (final s in sockets) await s.close();
  }

  void stopReceiver() {
    _receiving = false;
    _dataServer?.close();
    _dataServer = null;
  }

  bool get isReceiving => _receiving;
}
