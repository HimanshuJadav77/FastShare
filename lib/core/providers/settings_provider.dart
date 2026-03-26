import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

class SettingsState {
  final String deviceName;
  final String? lastDeviceName;
  final String? lastDeviceType;
  final String downloadPath;
  final bool autoResumeEnabled;

  SettingsState({
    required this.deviceName,
    this.lastDeviceName,
    this.lastDeviceType,
    required this.downloadPath,
    this.autoResumeEnabled = true,
  });

  SettingsState copyWith({
    String? deviceName,
    String? lastDeviceName,
    String? lastDeviceType,
    String? downloadPath,
    bool? autoResumeEnabled,
  }) {
    return SettingsState(
      deviceName: deviceName ?? this.deviceName,
      lastDeviceName: lastDeviceName ?? this.lastDeviceName,
      lastDeviceType: lastDeviceType ?? this.lastDeviceType,
      downloadPath: downloadPath ?? this.downloadPath,
      autoResumeEnabled: autoResumeEnabled ?? this.autoResumeEnabled,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  static const _nameKey = 'custom_device_name';

  static const _lastDeviceNameKey = 'last_device_name';
  static const _lastDeviceTypeKey = 'last_device_type';
  static const _downloadPathKey = 'download_path';
  static const _autoResumeKey = 'auto_resume_enabled';

  SettingsNotifier() : super(SettingsState(deviceName: 'Device', downloadPath: '/Downloads/FastShare')) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    String? name = prefs.getString(_nameKey);
    String? lastName = prefs.getString(_lastDeviceNameKey);
    String? lastType = prefs.getString(_lastDeviceTypeKey);
    String? path = prefs.getString(_downloadPathKey);
    bool? autoResume = prefs.getBool(_autoResumeKey);
    
    if (name == null || name.isEmpty) {
      name = await _getOSDeviceName();
    }

    if (path == null) {
      if (Platform.isAndroid) {
        path = '/storage/emulated/0/Download/FastShare';
      } else if (Platform.isWindows) {
        path = 'C:\\Downloads\\FastShare';
      } else {
        path = 'Downloads/FastShare';
      }
    }
    
    state = state.copyWith(
      deviceName: name,
      lastDeviceName: lastName,
      lastDeviceType: lastType,
      downloadPath: path,
      autoResumeEnabled: autoResume ?? true,
    );
  }

  Future<void> setDownloadPath(String path) async {
    state = state.copyWith(downloadPath: path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_downloadPathKey, path);
  }

  Future<void> toggleAutoResume(bool value) async {
    state = state.copyWith(autoResumeEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoResumeKey, value);
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
