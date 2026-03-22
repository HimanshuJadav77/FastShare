# Wi-Fi FTP Server

A high-performance, monochrome-themed Flutter application that turns your Android device into a Wi-Fi FTP server.

## Features
- **Wi-Fi FTP Server**: Access device files from any FTP client (FileZilla, Windows Explorer).
- **Speed Optimized**: Designed for LAN performance.
- **Secure**: Randomly generated credentials, LAN-only access.
- **Theme**: Strict Monochrome (Black & White).
- **Permissions**: Handles Android 8-10 and Android 11+ storage permissions.
- **QR Connect**: Scan to connect instantly.

## Setup & Permissions
### Android 10
- Based on `requestLegacyExternalStorage`, just grant "Storage" permission.

### Android 11+ (Android R, S, T, U)
- Requires **"All Files Access"** (`MANAGE_EXTERNAL_STORAGE`) to serve `/storage/emulated/0/`.
- On first launch, if you see "Storage Access Required":
  1. Grants "Settings".
  2. Toggle **"Allow access to manage all files"**.
- **SAF Fallback**: If you deny the above, select "Use System Picker" to share a specific folder via Android's file picker.

## Setup Instructions

1. **Prerequisites**
   - Flutter SDK (3.10+)
   - Android Device (Android 8+)
   - USB Debugging enabled

2. **Installation**
   ```bash
   git clone <repo>
   cd wifi_ftp
   flutter pub get
   ```

3. **Running the App**
   Connect your Android device and run:
   ```bash
   flutter run
   ```

## Usage
1. Connect phone and PC to the **same Wi-Fi network**.
2. Open the app and grant **Storage Permissions** when prompted.
3. Select a **Shared Folder**.
4. Tap **START SERVER**.
5. On your PC, open File Explorer or FileZilla.
6. Enter the **FTP URL** displayed (e.g., `ftp://192.168.1.5:2221`).
7. Enter the **Username** and **Password** shown on the screen.

## Troubleshooting
- **Connection Refused**: Ensure both devices are on the same Wi-Fi. Check if firewall is blocking port 2221.
- **Permission Denied**: Go to Android Settings -> Apps -> Wi-Fi FTP -> Permissions and enable Storage access manually if needed.
- **Slow Speed**: Use 5GHz Wi-Fi for best performance.

## Dependencies
- `ftp_server`
- `network_info_plus`
- `permission_handler`
- `path_provider`
- `qr_flutter`
- `device_info_plus`
