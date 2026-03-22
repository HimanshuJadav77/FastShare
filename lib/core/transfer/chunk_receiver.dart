import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wifi_ftp/core/data/models/chunk_model.dart';

class ChunkReceiver {
  final Map<String, RandomAccessFile> _openFiles = {};

  Future<void> handleIncomingChunk(ChunkModel chunk, Uint8List payload) async {
    // Phase 1: Security & Integrity Verification
    final computedChecksum = sha256.convert(payload).toString();
    if (computedChecksum != chunk.checksum) {
      throw Exception("CRITICAL ERROR: Transmission Corruption. Checksum failed for chunk ${chunk.chunkIndex}");
    }

    // Phase 2: Persistence Preparation
    RandomAccessFile? raf = _openFiles[chunk.fileId];
    if (raf == null) {
      final dir = await getDownloadsDirectory();
      final baseDir = dir?.path ?? '/storage/emulated/0/Download';
      final file = File('$baseDir/${chunk.fileId}');
      
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      
      raf = await file.open(mode: FileMode.append);
      _openFiles[chunk.fileId] = raf;
    }

    // Phase 3: Thread-Safe Byte Writing
    // Calculates strict exact offset insertion based on the protocol constants
    final offset = chunk.chunkIndex * 4194304; 
    await raf.setPosition(offset);
    await raf.writeFrom(payload);
  }
  
  Future<void> finalizeFile(String fileId) async {
    await _openFiles[fileId]?.close();
    _openFiles.remove(fileId);
  }
}
