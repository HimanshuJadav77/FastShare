import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:wifi_ftp/core/data/models/device_model.dart';
import 'package:network_info_plus/network_info_plus.dart';

class WifiService {
  final int discoveryPort = 45555;
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  final List<DeviceModel> _discoveredDevices = [];
  final Map<String, DateTime> _lastSeen = {};
  final StreamController<List<DeviceModel>> _deviceController =
      StreamController.broadcast();

  Stream<List<DeviceModel>> get discoveredDevices => _deviceController.stream;
  List<DeviceModel> get currentDevices => List.unmodifiable(_discoveredDevices);

  Future<String?> getLocalIp() async {
    // Method 1: network_info_plus (works when connected TO a WiFi network)
    try {
      String? ip = await NetworkInfo().getWifiIP();
      debugPrint('[DISCOVERY] network_info_plus IP: $ip');
      if (ip != null && ip != '0.0.0.0' && !ip.startsWith('127.')) return ip;
    } catch (e) {
      debugPrint('[DISCOVERY] network_info_plus failed: $e');
    }

    // Method 2: Scan all network interfaces
    // When the phone IS the hotspot, network_info_plus returns null.
    // We must find the hotspot gateway interface (usually wlan/ap/swlan on 192.168.43.1)
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      // Cellular interface names to SKIP (these are mobile data, not local network)
      const cellularPrefixes = ['ccmni', 'rmnet', 'pdp', 'ppp', 'cdma'];

      String? bestIp;
      for (var iface in interfaces) {
        final nameLower = iface.name.toLowerCase();
        final isCellular = cellularPrefixes.any(
          (prefix) => nameLower.startsWith(prefix),
        );

        debugPrint(
          '[DISCOVERY] Interface: ${iface.name} (cellular: $isCellular)',
        );
        for (var addr in iface.addresses) {
          debugPrint(
            '[DISCOVERY]   Address: ${addr.address} (loopback: ${addr.isLoopback})',
          );
          if (addr.isLoopback || isCellular) continue;

          // Prefer 192.168.x.x (hotspot/LAN range)
          if (addr.address.startsWith('192.168.')) return addr.address;
          // Fallback to any other private IP
          bestIp ??= addr.address;
        }
      }
      if (bestIp != null) return bestIp;
    } catch (e) {
      debugPrint('[DISCOVERY] NetworkInterface.list failed: $e');
    }

    debugPrint('[DISCOVERY] WARNING: No usable IP address found!');
    return null;
  }

  Future<void> startDiscovery(DeviceModel localDevice) async {
    final ip = await getLocalIp();
    if (ip == null) {
      debugPrint(
        '[DISCOVERY] Cannot start discovery - no IP address available',
      );
      return;
    }
    debugPrint('[DISCOVERY] Local IP: $ip');

    // Bind UDP socket
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      _socket!.broadcastEnabled = true;
      debugPrint('[DISCOVERY] UDP socket bound to port $discoveryPort');
    } catch (e) {
      debugPrint('[DISCOVERY] UDP Bind FAILED: $e');
      return;
    }

    // Listen for incoming broadcasts
    _socket!.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket?.receive();
        if (datagram != null) {
          try {
            final jsonStr = utf8.decode(datagram.data);
            final json = jsonDecode(jsonStr);
            final device = DeviceModel.fromJson(json);
            final actualIp = datagram.address.address;

            debugPrint(
              '[DISCOVERY] Received broadcast from $actualIp: ${device.deviceName}',
            );

            if (device.deviceId != localDevice.deviceId) {
              _lastSeen[device.deviceId] = DateTime.now();

              // Update or add device
              final existingIndex = _discoveredDevices.indexWhere(
                (d) => d.deviceId == device.deviceId,
              );
              final updatedDevice = DeviceModel(
                deviceId: device.deviceId,
                deviceName: device.deviceName,
                deviceType: device.deviceType,
                ip: actualIp,
                port: device.port,
                capabilities: device.capabilities,
              );

              if (existingIndex >= 0) {
                _discoveredDevices[existingIndex] = updatedDevice;
              } else {
                _discoveredDevices.add(updatedDevice);
                debugPrint(
                  '[DISCOVERY] NEW device added: ${device.deviceName} @ $actualIp',
                );
              }
              _deviceController.add(List.unmodifiable(_discoveredDevices));
            }
          } catch (e) {
            debugPrint('[DISCOVERY] Failed to parse broadcast: $e');
          }
        }
      }
    });

    // Start periodic broadcasting
    _broadcastTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final broadcastModel = DeviceModel(
        deviceId: localDevice.deviceId,
        deviceName: localDevice.deviceName,
        deviceType: localDevice.deviceType,
        ip: ip,
        port: localDevice.port,
        capabilities: localDevice.capabilities,
      );
      final data = utf8.encode(jsonEncode(broadcastModel.toJson()));

      try {
        _socket?.send(data, InternetAddress("255.255.255.255"), discoveryPort);
      } catch (e) {
        debugPrint('[DISCOVERY] Global broadcast failed: $e');
      }

      try {
        final parts = ip.split('.');
        if (parts.length == 4) {
          final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          _socket?.send(data, InternetAddress(subnetBroadcast), discoveryPort);
        }
      } catch (e) {
        debugPrint('[DISCOVERY] Subnet broadcast failed: $e');
      }
    });

    // Cleanup timer: remove devices that haven't broadcast in 8 seconds
    _cleanupTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final now = DateTime.now();
      _discoveredDevices.removeWhere((d) {
        final lastSeen = _lastSeen[d.deviceId];
        if (lastSeen == null) return true;
        final stale = now.difference(lastSeen).inSeconds > 8;
        if (stale) {
          _lastSeen.remove(d.deviceId);
          debugPrint('[DISCOVERY] Device removed (stale): ${d.deviceName}');
        }
        return stale;
      });
      _deviceController.add(List.unmodifiable(_discoveredDevices));
    });

    debugPrint('[DISCOVERY] Broadcasting started. Waiting for peers...');
  }

  void stopDiscovery() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _socket?.close();
    _socket = null;
    _discoveredDevices.clear();
    _lastSeen.clear();
    debugPrint('[DISCOVERY] Stopped.');
  }
}
