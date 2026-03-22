import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wifi_ftp/core/transfer/transfer_queue.dart';
import 'package:wifi_ftp/core/transfer/transfer_history.dart';

/// Handles actual file transfer over TCP.
/// Protocol on data port 45557:
///   1. Sender writes JSON header: {"type":"FILE_START","name":"foo.jpg","size":12345,"id":"uuid"}\n
///   2. Sender streams raw bytes (exactly 'size' bytes)
///   3. Repeat for next file
///   4. Socket closes when done
class FileTransferService {
  static final FileTransferService _instance = FileTransferService._internal();
  factory FileTransferService() => _instance;
  FileTransferService._internal();

  final int dataPort = 45557;
  ServerSocket? _dataServer;
  final TransferQueue _queue = TransferQueue();
  final TransferHistory _history = TransferHistory();
  bool _receiving = false;

  /// Global navigator key for completion popups — shared with AppConnection
  static GlobalKey<NavigatorState>? navigatorKey;

  /// Name of the connected device (set by AppConnection)
  String connectedDeviceName = 'Unknown';

  // ─── RECEIVER SIDE ───

  Future<void> startReceiver() async {
    if (_dataServer != null) {
      debugPrint('[FILE-RX] Already listening.');
      return;
    }
    try {
      _dataServer = await ServerSocket.bind(InternetAddress.anyIPv4, dataPort);
      _receiving = true;

      _dataServer!.listen((Socket client) {
        _handleIncomingDataSocket(client);
      });
    } catch (e) {
      debugPrint('[FILE-RX] Failed to bind server socket: $e');
    }
  }

