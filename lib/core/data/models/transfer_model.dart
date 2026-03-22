enum TransferState { pending, transferring, paused, completed, failed }

class TransferModel {
  final String fileId;
  final String fileName;
  final int totalSize;
  final int totalChunks;
  List<int> receivedChunks;
  TransferState state;
  double speedBytesPerSecond;

  TransferModel({
    required this.fileId,
    required this.fileName,
    required this.totalSize,
    required this.totalChunks,
    List<int>? receivedChunks,
    this.state = TransferState.pending,
    this.speedBytesPerSecond = 0.0,
  }) : receivedChunks = receivedChunks ?? [];

  double get progress => totalChunks == 0 ? 0 : receivedChunks.length / totalChunks;

  Map<String, dynamic> toJson() => {
        'file_id': fileId,
        'file_name': fileName,
        'total_size': totalSize,
        'total_chunks': totalChunks,
        'received_chunks': receivedChunks,
      };

  factory TransferModel.fromJson(Map<String, dynamic> json) => TransferModel(
        fileId: json['file_id'],
        fileName: json['file_name'],
        totalSize: json['total_size'],
        totalChunks: json['total_chunks'],
        receivedChunks: List<int>.from(json['received_chunks'] ?? []),
      );
}
