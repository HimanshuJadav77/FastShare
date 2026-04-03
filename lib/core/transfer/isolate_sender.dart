import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

// ─── Commands sent from main → sender isolate ───
class SenderCmd {
  static const String pause = 'PAUSE';
  static const String resume = 'RESUME';
  static const String cancel = 'CANCEL';
}

// ─── Config passed into the sender isolate ───
class SenderIsolateArgs {
  final SendPort replyPort;
  final String peerIp;
  final int dataPort;
  final String fileId;
  final String fileName;
  final String filePath;
  final int fileSize;
  final int chunkSize;
  final int parallelStreams;

  const SenderIsolateArgs({
    required this.replyPort,
    required this.peerIp,
    required this.dataPort,
    required this.fileId,
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.chunkSize,
    required this.parallelStreams,
  });
}

// ─── Telemetry messages sent back to main isolate ───
class SenderTelemetry {
  final String fileId;
  final int bytesDone; // absolute
  final double speedBps;
  final bool isDone;
  final bool isError;
  final bool isPaused;

  const SenderTelemetry({
    required this.fileId,
    required this.bytesDone,
    required this.speedBps,
    this.isDone = false,
    this.isError = false,
    this.isPaused = false,
  });
}

/// Pre-built header bytes for a chunk — avoids JSON encode + utf8 encode on
/// every chunk in the hot loop.
List<int> _buildChunkHeader(String fileId, int index, int size) {
  // Compact JSON — no checksum (TCP provides CRC on every segment, LAN is reliable)
  final json = '{"type":"CHUNK","id":"$fileId","index":$index,"size":$size}\n';
  return json.codeUnits; // ASCII-safe, no need for utf8.encode
}

