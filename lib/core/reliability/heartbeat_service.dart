import 'dart:async';
import 'dart:io';

class HeartbeatService {
  Timer? _timer;
  final Duration _interval = const Duration(seconds: 3);

  void startHeartbeat(Socket socket, Function onTimeout) {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) {
      try {
        socket.write('{"type":"PING"}\n');
      } catch (e) {
        onTimeout();
        stop();
      }
        });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
