import 'dart:typed_data';

class ChunkModel {
  final String type = "chunk";
  final String fileId;
  final int chunkIndex;
  final int totalChunks;
  final int chunkSize;
  final String checksum;
  final Uint8List? payload; // Binary payload directly attached dynamically

  ChunkModel({
    required this.fileId,
    required this.chunkIndex,
    required this.totalChunks,
    required this.chunkSize,
    required this.checksum,
    this.payload,
  });

  // Converts header to JSON (excluding binary payload)
  Map<String, dynamic> toJson() => {
        'type': type,
        'file_id': fileId,
        'chunk_index': chunkIndex,
        'total_chunks': totalChunks,
        'chunk_size': chunkSize,
        'checksum': checksum,
      };

  factory ChunkModel.fromJson(Map<String, dynamic> json) => ChunkModel(
        fileId: json['file_id'],
        chunkIndex: json['chunk_index'],
        totalChunks: json['total_chunks'],
        chunkSize: json['chunk_size'],
        checksum: json['checksum'],
      );
}
