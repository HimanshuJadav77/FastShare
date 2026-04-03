import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wifi_ftp/core/data/models/device_model.dart';
import 'package:wifi_ftp/core/connectivity/discovery_service.dart';
import 'package:wifi_ftp/core/networking/tcp_server.dart';
import 'package:wifi_ftp/core/transfer/file_transfer_service.dart';
import 'package:wifi_ftp/core/transfer/transfer_queue.dart';

enum ConnectionState { idle, discovering, connecting, connected, transferring, disconnected }

/// Pending incoming connection request waiting for user accept/reject
class PendingConnectionRequest {
  final String deviceName;
  final String deviceId;
  final String remoteIp;
  final int remotePort;
  final Socket socket;

  PendingConnectionRequest({
    required this.deviceName,
    required this.deviceId,
    required this.remoteIp,
    required this.remotePort,
    required this.socket,
  });
}

class AppConnection extends ChangeNotifier {
  // Singleton
  static final AppConnection _instance = AppConnection._internal();
  factory AppConnection() => _instance;
  AppConnection._internal() {
    orchestrator.tcpServer.onPeerConnected = _onIncomingPeerConnected;
    orchestrator.tcpServer.onPeerDisconnected = _onIncomingPeerDisconnected;
    orchestrator.tcpServer.onControlMessage = (json) {
      final type = json['type'];
      if (type == 'PAUSE_TRANSFER') {
        try { _queue.pauseItem(json['id']); } catch (_) {}
      } else if (type == 'RESUME_TRANSFER') {
        try { _queue.resumeItem(json['id']); } catch (_) {}
      } else if (type == 'CANCEL_TRANSFER') {
        try {
          final itemName = _queue.items.firstWhere((i) => i.id == json['id']).fileName;
          _queue.cancelItem(json['id']);
          _showCancelledPopup(itemName);
        } catch (_) {}
      }
    };
  }

  // State
  ConnectionState _state = ConnectionState.idle;
  DeviceModel? _connectedDevice;
  DeviceModel? _localDevice;
  Socket? _controlSocket;
  Timer? _heartbeatTimer;
  PendingConnectionRequest? _pendingRequest;
  StreamSubscription? _controlSocketSub;
  int _heartbeatFailures = 0;

  // Global navigator key — set from main.dart
  static GlobalKey<NavigatorState>? navigatorKey;

  // Services
  final DiscoveryOrchestrator orchestrator = DiscoveryOrchestrator();
  final FileTransferService fileTransfer = FileTransferService();
  final TransferQueue _queue = TransferQueue();

  // Getters
  ConnectionState get state => _state;
  DeviceModel? get connectedDevice => _connectedDevice;
  DeviceModel? get localDevice => _localDevice;
  PendingConnectionRequest? get pendingRequest => _pendingRequest;
  bool get isConnected => _state == ConnectionState.connected || _state == ConnectionState.transferring;
  TcpServer get tcpServer => orchestrator.tcpServer;

  void _setState(ConnectionState newState) {
    _state = newState;
    debugPrint('[CONNECTION] State → ${newState.name}');
    Future.microtask(() => notifyListeners());
  }

  // ─── Listen on control socket for DISCONNECT / closure ───

  /// Monitor an existing subscription for DISCONNECT / closure signals.
  /// If [existingSub] is provided, we reuse it (for outgoing connections
  /// where the socket stream was already listened to).
  void _monitorControlSocket(Socket socket, {StreamSubscription? existingSub}) {
    _controlSocketSub?.cancel();
    if (existingSub != null) {
      // Reuse the existing subscription — swap its handlers
      _controlSocketSub = existingSub;
      existingSub.onData((data) {
        _handleControlData(data);
      });
      existingSub.onDone(() {
        debugPrint('[CONNECTION] Control socket closed by remote');
        _onRemoteDisconnect();
      });
      existingSub.onError((e) {
        debugPrint('[CONNECTION] Control socket error: $e');
        _onRemoteDisconnect();
      });
    } else {
      // Fresh listen (for incoming connections where we own the socket)
      _controlSocketSub = socket.listen(
        (data) => _handleControlData(data),
        onDone: () {
          debugPrint('[CONNECTION] Control socket closed by remote');
          _onRemoteDisconnect();
        },
        onError: (e) {
          debugPrint('[CONNECTION] Control socket error: $e');
          _onRemoteDisconnect();
        },
      );
    }
  }

