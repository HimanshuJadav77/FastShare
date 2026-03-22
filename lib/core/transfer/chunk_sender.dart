import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:wifi_ftp/core/data/models/chunk_model.dart';
import 'package:wifi_ftp/core/networking/socket_manager.dart';

class ChunkSender {
  final SocketManager _socketManager;
  final int chunkSize = 4194304; // 4MB Chunk Default

  ChunkSender(this._socketManager);

  Future<void> sendFile(String deviceId, File file) async {
    final sockets = _socketManager.getSocketsForDevice(deviceId);
    if (sockets.isEmpty) {
      throw Exception("No active sockets available for transfer.");
    }

    final length = await file.length();
    final totalChunks = (length / chunkSize).ceil();
    final fileId = file.path
        .split(Platform.pathSeparator)
        .last; // Simplified ID

    final raf = await file.open(mode: FileMode.read);
    int activeSocketIndex = 0;

    for (int i = 0; i < totalChunks; i++) {
      final offset = i * chunkSize;
      await raf.setPosition(offset);

      final bytesToRead = (offset + chunkSize > length)
          ? length - offset
          : chunkSize;
      final data = await raf.read(bytesToRead);
      final checksum = sha256.convert(data).toString();

      final chunk = ChunkModel(
        fileId: fileId,
        chunkIndex: i,
        totalChunks: totalChunks,
        chunkSize: bytesToRead,
        checksum: checksum,
      );

      final headerJsonBytes = utf8.encode('${jsonEncode(chunk.toJson())}\n');

      // Dispatch payload onto round-robin available sockets
      final socket = sockets[activeSocketIndex % sockets.length];
      socket.add(headerJsonBytes);
      socket.add(data);

      activeSocketIndex++;

      // Throttle deeply rapid buffers to avoid overwhelming standard network streams
      await Future.delayed(const Duration(milliseconds: 2));
    }

    await raf.close();
  }
}