  void _handleIncomingDataSocket(Socket socket) {
    final chunks = <Uint8List>[];
    int bufferLength = 0;

    String? currentFileId;
    String? currentFileName;
    int currentFileSize = 0;
    int currentFileIndex = 0;
    int currentFileTotal = 1;
    int bytesReceived = 0;
    RandomAccessFile? raf;
    Stopwatch? sw;
    String? currentFilePath;
    late StreamSubscription<Uint8List> sub;
    bool isProcessing = false;

    socket.setOption(SocketOption.tcpNoDelay, true);

    Future<void> processQueue() async {
      if (isProcessing) return;
      isProcessing = true;

      try {
        while (chunks.isNotEmpty) {
          // ─── STATE: RECEIVING FILE BYTES ───
          if (currentFileId != null && raf != null) {
            final data = chunks.first;
            final remainingForFile = currentFileSize - bytesReceived;

            if (remainingForFile <= 0) {
              debugPrint('[FILE-RX] Out of sync state detected. Aborting.');
              if (currentFileId != null) _queue.failItem(currentFileId!);
              socket.destroy();
              return;
            }

            if (data.length <= remainingForFile) {
              await raf!.writeFrom(data);
              bytesReceived += data.length;
              chunks.removeAt(0);
              bufferLength -= data.length;
            } else {
              // Chunk contains end of this file AND start of next header/file
              await raf!.writeFrom(data, 0, remainingForFile);
              bytesReceived += remainingForFile;

              final leftover = data.sublist(remainingForFile);
              chunks[0] = leftover;
              bufferLength -= remainingForFile;
            }

            // 1. ALWAYS handle backpressure independently of the UI
            // This prevents the stream from permanently deadlocking
            if (sub.isPaused && bufferLength < 1024 * 1024 * 4) {
              sub.resume();
            }

            // 2. Throttle UI updates so we don't choke the Android Choreographer
            if (bytesReceived % (1024 * 1024 * 2) < data.length ||
                bytesReceived >= currentFileSize) {
              final elapsed = (sw?.elapsedMilliseconds ?? 0) / 1000.0;
              final speed = elapsed > 0 ? bytesReceived / elapsed : 0.0;
              try {
                _queue.updateProgress(
                  currentFileId!,
                  bytesReceived / currentFileSize,
                  speed,
                );
              } catch (_) {}

              // Yield to UI Thread
              await Future.delayed(const Duration(milliseconds: 1));
            }

            // ─── HANDLE FILE COMPLETION ───
            if (bytesReceived >= currentFileSize) {
              final isLastFile = currentFileIndex + 1 >= currentFileTotal;

              VoidCallback? dismissLoading;
              if (isLastFile) {
                dismissLoading = _showLoadingPopup('Saving to device...');
              }

              // Do the heavy lifting (Disk write)
              await raf!.flush();
              await raf!.close();
              raf = null;

              // Send an ACK back to the Sender over the data socket
              try {
                socket.write('ACK\n');
                await socket.flush();
              } catch (e) {
                debugPrint('[FILE-RX] Failed to send ACK: $e');
              }

              _queue.completeItem(currentFileId!);
              debugPrint('[FILE-RX] Complete: $currentFileName');

              await _history.addRecord(
                TransferRecord(
                  fileName: currentFileName!,
                  fileSize: currentFileSize,
                  direction: 'received',
                  deviceName: connectedDeviceName,
                  timestamp: DateTime.now(),
                  filePath: currentFilePath,
                ),
              );

              // Dismiss the loading overlay
              dismissLoading?.call();

              // Show the final success popup
              if (isLastFile) {
                _showCompletionPopup(
                  currentFileTotal > 1
                      ? '$currentFileTotal files'
                      : currentFileName!,
                  'received',
                );
              }

              currentFileId = null;
              currentFileName = null;
              bytesReceived = 0;
              // Small yield before next file header parsing
              await Future.delayed(const Duration(milliseconds: 2));
            }
          }
          // ─── STATE: PARSING HEADER ───
          else {
            final builder = BytesBuilder(copy: false);
            // Copy list for safe iteration
            final snap = List<Uint8List>.from(chunks);
            for (var c in snap) {
              builder.add(c);
            }
            final flat = builder.takeBytes();
            final nl = flat.indexOf(10); // \n

            if (nl != -1) {
              final headerBytes = flat.sublist(0, nl);
              final remainingData = flat.sublist(nl + 1);

              String line;
              try {
                line = utf8.decode(headerBytes).trim();
              } catch (e) {
                debugPrint('[FILE-RX] Header Decode failed: $e. Aborting.');
                if (currentFileId != null) _queue.failItem(currentFileId!);
                socket.destroy();
                return;
              }

              chunks.clear();
              bufferLength = 0;
              if (remainingData.isNotEmpty) {
                chunks.add(remainingData);
                bufferLength = remainingData.length;
              }

              if (line.isNotEmpty) {
                try {
                  final json = jsonDecode(line) as Map<String, dynamic>;
                  if (json['type'] == 'FILE_START') {
                    currentFileId = json['id'];
                    currentFileName = json['name'];
                    currentFileSize = json['size'];
                    currentFileIndex = json['index'];
                    currentFileTotal = json['total'];
                    bytesReceived = 0;

                    final res = await _openReceiveFile(currentFileName!);
                    raf = res.$1;
                    currentFilePath = res.$2;

                    _queue.addItem(
                      TransferItem(
                        id: currentFileId!,
                        fileName: currentFileName!,
                        fileSize: currentFileSize,
                        direction: TransferDirection.receiving,
                        status: TransferItemStatus.transferring,
                        localFile: File(currentFilePath!),
                      ),
                    );
                    debugPrint('[FILE-RX] Started: $currentFileName');
                    sw = Stopwatch()..start();
                  }
                } catch (e) {
                  debugPrint('[FILE-RX] JSON Start error: $e');
                }
              }
            } else {
              break; // Wait for more data to find \n
            }
          }
        }
      } catch (e) {
        debugPrint('[FILE-RX] Loop Error: $e. Aborting.');
        if (currentFileId != null) _queue.failItem(currentFileId!);
        socket.destroy();
        return;
      } finally {
        isProcessing = false;
        if (bufferLength > 0) processQueue();
      }
    }

    sub = socket.listen(
      (data) {
        chunks.add(data);
        bufferLength += data.length;
        if (bufferLength > 1024 * 1024 * 12) sub.pause();
        processQueue();
      },
      onDone: () async {
        debugPrint('[FILE-RX] Socket closed. Draining...');
        // Wait for processing to finish
        int retry = 0;
        while ((bufferLength > 0 || isProcessing) && retry < 50) {
          if (!isProcessing) processQueue();
          await Future.delayed(const Duration(milliseconds: 50));
          retry++;
        }

        if (raf != null) {
          try {
            await raf!.flush();
            await raf!.close();
          } catch (_) {}
          raf = null;
        }

        if (currentFileId != null && bytesReceived < currentFileSize) {
          _queue.failItem(currentFileId!);
        }
        currentFileId = null;
      },
      onError: (e) async {
        debugPrint('[FILE-RX] Socket Error: $e');
        if (raf != null) {
          try {
            await raf!.close();
          } catch (_) {}
          raf = null;
        }
        if (currentFileId != null) _queue.failItem(currentFileId!);
        currentFileId = null;
      },
      cancelOnError: true,
    );
  }

