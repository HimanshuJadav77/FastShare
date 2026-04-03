import 'package:flutter/foundation.dart';

enum TelemetryState { waiting, active, paused, done, error }

class TransferTelemetry {
  final double progress; // 0.0 – 1.0
  final double speedMBs;
  final String eta;
  final TelemetryState state;

  const TransferTelemetry({
    this.progress = 0.0,
    this.speedMBs = 0.0,
    this.eta = '--',
    this.state = TelemetryState.waiting,
  });

  TransferTelemetry copyWith({
    double? progress,
    double? speedMBs,
    String? eta,
    TelemetryState? state,
  }) =>
      TransferTelemetry(
        progress: progress ?? this.progress,
        speedMBs: speedMBs ?? this.speedMBs,
        eta: eta ?? this.eta,
        state: state ?? this.state,
      );

  static String formatEta(int remainingBytes, double speedBytesPerSec) {
    if (speedBytesPerSec <= 0) return '--';
    final s = remainingBytes / speedBytesPerSec;
    if (s < 60) return '${s.toStringAsFixed(0)}s';
    if (s < 3600) return '${(s / 60).toStringAsFixed(0)}m';
    return '${(s / 3600).toStringAsFixed(1)}h';
  }
}

/// Per-transfer telemetry. Uses a 2-second sliding window for speed accuracy.
/// Updated at most every 500 ms to avoid flooding the UI.
class TelemetryNotifier extends ValueNotifier<TransferTelemetry> {
  final int fileSize;
  int _bytesDone;

  // (epochMs, absoluteBytesDone)
  final List<(int, int)> _window = [];
  int _lastNotifyMs = 0;

  TelemetryNotifier({required this.fileSize, int initialBytes = 0})
      : _bytesDone = initialBytes,
        super(TransferTelemetry(
          progress: fileSize > 0 ? initialBytes / fileSize : 0.0,
        ));

  /// Called when an incremental number of bytes have arrived/been written
  /// (used only locally if not using an isolate).
  void addBytes(int count) {
    _bytesDone += count;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _window.add((nowMs, _bytesDone));

    final cutoff = nowMs - 2000;
    while (_window.isNotEmpty && _window.first.$1 < cutoff) {
      _window.removeAt(0);
    }

    double speedBps = 0;
    if (_window.length >= 2) {
      final dBytes = _window.last.$2 - _window.first.$2;
      final dMs = _window.last.$1 - _window.first.$1;
      if (dMs > 0) speedBps = dBytes * 1000 / dMs;
    }

    if (nowMs - _lastNotifyMs < 500 && _bytesDone < fileSize) return;
    _lastNotifyMs = nowMs;

    _emitTick(speedBps);
  }

  /// Extremely precise: receives exact telemetry from background isolates,
  /// completely immune to main-thread UI frame jitter.
  void updateFromIsolate(int absoluteBytes, double exactSpeedBps) {
    _bytesDone = absoluteBytes;
    _emitTick(exactSpeedBps);
  }

  void _emitTick(double speedBps) {
    final progress = fileSize > 0 ? (_bytesDone / fileSize).clamp(0.0, 1.0) : 0.0;
    value = TransferTelemetry(
      progress: progress,
      speedMBs: speedBps / (1024 * 1024),
      eta: TransferTelemetry.formatEta(fileSize - _bytesDone, speedBps),
      state: TelemetryState.active,
    );
  }

  void setState(TelemetryState s) => value = value.copyWith(state: s);

  void markDone() => value = const TransferTelemetry(
        progress: 1.0,
        speedMBs: 0,
        eta: '--',
        state: TelemetryState.done,
      );

  void markError() => value = value.copyWith(state: TelemetryState.error);
}
