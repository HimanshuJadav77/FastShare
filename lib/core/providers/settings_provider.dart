import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

class SettingsState {
  final String deviceName;
  SettingsState({required this.deviceName});

  SettingsState copyWith({String? deviceName}) {
    return SettingsState(deviceName: deviceName ?? this.deviceName);
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  static const _nameKey = 'custom_device_name';

  SettingsNotifier() : super(SettingsState(deviceName: 'Device')) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    String? name = prefs.getString(_nameKey);
    
    if (name == null || name.isEmpty) {
      // Default to OS device name
      name = await _getOSDeviceName();
    }
    
    state = state.copyWith(deviceName: name);
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