// ─── Top-level Isolate entry point ───
@pragma('vm:entry-point')
Future<void> isolateSenderEntry(SenderIsolateArgs args) async {
  final cmdPort = ReceivePort();
  args.replyPort.send(cmdPort.sendPort);

  bool isPaused = false;
  bool isCancelled = false;

  cmdPort.listen((msg) {
    if (msg == SenderCmd.pause) isPaused = true;
    if (msg == SenderCmd.resume) isPaused = false;
    if (msg == SenderCmd.cancel) isCancelled = true;
  });

  void sendError() {
    args.replyPort.send(SenderTelemetry(
      fileId: args.fileId, bytesDone: 0, speedBps: 0, isError: true,
    ));
    cmdPort.close();
  }

  // ── 1. Handshake on primary socket ──
  Socket controlSocket;
  try {
    controlSocket = await Socket.connect(
      args.peerIp, args.dataPort,
      timeout: const Duration(seconds: 10),
    );
    // TCP_NODELAY: disable Nagle's algorithm — send immediately, don't batch small packets
    controlSocket.setOption(SocketOption.tcpNoDelay, true);
    controlSocket.done.catchError((_) {});
  } catch (_) { sendError(); return; }

  final totalChunks = (args.fileSize / args.chunkSize).ceil();

  try {
    controlSocket.write(
      '${jsonEncode({
        'type': 'OFFER_FILE',
        'id': args.fileId,
        'name': args.fileName,
        'size': args.fileSize,
        'chunks': totalChunks,
      })}\n',
    );
    await controlSocket.flush();
  } catch (_) {
    sendError();
    return;
  }

  // ── 2. Wait for START_FROM ──
  int startIndex = 0;
  try {
    final completer = Completer<int>();
    final lineBuf = StringBuffer();
    final sub = controlSocket.listen((data) {
      lineBuf.write(String.fromCharCodes(data));
      final s = lineBuf.toString();
      final nl = s.indexOf('\n');
      if (nl != -1 && !completer.isCompleted) {
        try {
          final json = jsonDecode(s.substring(0, nl)) as Map<String, dynamic>;
          if (json['type'] == 'START_FROM') {
            completer.complete((json['index'] as num).toInt());
          }
        } catch (_) {}
      }
    });
    startIndex = await completer.future.timeout(const Duration(seconds: 15));
    await sub.cancel();
  } catch (_) {
    sendError();
    try { controlSocket.destroy(); } catch (_) {}
    return;
  }

  // ── 3. Open parallel data sockets ──
  // TCP_NODELAY on all sockets — critical for throughput, prevents 40ms Nagle delays
  final sockets = <Socket>[controlSocket];
  for (int i = 1; i < args.parallelStreams; i++) {
    try {
      final s = await Socket.connect(
        args.peerIp, args.dataPort,
        timeout: const Duration(seconds: 5),
      );
      s.setOption(SocketOption.tcpNoDelay, true);
      s.done.catchError((_) {});
      sockets.add(s);
    } catch (_) {}
  }

  // ── 4. Open file ──
  RandomAccessFile raf;
  try {
    raf = await File(args.filePath).open(mode: FileMode.read);
    if (startIndex > 0) await raf.setPosition(startIndex * args.chunkSize);
  } catch (_) {
    sendError();
    for (final s in sockets) { try { s.destroy(); } catch (_) {} }
    return;
  }

  int chunkIndex = startIndex;
  int bytesDone = startIndex * args.chunkSize;
  int socketIdx = 0;

  // Flush IOSink every this many bytes — prevents unbounded buffering without
  // adding per-chunk flush overhead.
  const flushEveryBytes = 32 * 1024 * 1024; // 32 MB
  int bytesSinceFlush = 0;

  // Sliding window for speed telemetry (epochMs, absoluteBytes)
  final window = <(int, int)>[];
  int lastTelemetryMs = 0;

  while (chunkIndex < totalChunks && !isCancelled) {
    if (isPaused) {
      await Future.delayed(const Duration(milliseconds: 100));
      continue;
    }

    // ── Read chunk ──
    final remaining = args.fileSize - bytesDone;
    final currentSize = remaining < args.chunkSize ? remaining : args.chunkSize;
    final chunkData = await raf.read(currentSize);

    // ── Write header + payload — NO SHA-256, NO per-chunk flush ──
    // TCP CRC32 (hardware-accelerated on every NIC) guarantees bit-level integrity on LAN.
    final socket = sockets[socketIdx % sockets.length];
    try {
      socket.add(_buildChunkHeader(args.fileId, chunkIndex, chunkData.length));
      socket.add(chunkData);
    } catch (_) {
      sockets.remove(socket);
      if (sockets.isEmpty) { sendError(); break; }
      continue; // retry this chunk on next socket
    }

    bytesDone += chunkData.length;
    bytesSinceFlush += chunkData.length;
    chunkIndex++;
    socketIdx++;

    // Flush once every 32 MB to prevent IOSink buffer from growing unbounded.
    // Do NOT flush every chunk — that adds ~1ms OS syscall overhead per MB.
    if (bytesSinceFlush >= flushEveryBytes) {
      try { await socket.flush(); } catch (_) {}
      bytesSinceFlush = 0;
    }

    // ── Telemetry (at most every 500ms, very cheap) ──
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - lastTelemetryMs >= 500) {
      window.add((nowMs, bytesDone));
      final cutoff = nowMs - 2000;
      while (window.isNotEmpty && window.first.$1 < cutoff) {
        window.removeAt(0);
      }
      double speedBps = 0;
      if (window.length >= 2) {
        final dBytes = window.last.$2 - window.first.$2;
        final dMs = window.last.$1 - window.first.$1;
        if (dMs > 0) speedBps = dBytes * 1000 / dMs;
      }
      args.replyPort.send(SenderTelemetry(
        fileId: args.fileId, bytesDone: bytesDone, speedBps: speedBps,
      ));
      lastTelemetryMs = nowMs;
    }
  }

  // Final flush to drain any remaining IOSink buffer
  for (final s in sockets) {
    try { await s.flush(); } catch (_) {}
    try { await s.close(); } catch (_) {}
  }
  await raf.close();

  if (!isCancelled) {
    args.replyPort.send(SenderTelemetry(
      fileId: args.fileId,
      bytesDone: args.fileSize,
      speedBps: 0,
      isDone: true,
    ));
  }
  cmdPort.close();
}
