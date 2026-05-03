# FastShare 🚀

**FastShare** is a high-performance, local-first file transfer application for Android. Designed to eliminate the friction of cloud-based sharing, it leverages a custom peer-to-peer protocol to achieve blazing-fast speeds over Wi-Fi.

![FastShare UI](https://via.placeholder.com/800x450?text=FastShare+Modern+Minimal+UI)

## ✨ Features

- **Blazing Speed**: Custom parallel TCP stream architecture capable of **25MB/s - 50MB/s** on standard 5GHz Wi-Fi.
- **Zero Configuration**: Automatic device discovery using UDP broadcasting—just open the app and find nearby devices.
- **Premium Minimalist UI**: A clean, distraction-free interface with smooth animations and a "mobile-first" aesthetic.
- **Background Persistence**: Integrated with Android Foreground Services; transfers continue reliably even when the app is minimized or the screen is off.
- **Intelligent Notifications**: Real-time progress bars and "Smart Disconnect" alerts that keep you informed without being intrusive.
- **Privacy First**: Transfers happen exclusively over your local network. No cloud, no tracking, and no internet required.
- **Robust Recovery**: Automated handling of network interruptions with clear "Retry" options for failed transfers.

## 🛠️ Technology Stack

- **Framework**: Flutter (Dart)
- **Protocol**: Custom TCP Control Channel + Parallel Data Sockets
- **Discovery**: UDP Multicast/Broadcast
- **State Management**: Flutter Riverpod 3.0 (Notifiers & Providers)
- **Background Logic**: `flutter_foreground_task` & Isolate-based file I/O

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (3.10.0 or higher)
- Android Device (Android 8.0+)
- Both devices connected to the **same Wi-Fi network**

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/HimanshuJadav77/FastShare.git
   ```
2. Install dependencies:
   ```bash
   cd FastShare
   flutter pub get
   ```
3. Run the application:
   ```bash
   flutter run
   ```

## 📱 Permissions
To ensure high-speed access to all your media, the app requires:
- **All Files Access**: (Android 11+) For serving and saving files directly to storage.
- **Location**: Required by Android for Wi-Fi SSID discovery.
- **Notifications**: For background transfer monitoring.

## 🤝 Contributing
Contributions are welcome! If you have ideas for improving transfer speeds or enhancing the UI, feel free to open a Pull Request.

---
Developed with ❤️ by [Himanshu Jadav](https://github.com/HimanshuJadav77)
