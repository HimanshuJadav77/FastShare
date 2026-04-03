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
        client.done.catchError((_) {});

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

            // New Robust Logic: Only clear buffer for what we actually parsed
            try {
              final String decoded = utf8.decode(rawBuffer, allowMalformed: true);
              if (decoded.contains('\n')) {
                final lines = decoded.split('\n');
                // The last element is either empty or a partial line
                final String partialLine = lines.last;
                
                for (int i = 0; i < lines.length - 1; i++) {
                  final line = lines[i].trim();
                  if (line.isEmpty) continue;
                  
                  try {
                    final json = jsonDecode(line) as Map<String, dynamic>;
                    debugPrint('[TCP-SERVER] Signal: ${json['type']}');
                    
                    if (json['type'] == 'HELLO_PC') {
                      onPeerConnected?.call(client.remoteAddress.address, client.remotePort, json['device_name'] ?? 'Unknown', json['device_id'] ?? '', client);
                    } else if (json['type'] == 'PING') {
                      _safeWrite(client, '${jsonEncode({'type': 'PONG'})}\n');
                    } else if (json['type'] == 'DISCONNECT') {
                      onPeerDisconnected?.call(client);
                    } else if (json['type'] == 'CANCEL_TRANSFER' || json['type'] == 'PAUSE_TRANSFER' || json['type'] == 'RESUME_TRANSFER') {
                      onControlMessage?.call(json);
                    } else if (json['type'] == 'DATA_INIT') {
                      isDataSocket = true;
                      _dataSockets.add(client);
                      // Hand over the REMAINING buffer to binary mode if any
                      rawBuffer.clear();
                      if (partialLine.isNotEmpty) {
                        _handleBinaryData(Uint8List.fromList(utf8.encode(partialLine)), client);
                      }
                      return; // Exit loop, promoted to binary
                    }
                    
                    if (!_messageController.isClosed) _messageController.add(json);
                  } catch (e) {
                    debugPrint('[TCP-SERVER] JSON Error: $e');
                  }
                }
                
                // Keep only the partial line in the buffer
                rawBuffer.clear();
                rawBuffer.addAll(utf8.encode(partialLine));
              }
            } catch (e) {
              debugPrint('[TCP-SERVER] Decode Error (ignoring malformed): $e');
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

  void stop({bool forceCloseClients = false}) {
    if (forceCloseClients) {
      for (var c in _clients) {
        try { c.close(); } catch (_) {}
      }
      _clients.clear();
      _dataSockets.clear();
    }
    _serverSocket?.close();
    _serverSocket = null;
    debugPrint('[TCP-SERVER] Stopped.');
  }
}
