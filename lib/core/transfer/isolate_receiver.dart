import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

// ─── Commands sent to receiver isolate ───
class ReceiverCmd {
  static const String stop = 'STOP';
}

class ReceiverUpdateConfigMsg {
  final String saveDirectory;
  final bool autoResumeEnabled;
  const ReceiverUpdateConfigMsg({
    required this.saveDirectory,
    required this.autoResumeEnabled,
  });
}

// ─── Config passed into receiver isolate ───
class ReceiverIsolateArgs {
  final SendPort replyPort;
  final int dataPort;
  final String saveDirectory;
  final bool autoResumeEnabled;
  final int chunkSize;

  const ReceiverIsolateArgs({
    required this.replyPort,
    required this.dataPort,
    required this.saveDirectory,
    required this.autoResumeEnabled,
    required this.chunkSize,
  });
}

// ─── Events returned from receiver isolate ───
class ReceiverOfferMsg {
  final String id;
  final String name;
  final int size;
  const ReceiverOfferMsg(this.id, this.name, this.size);
}

class ReceiverTelemetryMsg {
  final String id;
  final int bytesDone;
  final double speedBps;
  final bool isDone;
  final bool isError;
  const ReceiverTelemetryMsg({
    required this.id,
    required this.bytesDone,
    this.speedBps = 0,
    this.isDone = false,
    this.isError = false,
  });
}

