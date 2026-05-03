import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(() {
  return SettingsNotifier();
});

class SettingsState {
  final String deviceName;
  final String? lastDeviceName;
  final String? lastDeviceType;
  final String downloadPath;

  /// Chunk size in MB for file transfers (1, 4, or 8)
  final int chunkSizeMB;

  /// Number of parallel TCP streams per transfer (1–6)
  final int parallelStreams;

  /// Show progress notification on Android during active transfer
  final bool showProgressNotification;

  /// Keep screen awake while a transfer is active
  final bool keepScreenOn;

  /// --- Advanced Networking ---
  final int discoveryPort;
  final int controlPort;
  final int dataPort;
  final bool autoResume;
  final int broadcastIntervalSeconds;

  SettingsState({
    required this.deviceName,
    this.lastDeviceName,
    this.lastDeviceType,
    required this.downloadPath,
    this.chunkSizeMB = 4,
    this.parallelStreams = 3,
    this.showProgressNotification = true,
    this.keepScreenOn = true,
    this.discoveryPort = 45555,
    this.controlPort = 45556,
    this.dataPort = 45557,
    this.autoResume = true,
    this.broadcastIntervalSeconds = 1,
  });

  SettingsState copyWith({
    String? deviceName,
    String? lastDeviceName,
    String? lastDeviceType,
    String? downloadPath,
    int? chunkSizeMB,
    int? parallelStreams,
    bool? showProgressNotification,
    bool? keepScreenOn,
    int? discoveryPort,
    int? controlPort,
    int? dataPort,
    bool? autoResume,
    int? broadcastIntervalSeconds,
  }) {
    return SettingsState(
      deviceName: deviceName ?? this.deviceName,
      lastDeviceName: lastDeviceName ?? this.lastDeviceName,
      lastDeviceType: lastDeviceType ?? this.lastDeviceType,
      downloadPath: downloadPath ?? this.downloadPath,
      chunkSizeMB: chunkSizeMB ?? this.chunkSizeMB,
      parallelStreams: parallelStreams ?? this.parallelStreams,
      showProgressNotification: showProgressNotification ?? this.showProgressNotification,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      discoveryPort: discoveryPort ?? this.discoveryPort,
      controlPort: controlPort ?? this.controlPort,
      dataPort: dataPort ?? this.dataPort,
      autoResume: autoResume ?? this.autoResume,
      broadcastIntervalSeconds: broadcastIntervalSeconds ?? this.broadcastIntervalSeconds,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _nameKey               = 'custom_device_name';
  static const _lastDeviceNameKey     = 'last_device_name';
  static const _lastDeviceTypeKey     = 'last_device_type';
  static const _downloadPathKey       = 'download_path';
  static const _chunkSizeMBKey        = 'chunk_size_mb';
  static const _parallelStreamsKey     = 'parallel_streams';
  static const _showProgressNotifKey  = 'show_progress_notif';
  static const _keepScreenOnKey       = 'keep_screen_on';
  
  static const _discoveryPortKey      = 'discovery_port';
  static const _controlPortKey        = 'control_port';
  static const _dataPortKey           = 'data_port';
  static const _autoResumeKey         = 'auto_resume';
  static const _broadcastIntervalKey  = 'broadcast_interval';

  @override
  SettingsState build() {
    _loadSettings();
    return SettingsState(deviceName: 'Device', downloadPath: '/Downloads/Fastshare');
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    String? name      = prefs.getString(_nameKey);
    String? lastName  = prefs.getString(_lastDeviceNameKey);
    String? lastType  = prefs.getString(_lastDeviceTypeKey);
    String? path      = prefs.getString(_downloadPathKey);
    int? chunkSizeMB  = prefs.getInt(_chunkSizeMBKey);
    int? parallelStreams = prefs.getInt(_parallelStreamsKey);
    bool? showNotif   = prefs.getBool(_showProgressNotifKey);
    bool? keepScreen  = prefs.getBool(_keepScreenOnKey);
    
    int? dPort = prefs.getInt(_discoveryPortKey);
    int? cPort = prefs.getInt(_controlPortKey);
    int? daPort = prefs.getInt(_dataPortKey);
    bool? resume = prefs.getBool(_autoResumeKey);
    int? bInterval = prefs.getInt(_broadcastIntervalKey);

    if (name == null || name.isEmpty) {
      name = await _getOSDeviceName();
    }

    if (path == null) {
      if (Platform.isAndroid) {
        path = '/storage/emulated/0/download/Fastshare';
      } else if (Platform.isWindows) {
        path = 'C:\\Downloads\\Fastshare';
      } else {
        path = 'Downloads/Fastshare';
      }
    }

    state = state.copyWith(
      deviceName: name,
      lastDeviceName: lastName,
      lastDeviceType: lastType,
      downloadPath: path,
      chunkSizeMB: chunkSizeMB ?? 4,
      parallelStreams: parallelStreams ?? 3,
      showProgressNotification: showNotif ?? true,
      keepScreenOn: keepScreen ?? true,
      discoveryPort: dPort ?? 45555,
      controlPort: cPort ?? 45556,
      dataPort: daPort ?? 45557,
      autoResume: resume ?? true,
      broadcastIntervalSeconds: bInterval ?? 1,
    );
  }

  Future<void> setDownloadPath(String path) async {
    state = state.copyWith(downloadPath: path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_downloadPathKey, path);
  }

  Future<void> setChunkSizeMB(int mb) async {
    state = state.copyWith(chunkSizeMB: mb);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_chunkSizeMBKey, mb);
  }

  Future<void> setParallelStreams(int count) async {
    state = state.copyWith(parallelStreams: count.clamp(1, 6));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_parallelStreamsKey, count.clamp(1, 6));
  }

  Future<void> setShowProgressNotification(bool value) async {
    state = state.copyWith(showProgressNotification: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showProgressNotifKey, value);
  }

  Future<void> setKeepScreenOn(bool value) async {
    state = state.copyWith(keepScreenOn: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keepScreenOnKey, value);
  }

  Future<void> setDiscoveryPort(int port) async {
    state = state.copyWith(discoveryPort: port);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_discoveryPortKey, port);
  }

  Future<void> setControlPort(int port) async {
    state = state.copyWith(controlPort: port);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_controlPortKey, port);
  }

  Future<void> setDataPort(int port) async {
    state = state.copyWith(dataPort: port);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dataPortKey, port);
  }

  Future<void> setAutoResume(bool value) async {
    state = state.copyWith(autoResume: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoResumeKey, value);
  }

  Future<void> setBroadcastInterval(int seconds) async {
    state = state.copyWith(broadcastIntervalSeconds: seconds);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_broadcastIntervalKey, seconds);
  }

  Future<void> setLastDevice(String name, String type) async {
    state = state.copyWith(lastDeviceName: name, lastDeviceType: type);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastDeviceNameKey, name);
    await prefs.setString(_lastDeviceTypeKey, type);
  }

  Future<void> setDeviceName(String name) async {
    state = state.copyWith(deviceName: name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name);
  }

  Future<String> _getOSDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.model;
    } else if (Platform.isWindows) {
      final windowsInfo = await deviceInfo.windowsInfo;
      return windowsInfo.computerName;
    }
    return 'Unknown Device';
  }
}
