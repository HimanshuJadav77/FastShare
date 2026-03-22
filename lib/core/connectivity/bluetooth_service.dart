import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wifi_ftp/core/data/models/device_model.dart';
import 'package:flutter/foundation.dart';

class BluetoothService {
  final StreamController<DeviceModel> _deviceController = StreamController.broadcast();
  Stream<DeviceModel> get discoveredDevices => _deviceController.stream;

  Future<void> startDiscovery() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      debugPrint('Bluetooth Discovery skipped on Desktop platforms.');
      return;
    }

    try {
      if (await FlutterBluePlus.isSupported == false) return;

      if (Platform.isAndroid) {
        await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;
      }

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName.isNotEmpty) {
             _deviceController.add(DeviceModel(
                deviceId: r.device.remoteId.str,
                deviceName: r.device.platformName,
                deviceType: 'bluetooth_peer',
                ip: '',
                port: 0,
             ));
          }
        }
      });
    } catch (e) {
      debugPrint('Bluetooth Error: $e');
    }
  }

  void stopDiscovery() {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) return;
    try {
      FlutterBluePlus.stopScan();
    } catch (_) {}
  }
}
