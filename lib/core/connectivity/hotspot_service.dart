import 'package:wifi_iot/wifi_iot.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

class HotspotService {
  Future<bool> createHotspot(String ssid, String password) async {
    if (!Platform.isAndroid) return false;

    // WiFi_IOT requires LOCATION and WIFI state permissions
    final enabled = await WiFiForIoTPlugin.setWiFiAPEnabled(true);
    if (enabled) {
      // ignore: deprecated_member_use
      await WiFiForIoTPlugin.setWiFiAPSSID(ssid);
      // ignore: deprecated_member_use
      await WiFiForIoTPlugin.setWiFiAPPreSharedKey(password);
      debugPrint('Hotspot created: $ssid');
      return true;
    }
    return false;
  }

  Future<bool> connectToHotspot(String ssid, String password) async {
    if (!Platform.isAndroid) return false;
    
    await WiFiForIoTPlugin.setEnabled(true);
    return await WiFiForIoTPlugin.connect(ssid, password: password, security: NetworkSecurity.WPA);
  }

  Future<void> disableHotspot() async {
    if (Platform.isAndroid) {
      await WiFiForIoTPlugin.setWiFiAPEnabled(false);
    }
  }
}