@pragma('vm:entry-point')
Future<void> isolateReceiverEntry(ReceiverIsolateArgs args) async {
  final cmdPort = ReceivePort();
  args.replyPort.send(cmdPort.sendPort);

  String saveDir = args.saveDirectory;
  bool autoResume = args.autoResumeEnabled;

  ServerSocket? server;
  try {
    server = await ServerSocket.bind(InternetAddress.anyIPv4, args.dataPort);
  } catch (e) {
    args.replyPort.send('ERROR: $e');
    return;
  }

  final openFiles = <String, RandomAccessFile>{};
  final writePromises = <String, Future<void>>{};
  final fileSizes = <String, int>{};
  
  // For telemetry
  final telemetryBytes = <String, int>{};
  final telemetryWindow = <String, List<(int, int)>>{};
  final telemetryLastMs = <String, int>{};

  void completeFile(String id) async {
    final raf = openFiles.remove(id);
    if (raf != null) {
      await (writePromises[id] ?? Future.value());
      try { await raf.flush(); } catch (_) {}
      try { await raf.close(); } catch (_) {}
      writePromises.remove(id);
      fileSizes.remove(id);
      telemetryWindow.remove(id);
      telemetryLastMs.remove(id);
      
      args.replyPort.send(ReceiverTelemetryMsg(
        id: id, bytesDone: telemetryBytes.remove(id) ?? 0, isDone: true,
      ));
    }
  }

  cmdPort.listen((msg) {
    if (msg == ReceiverCmd.stop) {
      server?.close();
      for (final f in openFiles.values) {
        try { f.closeSync(); } catch (_) {}
      }
      cmdPort.close();
    } else if (msg is ReceiverUpdateConfigMsg) {
      saveDir = msg.saveDirectory;
      autoResume = msg.autoResumeEnabled;
    }
  });

  server.listen((Socket socket) {
    // ── TCP Tuning ──
    // Highly critical for 45+ MB/s transfers on LAN to bypass Nagle's algorithm issues 
    socket.setOption(SocketOption.tcpNoDelay, true);
    socket.done.catchError((_) {});

    final buffer = <Uint8List>[];
    int bufLen = 0;
    
    String? activeFileId;
    int chunkExpected = 0;
    int chunkWriteOffset = 0;
    final payloadBuf = BytesBuilder(copy: false);
    int payloadReceived = 0;

    StreamSubscription<Uint8List>? sub;
    bool inProcess = false;

    Future<void> process() async {
      if (inProcess) return;
      inProcess = true;
      try {
        while (buffer.isNotEmpty) {
          if (activeFileId != null && chunkExpected > 0) {
            // ── Payload Assembly ──
            final data = buffer.first;
            final remaining = chunkExpected - payloadReceived;
            final take = data.length <= remaining ? data.length : remaining;

            payloadBuf.add(data.sublist(0, take));
            payloadReceived += take;

            if (data.length <= remaining) {
              buffer.removeAt(0);
              bufLen -= data.length;
            } else {
              buffer[0] = data.sublist(take);
              bufLen -= take;
            }

            if (payloadReceived >= chunkExpected) {
              // ── Chunk complete ──
              final payload = payloadBuf.takeBytes();
              payloadBuf.clear();

              final thisId = activeFileId!;
              final raf = openFiles[thisId];
              if (raf != null) {
                final writeOffset = chunkWriteOffset;
                
                // Chain disk writes iteratively to avoid overlapping seeks on same file
                writePromises[thisId] = (writePromises[thisId] ?? Future.value())
                    .then((_) async {
                  await raf.setPosition(writeOffset);
                  await raf.writeFrom(payload);
                }).catchError((e) {
                  // Ignore write errors to prevent collapsing the entire queue
                });

                telemetryBytes[thisId] = (telemetryBytes[thisId] ?? 0) + payload.length;
                final bytesDone = telemetryBytes[thisId]!;
                final totalSize = fileSizes[thisId] ?? 0;
                
                if (bytesDone >= totalSize) {
                  completeFile(thisId);
                } else {
                  // Push UI Telemetry (throttle to 500ms so main thread isn't choked by IPC)
                  final nowMs = DateTime.now().millisecondsSinceEpoch;
                  final lastMs = telemetryLastMs[thisId] ?? 0;
                  
                  final window = telemetryWindow.putIfAbsent(thisId, () => []);
                  window.add((nowMs, bytesDone));
                  final cutoff = nowMs - 2000;
                  while (window.isNotEmpty && window.first.$1 < cutoff) {
                    window.removeAt(0);
                  }

                  if (nowMs - lastMs >= 500) {
                    double speedBps = 0;
                    if (window.length >= 2) {
                       final dBytes = window.last.$2 - window.first.$2;
                       final dMs = window.last.$1 - window.first.$1;
                       if (dMs > 0) speedBps = dBytes * 1000 / dMs;
                    }
                    args.replyPort.send(ReceiverTelemetryMsg(
                      id: thisId, bytesDone: bytesDone, speedBps: speedBps,
                    ));
                    telemetryLastMs[thisId] = nowMs;
                  }
                }
              }

              activeFileId = null;
              chunkExpected = 0;
              payloadReceived = 0;
              
              // Un-throttle recv window if memory releases pressure
              if (sub != null && sub.isPaused && bufLen < 16 * 1024 * 1024) {
                sub.resume();
              }
            }
          } else {
            // ── Fast Header Scan ──
            int nl = -1;
            int acc = 0;
            for (final chunk in buffer) {
              final idx = chunk.indexOf(10); // \n
              if (idx != -1) { nl = acc + idx; break; }
              acc += chunk.length;
            }
            if (nl == -1) break;

            final hBytes = Uint8List(nl);
            int off = 0;
            for (final chunk in buffer) {
              final take = (nl - off).clamp(0, chunk.length);
              hBytes.setRange(off, off + take, chunk);
              off += take;
              if (off >= nl) break;
            }

            int toConsume = nl + 1;
            while (toConsume > 0 && buffer.isNotEmpty) {
              if (buffer.first.length <= toConsume) {
                toConsume -= buffer.first.length;
                bufLen -= buffer.first.length;
                buffer.removeAt(0);
              } else {
                buffer[0] = buffer.first.sublist(toConsume);
                bufLen -= toConsume;
                toConsume = 0;
              }
            }

            try {
              final h = jsonDecode(String.fromCharCodes(hBytes)) as Map<String, dynamic>;
              final type = h['type'] as String?;
              
              if (type == 'OFFER_FILE') {
                final id = h['id'] as String;
                final name = h['name'] as String;
                final size = (h['size'] as num).toInt();

                final dir = Directory(saveDir);
                if (!dir.existsSync()) dir.createSync(recursive: true);

                final file = File('${dir.path}/$name');
                final exists = file.existsSync();
                int startChunk = 0;
                
                if (exists && autoResume) {
                   startChunk = file.lengthSync() ~/ args.chunkSize;
                   if (startChunk * args.chunkSize > size) {
                     startChunk = 0;
                     file.deleteSync();
                   }
                } else if (exists) {
                   file.deleteSync();
                }

                if (!openFiles.containsKey(id)) {
                  openFiles[id] = file.openSync(mode: (exists && autoResume) ? FileMode.append : FileMode.write);
                  fileSizes[id] = size;
                  telemetryBytes[id] = startChunk * args.chunkSize;
                  args.replyPort.send(ReceiverOfferMsg(id, name, size));
                }

                socket.write('{"type":"START_FROM","index":$startChunk}\n');
                await socket.flush();

              } else if (type == 'CHUNK') {
                activeFileId = h['id'] as String?;
                chunkExpected = (h['size'] as num).toInt();
                final index = (h['index'] as num?)?.toInt() ?? 0;
                chunkWriteOffset = index * args.chunkSize;
                payloadReceived = 0;
                payloadBuf.clear();
              }
            } catch (e) {
              // bad header — skip
            }
          }
        }
      } finally {
        inProcess = false;
      }
    };

    // Auto-throttle read window based on RAM
    sub = socket.listen(
      (data) {
        buffer.add(data);
        bufLen += data.length;
        if (bufLen > 64 * 1024 * 1024) sub?.pause();  // if 64MB of backlogged chunks haven't written to disk, wait!
        process();
      },
      onDone: () {}
    );
  });
}
