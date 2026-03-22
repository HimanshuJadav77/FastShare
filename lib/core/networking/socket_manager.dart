import 'dart:io';
import 'package:flutter/foundation.dart';

class SocketManager {
  final Map<String, List<Socket>> _deviceSockets = {};
  ServerSocket? _serverSocket;

  Future<void> startServer(int port, Function(Socket) onConnection) async {
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _serverSocket?.listen(onConnection);
      debugPrint('TCP Server listening on port $port');
    } catch (e) {
      debugPrint('Error starting server: $e');
    }
  }

  Future<Socket?> connectTo(String ip, int port) async {
    try {
      return await Socket.connect(ip, port, timeout: const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Failed to connect to $ip:$port - $e');
      return null;
    }
  }

  void registerSocket(String deviceId, Socket socket) {
    if (!_deviceSockets.containsKey(deviceId)) {
      _deviceSockets[deviceId] = [];
    }
    _deviceSockets[deviceId]!.add(socket);
  }

  List<Socket> getSocketsForDevice(String deviceId) {
    return _deviceSockets[deviceId] ?? [];
  }

  void disconnectDevice(String deviceId) {
    final sockets = _deviceSockets.remove(deviceId);
    if (sockets != null) {
      for (var s in sockets) {
        try { s.close(); } catch (_) {}
      }
    }
  }

  void stopAll() {
    _serverSocket?.close();
    _deviceSockets.forEach((_, sockets) {
      for (var s in sockets) {
        try { s.close(); } catch (_) {}
      }
    });
    _deviceSockets.clear();
  }
}
