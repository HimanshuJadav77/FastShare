import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class TcpServer {
  ServerSocket? _serverSocket;
  final List<Socket> _clients = [];
  final Set<Socket> _dataSockets = {};
  final StreamController<Map<String, dynamic>> _messageController = StreamController.broadcast();

  /// Called when a remote peer connects and sends HELLO_PC
  void Function(String remoteIp, int remotePort, String deviceName, String deviceId, Socket socket)? onPeerConnected;
  
  /// Called when an incoming peer disconnects or sends DISCONNECT
  void Function(Socket socket)? onPeerDisconnected;

  /// Called for all incoming JSON messages
  void Function(Map<String, dynamic> message)? onControlMessage;

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  bool get isRunning => _serverSocket != null;

  Future<void> start(int port) async {
    if (_serverSocket != null) {
      debugPrint('[TCP-SERVER] Already running.');
      return;
    }

    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      debugPrint('[TCP-SERVER] Listening on port $port');

      _serverSocket!.listen((Socket client) {
        debugPrint('[TCP-SERVER] New connection from ${client.remoteAddress.address}:${client.remotePort}');
        _clients.add(client);

        // Buffer for text-based control messages
        final List<int> rawBuffer = [];
        bool isDataSocket = false;

        client.listen(
          (Uint8List data) {
            // If this socket has been promoted to a data socket, handle binary directly
            if (isDataSocket) {
              _handleBinaryData(data, client);
              return;
            }

            // Try to parse as text control message
            rawBuffer.addAll(data);

            // Check if we can decode as UTF-8 text
            try {
              final text = utf8.decode(rawBuffer);

              while (text.contains('\n')) {
                final decoded = utf8.decode(rawBuffer);
                final nlIndex = decoded.indexOf('\n');
                final line = decoded.substring(0, nlIndex).trim();
                final remaining = decoded.substring(nlIndex + 1);
                rawBuffer.clear();
                rawBuffer.addAll(utf8.encode(remaining));

                if (line.isEmpty) continue;

                try {
                  final json = jsonDecode(line) as Map<String, dynamic>;
                  debugPrint('[TCP-SERVER] Message: ${json['type']}');

                  if (json['type'] == 'HELLO_PC') {
                    debugPrint('[TCP-SERVER] Received HELLO_PC');
                    // DO NOT auto-send OK — let AppConnection decide (accept/reject dialog)
                    final peerName = json['device_name'] as String? ?? 'Unknown';
                    final peerId = json['device_id'] as String? ?? '';
                    try {
                      onPeerConnected?.call(
                        client.remoteAddress.address,
                        client.remotePort,
                        peerName,
                        peerId,
                        client,
                      );
                    } catch (e) {
                      debugPrint('[TCP-SERVER] onPeerConnected error: $e');
                    }
                  } else if (json['type'] == 'PING') {
                    _safeWrite(client, '${jsonEncode({'type': 'PONG'})}\n');
                  } else if (json['type'] == 'DISCONNECT') {
                    debugPrint('[TCP-SERVER] Peer sent DISCONNECT');
                    onPeerDisconnected?.call(client);
                  } else if (json['type'] == 'CANCEL_TRANSFER' || 
                             json['type'] == 'PAUSE_TRANSFER' || 
                             json['type'] == 'RESUME_TRANSFER') {
                    onControlMessage?.call(json);
                  } else if (json['type'] == 'DATA_INIT') {
                    debugPrint('[TCP-SERVER] Data socket initialized - switching to binary mode');
                    isDataSocket = true;
                    _dataSockets.add(client);
                    rawBuffer.clear();
                  }

                  if (!_messageController.isClosed) {
                    _messageController.add(json);
                  }
                } catch (e) {
                  debugPrint('[TCP-SERVER] JSON parse error: $e');
                }
                break; // Process one message at a time
              }
            } catch (_) {
              // If we can't decode as UTF-8, it's binary data on a misidentified socket
              isDataSocket = true;
              _dataSockets.add(client);
              rawBuffer.clear();
              _handleBinaryData(data, client);
            }
          },
          onDone: () {
            try {
              debugPrint('[TCP-SERVER] Client disconnected: ${client.remoteAddress.address}');
            } catch (_) {
              debugPrint('[TCP-SERVER] Client disconnected');
            }
            onPeerDisconnected?.call(client);
            _clients.remove(client);
            _dataSockets.remove(client);
          },
          onError: (e) {
            debugPrint('[TCP-SERVER] Client error: $e');
            onPeerDisconnected?.call(client);
            _clients.remove(client);
            _dataSockets.remove(client);
          },
        );
      });
    } catch (e) {
      debugPrint('[TCP-SERVER] FAILED to start: $e');
    }
  }

  void _handleBinaryData(Uint8List data, Socket client) {
    // Binary chunk data received - will be wired to ChunkReceiver later
    debugPrint('[TCP-SERVER] Binary data received: ${data.length} bytes');
  }

  void _safeWrite(Socket client, String message) {
    try {
      client.write(message);
    } catch (e) {
      debugPrint('[TCP-SERVER] Write failed (sink closed): $e');
    }
  }

  void stop() {
    for (var c in _clients) {
      try { c.close(); } catch (_) {}
    }
    _clients.clear();
    _dataSockets.clear();
    _serverSocket?.close();
    _serverSocket = null;
    debugPrint('[TCP-SERVER] Stopped.');
  }
}