  void _handleControlData(dynamic data) {
    try {
      final msg = utf8.decode(data).trim();
      for (final line in msg.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final json = jsonDecode(trimmed);
          final type = json['type'];
          if (type == 'DISCONNECT') {
            debugPrint('[CONNECTION] Remote device sent DISCONNECT');
            _onRemoteDisconnect();
          } else if (type == 'PAUSE_TRANSFER') {
            try { _queue.pauseItem(json['id']); } catch (_) {}
          } else if (type == 'RESUME_TRANSFER') {
            try { _queue.resumeItem(json['id']); } catch (_) {}
          } else if (type == 'CANCEL_TRANSFER') {
            try {
              final itemName = _queue.items.firstWhere((i) => i.id == json['id']).fileName;
              _queue.cancelItem(json['id']);
              _showCancelledPopup(itemName);
            } catch (_) {}
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  void sendTransferControl(String type, String id) {
    if (_controlSocket == null) return;
    try {
      _controlSocket!.write('${jsonEncode({'type': type, 'id': id})}\n');
    } catch (e) {
      debugPrint('[CONNECTION] Failed to send control msg: $e');
    }
  }

  void _onIncomingPeerDisconnected(Socket socket) {
    if (_controlSocket == socket) {
      debugPrint('[CONNECTION] TcpServer reported incoming peer disconnected');
      _onRemoteDisconnect();
    }
  }

  void _showCancelledPopup(String fileName) {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) return;

    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Transfer Cancelled'),
        content: Text('"$fileName" was cancelled by ${connectedDevice?.deviceName ?? "the other device"}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onRemoteDisconnect() {
    if (!isConnected && _state != ConnectionState.connecting) return;
    
    _heartbeatFailures = 0;
    
    final wasDevice = _connectedDevice?.deviceName ?? 'Unknown';
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _controlSocketSub?.cancel();
    _controlSocketSub = null;
    
    try { _controlSocket?.destroy(); } catch (_) {}
    _controlSocket = null;
    _connectedDevice = null;
    
    // Pause all active sender isolates gracefully so transfers can resume later
    try { fileTransfer.pauseAllSenders(); } catch (_) {}

    fileTransfer.stopReceiver();
    _setState(ConnectionState.disconnected);
    debugPrint('[CONNECTION] Remote disconnected: $wasDevice');
  }

  // ─── Incoming connection handler ───

  void _onIncomingPeerConnected(String remoteIp, int remotePort, String deviceName, String deviceId, Socket socket) {
    if (isConnected) {
      debugPrint('[CONNECTION] Already connected, rejecting incoming from $deviceName');
      _rejectSocket(socket);
      return;
    }

    debugPrint('[CONNECTION] Incoming request from $deviceName @ $remoteIp — showing dialog');

    _pendingRequest = PendingConnectionRequest(
      deviceName: deviceName,
      deviceId: deviceId,
      remoteIp: remoteIp,
      remotePort: remotePort,
      socket: socket,
    );
    Future.microtask(() => notifyListeners());
    _showConnectionDialog();
  }

  void _showConnectionDialog() {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) {
      debugPrint('[CONNECTION] No navigator context — auto-accepting');
      acceptPendingConnection();
      return;
    }

    final req = _pendingRequest;
    if (req == null) return;

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(ctx).dividerColor.withValues(alpha: 0.2)),
        ),
        title: const Row(
          children: [
            Icon(Icons.devices, color: Colors.white, size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('Connection Request', style: TextStyle(color: Colors.white, fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${req.deviceName} wants to connect',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Allow this device to send and receive files?',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              rejectPendingConnection();
            },
            child: const Text('REJECT', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              acceptPendingConnection();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('ACCEPT', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void acceptPendingConnection() {
    final req = _pendingRequest;
    if (req == null) return;
    _pendingRequest = null;

    // Send OK
    try {
      req.socket.write('${jsonEncode({'type': 'OK', 'message': 'Connected'})}\n');
      debugPrint('[CONNECTION] Sent OK to ${req.deviceName}');
    } catch (e) {
      debugPrint('[CONNECTION] Failed to send OK: $e');
      return;
    }

    // Stop discovery
    orchestrator.wifiService.stopDiscovery();

    _connectedDevice = DeviceModel(
      deviceId: req.deviceId,
      deviceName: req.deviceName,
      deviceType: 'unknown',
      ip: req.remoteIp,
      port: 45556,
    );
    _controlSocket = req.socket;
    
    // FOR INCOMING CONNECTIONS:
    // We DO NOT call _monitorControlSocket(req.socket) because TcpServer
    // is already listening to this socket. TcpServer will trigger 
    // onPeerDisconnected if it closes or sends DISCONNECT.
    
    _startHeartbeat(req.socket);
    
    // Start file receiver + set device name for popups
    fileTransfer.connectedDeviceName = req.deviceName;
    fileTransfer.startReceiver();
    
    _setState(ConnectionState.connected);
    debugPrint('[CONNECTION] Accepted connection from ${req.deviceName}');
  }

  void rejectPendingConnection() {
    final req = _pendingRequest;
    if (req == null) return;
    _pendingRequest = null;
    _rejectSocket(req.socket);
    debugPrint('[CONNECTION] Rejected connection from ${req.deviceName}');
    Future.microtask(() => notifyListeners());
  }

  void _rejectSocket(Socket socket) {
    try {
      socket.write('${jsonEncode({'type': 'REJECTED', 'message': 'Connection rejected'})}\n');
      Future.delayed(const Duration(milliseconds: 200), () {
        try { socket.destroy(); } catch (_) {}
      });
    } catch (_) {}
  }

  // ─── Discovery ───

  Future<void> startDiscovery(DeviceModel local) async {
    _localDevice = local;
    orchestrator.tcpServer.onPeerConnected = _onIncomingPeerConnected;
    _setState(ConnectionState.discovering);
    await orchestrator.startDiscovery(local);
  }

  void stopDiscovery() {
    orchestrator.stopDiscovery();
    if (_state == ConnectionState.discovering) {
      _state = ConnectionState.idle;
      debugPrint('[CONNECTION] State → idle');
      Future.microtask(() => notifyListeners());
    }
  }

  // ─── Outgoing connection ───

  Future<bool> connectToDevice(DeviceModel device) async {
    _setState(ConnectionState.connecting);

    orchestrator.stopDiscovery();
    if (!orchestrator.tcpServer.isRunning && _localDevice != null) {
      orchestrator.tcpServer.onPeerConnected = _onIncomingPeerConnected;
      await orchestrator.tcpServer.start(_localDevice!.port);
    }

    try {
      final socket = await Socket.connect(
        device.ip,
        device.port,
        timeout: const Duration(seconds: 5),
      );
      socket.done.catchError((_) {});
      _controlSocket = socket;

      final handshake = jsonEncode({
        'type': 'HELLO_PC',
        'device_id': _localDevice?.deviceId ?? 'unknown',
        'device_name': _localDevice?.deviceName ?? 'Unknown',
      });
      socket.write('$handshake\n');
      debugPrint('[CONNECTION] Sent HELLO_PC to ${device.deviceName}');

      final completer = Completer<bool>();
      // Listen once — we'll reuse this subscription for monitoring
      final sub = socket.listen(
        (data) {
          final msg = utf8.decode(data).trim();
          if (msg.contains('"type":"OK"') || msg.contains('"type": "OK"')) {
            if (!completer.isCompleted) completer.complete(true);
          } else if (msg.contains('"type":"REJECTED"') || msg.contains('"type": "REJECTED"')) {
            if (!completer.isCompleted) completer.complete(false);
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.complete(false);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(false);
        },
      );

      final ok = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );

      if (ok) {
        _connectedDevice = device;
        // REUSE the existing subscription — don't cancel & re-listen
        _monitorControlSocket(socket, existingSub: sub);
        _startHeartbeat(socket);
        
        // Start file receiver + set device name for popups
        fileTransfer.connectedDeviceName = device.deviceName;
        fileTransfer.startReceiver();
        
        _setState(ConnectionState.connected);
        debugPrint('[CONNECTION] Connected to ${device.deviceName}');
        return true;
      } else {
        await sub.cancel();
        socket.destroy();
        _setState(ConnectionState.disconnected);
        return false;
      }
    } catch (e) {
      debugPrint('[CONNECTION] Failed: $e');
      _setState(ConnectionState.disconnected);
      return false;
    }
  }

  void _startHeartbeat(Socket socket) {
    _heartbeatTimer?.cancel();
    _heartbeatFailures = 0;
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      try {
        socket.write('${jsonEncode({'type': 'PING'})}\n');
        _heartbeatFailures = 0; // Success
      } catch (e) {
        _heartbeatFailures++;
        debugPrint('[CONNECTION] Heartbeat failure ($_heartbeatFailures/3): $e');
        if (_heartbeatFailures >= 3) {
          _onRemoteDisconnect();
        }
      }
    });
  }

  /// Explicitly disconnect — sends DISCONNECT message to remote peer first
  void disconnect() {
    if (!isConnected && _state != ConnectionState.connecting) return;
    final wasDevice = _connectedDevice?.deviceName ?? 'Unknown';
    debugPrint('[CONNECTION] Disconnecting manually from $wasDevice...');
    
    final socket = _controlSocket;
    _controlSocket = null;
    
    if (socket != null) {
      try {
        socket.write('${jsonEncode({'type': 'DISCONNECT'})}\n');
        socket.flush().then((_) {
          socket.destroy();
        }).catchError((_) {
          socket.destroy();
        });
      } catch (_) {
        socket.destroy();
      }
    }

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _controlSocketSub?.cancel();
    _controlSocketSub = null;
    _connectedDevice = null;
    
    fileTransfer.stopReceiver();
    _setState(ConnectionState.disconnected);
  }

  void setTransferring() {
    if (_state == ConnectionState.connected) {
      _setState(ConnectionState.transferring);
    }
  }

  void setConnected() {
    if (_state == ConnectionState.transferring) {
      _setState(ConnectionState.connected);
    }
  }

  @override
  void dispose() {
    disconnect();
    orchestrator.stopDiscovery();
    super.dispose();
  }
}
