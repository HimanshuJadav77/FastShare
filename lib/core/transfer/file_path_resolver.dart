import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

class FilePathResolver {
  static const _channel = MethodChannel('com.fastshare/file_path');

  /// Launches the native Android "Open Document" picker.
  /// Bypasses third-party plugins to avoid 4GB+ file resolution issues.
  static Future<List<({String uri, String name, int size})>?> pickNativeFiles() async {
    try {
      final List<dynamic>? results = await _channel.invokeMethod('pickFile');
      if (results == null) return null;

      return results.map((item) {
        final map = Map<String, dynamic>.from(item);
        return (
          uri: map['uri'] as String,
          name: (map['name'] as String?) ?? 'Unknown File',
          size: (map['size'] as int?) ?? 0,
        );
      }).toList();
    } catch (e) {
      debugPrint('[NATIVE-PICK] Error: $e');
      return null;
    }
  }

  /// Resolves a real filesystem path from a [PlatformFile] or a raw [uriString].
  static Future<({String path, bool isTempFile})?> resolveRealPath(
    dynamic fileOrUri,
  ) async {
    String? contentUri;
    PlatformFile? pFile;

    if (fileOrUri is PlatformFile) {
      pFile = fileOrUri;
      contentUri = pFile.identifier ?? pFile.path;
    } else if (fileOrUri is String) {
      contentUri = fileOrUri;
    }

    if (contentUri == null) return null;

    // ── 1. Try Native Path Resolution (Fastest, zero-copy) ──────────────────
    if (Platform.isAndroid) {
      try {
        final String? realPath = await _channel.invokeMethod('getRealPath', {'uri': contentUri});
        if (realPath != null && await File(realPath).exists()) {
          return (path: realPath, isTempFile: false);
        }
      } catch (e) {
        debugPrint('[RESOLVE] Native failed for $contentUri: $e');
      }
    }

    // ── 2. Handle PlatformFile specific path ────────────────────────────────
    if (pFile != null && pFile.path != null && await File(pFile.path!).exists()) {
      return (path: pFile.path!, isTempFile: false);
    }

    // ── 3. Fallback: stream-copy to temp ─────────────────────────────────────
    // Only possible if we have a PlatformFile with a read stream
    if (pFile == null) return null; 

    final stream = pFile.readStream;
    if (stream == null) return null;

    try {
      final tempDir = await getTemporaryDirectory();
      final dest = File('${tempDir.path}/${pFile.name}');
      
      // Delete any stale temp copy
      if (await dest.exists()) await dest.delete();

      final raf = await dest.open(mode: FileMode.write);
      await for (final chunk in stream) {
        await raf.writeFrom(chunk);
      }
      await raf.close();

      return (path: dest.path, isTempFile: true);
    } catch (e) {
      debugPrint('[RESOLVE] Fallback copy failed: $e');
      return null;
    }
  }
}
