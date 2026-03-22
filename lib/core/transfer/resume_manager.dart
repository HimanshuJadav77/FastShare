import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:wifi_ftp/core/data/models/transfer_model.dart';

class ResumeManager {
  Future<File> _getStateFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/transfer_state.json');
  }

  Future<void> saveState(TransferModel model) async {
    final file = await _getStateFile();
    
    Map<String, dynamic> states = {};
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) {
         states = jsonDecode(content) as Map<String, dynamic>;
      }
    }
    
    states[model.fileId] = model.toJson();
    await file.writeAsString(jsonEncode(states));
  }

  Future<TransferModel?> getState(String fileId) async {
    final file = await _getStateFile();
    if (!await file.exists()) return null;

    final content = await file.readAsString();
    if (content.isEmpty) return null;

    try {
      final states = jsonDecode(content) as Map<String, dynamic>;
      if (states.containsKey(fileId)) {
        return TransferModel.fromJson(states[fileId]);
      }
    } catch (_) {}
    
    return null;
  }
}
