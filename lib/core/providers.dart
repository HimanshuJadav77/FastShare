import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wifi_ftp/core/networking/app_connection.dart';
import 'package:wifi_ftp/core/transfer/transfer_queue.dart';
import 'package:wifi_ftp/core/transfer/transfer_history.dart';

export 'package:wifi_ftp/core/providers/theme_provider.dart';
export 'package:wifi_ftp/core/providers/settings_provider.dart';

// Global singleton connection — reactive across the entire app
final appConnectionProvider = ChangeNotifierProvider((ref) => AppConnection());

// Global transfer queue — reactive across the entire app
final transferQueueProvider = ChangeNotifierProvider((ref) => TransferQueue());

// Persistent transfer history
final transferHistoryProvider = ChangeNotifierProvider((ref) => TransferHistory());