  Future<(RandomAccessFile, String)> _openReceiveFile(String fileName) async {
    String basePath;
    if (Platform.isWindows) {
      final userDir =
          Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Public';
      basePath = '$userDir\\Downloads\\FastShare';
    } else {
      // Use the public Downloads folder so users can find the files easily in their File Manager
      basePath = '/storage/emulated/0/Download/FastShare';
    }

    final directory = Directory(basePath);
    if (!await directory.exists()) await directory.create(recursive: true);

    final filePath = '$basePath${Platform.pathSeparator}$fileName';
    final file = File(filePath);
    if (await file.exists()) await file.delete();
    await file.create();
    return (await file.open(mode: FileMode.write), filePath);
  }

  // ─── SENDER SIDE ───

  Future<void> sendFiles(String peerIp, List<TransferItem> items) async {
    Socket? dataSock;
    Completer<void>? ackCompleter;

    final validItems = items
        .where(
          (i) =>
              i.localFile != null && i.status != TransferItemStatus.completed,
        )
        .toList();
    debugPrint(
      '[FILE-TX] sendFiles started for ${validItems.length} items to $peerIp',
    );
    if (validItems.isEmpty) return;

    for (int i = 0; i < validItems.length; i++) {
      final item = validItems[i];
      if (item.isCancelled) continue;

      if (dataSock == null) {
        try {
          dataSock = await Socket.connect(peerIp, dataPort);
          dataSock.setOption(SocketOption.tcpNoDelay, true);

          // Listen to the socket for incoming ACKs from the Receiver
          dataSock.listen(
            (data) {
              final msg = utf8.decode(data).trim();
              if (msg.contains('ACK') &&
                  ackCompleter != null &&
                  !ackCompleter.isCompleted) {
                ackCompleter.complete();
              }
            },
            onError: (e) {
              if (ackCompleter != null && !ackCompleter.isCompleted) {
                ackCompleter.completeError(e);
              }
            },
            onDone: () {
              if (ackCompleter != null && !ackCompleter.isCompleted) {
                ackCompleter.completeError('Socket closed early');
              }
            },
          );
        } catch (e) {
          for (final i in validItems) {
            try {
              _queue.failItem(i.id);
            } catch (_) {}
          }
          return;
        }
      }

      try {
        final file = item.localFile!;
        final fileSize = await file.length();

        // Initialize the Completer BEFORE sending bytes
        ackCompleter = Completer<void>();

        // Send header
        final header = jsonEncode({
          'type': 'FILE_START',
          'id': item.id,
          'name': item.fileName,
          'size': fileSize,
          'index': i,
          'total': validItems.length,
        });
        dataSock.write('$header\n');
        await dataSock.flush();
        debugPrint('[FILE-TX] Sending: ${item.fileName} ($fileSize bytes)');

        // Stream file bytes
        final raf = await file.open(mode: FileMode.read);
        const chunkSize = 1048576 * 2; // 2MB chunks for maximum speed
        int bytesSent = 0;
        final sw = Stopwatch()..start();
        bool wasCancelled = false;

        while (bytesSent < fileSize) {
          if (item.isCancelled) {
            wasCancelled = true;
            break;
          }

          if (item.isPaused) {
            await Future.delayed(const Duration(milliseconds: 200));
            continue;
          }

          final toRead = (bytesSent + chunkSize > fileSize)
              ? fileSize - bytesSent
              : chunkSize;
          final chunk = await raf.read(toRead);
          dataSock.add(chunk);
          bytesSent += chunk.length;

          // Update UI every 2MB, but only flush the OS socket buffer every 16MB
          if (bytesSent % chunkSize == 0 || bytesSent >= fileSize) {
            final elapsed = sw.elapsedMilliseconds / 1000.0;
            final speed = elapsed > 0 ? bytesSent / elapsed : 0.0;
            try {
              _queue.updateProgress(item.id, bytesSent / fileSize, speed);
            } catch (_) {}

            if (bytesSent % (chunkSize * 8) == 0 || bytesSent >= fileSize) {
              await dataSock.flush();
            }
          }
        }

        final isLastFile = i == validItems.length - 1;
        VoidCallback? dismissLoading;

        if (isLastFile && !wasCancelled) {
          dismissLoading = _showLoadingPopup('Waiting for receiver to save...');
        }

        await dataSock.flush();
        await raf.close();

        if (wasCancelled) {
          dismissLoading?.call(); // Hide if cancelled
          try {
            await dataSock.close();
          } catch (_) {}
          dataSock = null;
          continue;
        }

        // Pause the Sender here until the Receiver fires the ACK!
        debugPrint('[FILE-TX] Waiting for Receiver ACK...');
        try {
          await ackCompleter.future;
          debugPrint('[FILE-TX] Received ACK!');
        } catch (e) {
          debugPrint('[FILE-TX] Failed to get ACK: $e');
        }

        _queue.completeItem(item.id);
        debugPrint(
          '[FILE-TX] Sent: ${item.fileName} (${sw.elapsedMilliseconds}ms)',
        );

        // Save to history
        await _history.addRecord(
          TransferRecord(
            fileName: item.fileName,
            fileSize: item.fileSize,
            direction: 'sent',
            deviceName: connectedDeviceName,
            timestamp: DateTime.now(),
            filePath: item.localFile?.path,
          ),
        );

        // Hide loading and show completion
        dismissLoading?.call();

        if (isLastFile) {
          _showCompletionPopup(
            validItems.length > 1
                ? '${validItems.length} files'
                : item.fileName,
            'sent',
          );
        }

        await Future.delayed(Duration.zero);
      } catch (e) {
        debugPrint('[FILE-TX] Error sending ${item.fileName}: $e');
        try {
          _queue.failItem(item.id);
        } catch (_) {}
        try {
          await dataSock?.close();
        } catch (_) {}
        dataSock = null; // Forces reconnect for the next file
      }
    }

    try {
      await dataSock?.close();
    } catch (_) {}
    debugPrint('[FILE-TX] All files sent, data socket closed');
  }

  // ─── Loading Popup ───

  VoidCallback? _showLoadingPopup(String message) {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) return null;

    bool isShowing = true;
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.green,
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => isShowing = false);

    // Returns a function that safely closes this specific dialog
    return () {
      if (isShowing && navigatorKey?.currentContext != null) {
        Navigator.pop(navigatorKey!.currentContext!);
      }
    };
  }

  // ─── Completion Popup ───

  void _showCompletionPopup(String fileName, String direction) {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) return;

    final isSent = direction == 'sent';
    final title = isSent ? 'File Sent ✓' : 'File Received ✓';
    final subtitle = isSent
        ? 'Sent to $connectedDeviceName'
        : 'Received from $connectedDeviceName';

    showDialog(
      context: ctx,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isSent ? Icons.check_circle : Icons.download_done,
              color: Colors.green,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.green, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fileName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              // Navigate to history
              Navigator.pushNamed(dialogCtx, '/history');
            },
            child: const Text(
              'VIEW HISTORY',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ─── Cleanup ───

  void stopReceiver() {
    _receiving = false;
    _dataServer?.close();
    _dataServer = null;
    debugPrint('[FILE-RX] Stopped.');
  }

  bool get isReceiving => _receiving;
}
