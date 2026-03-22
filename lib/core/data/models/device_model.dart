import 'dart:convert';

class DeviceModel {
  final String deviceId;
  final String deviceName;
  final String deviceType; // e.g., 'android', 'windows'
  final Map<String, dynamic> capabilities;
  
  // Non-UI visible connection info
  final String ip;
  final int port;

  DeviceModel({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.ip,
    required this.port,
    this.capabilities = const {},
  });

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_name': deviceName,
        'device_type': deviceType,
        'ip': ip,
        'port': port,
        'capabilities': capabilities,
      };

  factory DeviceModel.fromJson(Map<String, dynamic> json) => DeviceModel(
        deviceId: json['device_id'] ?? '',
        deviceName: json['device_name'] ?? 'Unknown Device',
        deviceType: json['device_type'] ?? 'unknown',
        ip: json['ip'] ?? '',
        port: json['port'] ?? 45556,
        capabilities: json['capabilities'] ?? {},
      );

  @override
  String toString() => jsonEncode(toJson());
}
