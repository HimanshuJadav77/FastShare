class DeviceModel {
  final String deviceId;
  final String deviceName;
  final String deviceType;
  final String ip;
  final int port;
  final List<String> capabilities;

  DeviceModel({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.ip,
    required this.port,
    this.capabilities = const [],
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      deviceId: json['deviceId'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? 'Unknown Device',
      deviceType: json['deviceType'] as String? ?? 'unknown',
      ip: json['ip'] as String? ?? '',
      port: json['port'] as int? ?? 45556,
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'deviceType': deviceType,
      'ip': ip,
      'port': port,
      'capabilities': capabilities,
    };
  }
}
