import 'dart:async';
import 'dart:io';
import 'package:wifi_ftp/core/transfer/chunk_sender.dart';
import 'package:wifi_ftp/core/networking/socket_manager.dart';

class TransferScheduler {
  final ChunkSender _sender;
  final SocketManager _socketManager;
  final int _parallelStreams = 4;

  TransferScheduler(this._sender, this._socketManager);

  Future<void> startParallelTransfer(String deviceId, File file, String targetIp, int corePort) async {
    // Scaffold optimal parallel buffer lane pipelines
    for (int i = 0; i < _parallelStreams; i++) {
       final socket = await _socketManager.connectTo(targetIp, corePort);
       if (socket != null) {
          _socketManager.registerSocket(deviceId, socket);
          socket.write('{"type":"DATA_INIT"}\n');
       }
    }
    
    // Commence distributed binary payload dispatching
    await _sender.sendFile(deviceId, file);
  }
}
