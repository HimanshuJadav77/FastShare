import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wifi_ftp/core/transfer/transfer_queue.dart';

// Provides the singleton TransferQueue
final transferQueueProvider = NotifierProvider<TransferQueueNotifier, List<TransferItem>>(() {
  return TransferQueueNotifier();
});

// A provider to easily access active transfers, etc. if needed
final activeTransfersProvider = Provider<List<TransferItem>>((ref) {
  final state = ref.watch(transferQueueProvider);
  return state.where((i) => i.status == TransferItemStatus.transferring).toList();
});
