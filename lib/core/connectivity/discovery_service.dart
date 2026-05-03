import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wifi_ftp/core/data/models/device_model.dart';
import 'package:wifi_ftp/core/connectivity/wifi_service.dart';
import 'package:wifi_ftp/core/networking/tcp_server.dart';

class DiscoveryOrchestrator {
  final WifiService wifiService = WifiService();
  final TcpServer tcpServer = TcpServer();

  final StreamController<List<DeviceModel>> _devicesController = StreamController.broadcast();
  Stream<List<DeviceModel>> get discoveredDevices => _devicesController.stream;
  List<DeviceModel> get currentDevices => wifiService.currentDevices;

  Future<void> startDiscovery(DeviceModel localDevice) async {
    debugPrint('[ORCHESTRATOR] Starting hybrid discovery...');

    // Start TCP server FIRST so peers can connect to us
    await tcpServer.start(localDevice.port);

    // 1. Wi-Fi LAN Discovery (Primary)
    wifiService.discoveredDevices.listen((devices) {
      _devicesController.add(devices);
    });
    await wifiService.startDiscovery(localDevice);

    debugPrint('[ORCHESTRATOR] Discovery active.');
  }

  void stopDiscovery() {
    wifiService.stopDiscovery();
    tcpServer.stop(forceCloseClients: false);
    debugPrint('[ORCHESTRATOR] Discovery stopped.');
  }
}
