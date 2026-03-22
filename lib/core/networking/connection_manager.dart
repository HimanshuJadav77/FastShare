import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:wifi_ftp/core/networking/socket_manager.dart';
import 'package:wifi_ftp/core/data/models/device_model.dart';
import 'package:wifi_ftp/core/reliability/heartbeat_service.dart';

class ConnectionManager {
  final SocketManager _socketManager;
  final HeartbeatService _heartbeatService;

  final StreamController<DeviceModel> _connectedController =
      StreamController.broadcast();
  Stream<DeviceModel> get onDeviceConnected => _connectedController.stream;

  ConnectionManager(this._socketManager, this._heartbeatService);

  Future<bool> connectToDevice(DeviceModel device) async {
    final socket = await _socketManager.connectTo(device.ip, device.port);
    if (socket == null) return false;

    _socketManager.registerSocket(device.deviceId, socket);

    // Send the TCP HELLO_PC JSON Payload
    final handshake = jsonEncode({
      'type': 'HELLO_PC',
      'device_id': 'local_device_session',
    });

    socket.write('$handshake\n');

    bool connected = false;
    socket.listen((data) {
      final msg = utf8.decode(data).trim();
      if (msg.contains('"type":"OK"')) {
        connected = true;
        _connectedController.add(device);
        _heartbeatService.startHeartbeat(socket, () {
          debugPrint('Heartbeat failed. Disconnected from ${device.deviceId}');
          _socketManager.disconnectDevice(device.deviceId);
        });
      }
    });

    await Future.delayed(const Duration(seconds: 2));
    return connected;
  }
}
