import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wifi_ftp/core/networking/app_connection.dart';
import 'package:wifi_ftp/core/transfer/transfer_history.dart';

export 'package:wifi_ftp/core/providers/theme_provider.dart';
export 'package:wifi_ftp/core/providers/settings_provider.dart';
export 'package:wifi_ftp/core/providers/transfer_queue_provider.dart';

// Global singleton connection — reactive across the entire app
final appConnectionProvider = Provider((ref) {
  final conn = AppConnection();
  ref.onDispose(() => conn.dispose());
  return conn;
});

// Persistent transfer history
final transferHistoryProvider = NotifierProvider<TransferHistoryNotifier, List<TransferRecord>>(() {
  return TransferHistoryNotifier();
});

enum TransferFilter { all, pending, completed, cancelled }

final transferFilterProvider = NotifierProvider<TransferFilterNotifier, TransferFilter>(() {
  return TransferFilterNotifier();
});

class TransferFilterNotifier extends Notifier<TransferFilter> {
  @override
  TransferFilter build() => TransferFilter.all;
  void setFilter(TransferFilter f) => state = f;
}
