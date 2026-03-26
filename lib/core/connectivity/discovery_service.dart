import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wifi_ftp/core/data/models/device_model.dart';
import 'package:wifi_ftp/core/connectivity/wifi_service.dart';
import 'package:wifi_ftp/core/connectivity/bluetooth_service.dart';
import 'package:wifi_ftp/core/connectivity/hotspot_service.dart';
import 'package:wifi_ftp/core/networking/tcp_server.dart';

class DiscoveryOrchestrator {
  final WifiService wifiService = WifiService();
  final BluetoothService _bluetoothService = BluetoothService();
  final HotspotService hotspotService = HotspotService();
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

    // 2. Bluetooth BLE Discovery (Fallback)
    _bluetoothService.discoveredDevices.listen((device) {
      final current = List<DeviceModel>.from(wifiService.currentDevices);
      if (!current.any((d) => d.deviceId == device.deviceId)) {
        current.add(device);
        _devicesController.add(current);
      }
    });
    await _bluetoothService.startDiscovery();

    debugPrint('[ORCHESTRATOR] Discovery active.');
  }

  void stopDiscovery() {
    wifiService.stopDiscovery();
    _bluetoothService.stopDiscovery();
    tcpServer.stop(forceCloseClients: false);
    debugPrint('[ORCHESTRATOR] Discovery stopped.');
  }
}
