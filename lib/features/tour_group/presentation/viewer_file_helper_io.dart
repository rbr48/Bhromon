import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../../../core/utils/app_logger.dart';

/// Saves binary bytes into a temporary local file on mobile/desktop.
Future<String?> saveTempBytes(Uint8List bytes, String fileName) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (e, st) {
    logWarning('[ViewerFileHelper] Failed to save temp bytes', e, st);
    return null;
  }
}

/// Saves text into a temporary local file on mobile/desktop.
Future<String?> saveTempText(String text, String fileName) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsString(text, flush: true);
    return file.path;
  } catch (e, st) {
    logWarning('[ViewerFileHelper] Failed to save temp text', e, st);
    return null;
  }
}

/// Reads binary bytes from a local file.
Future<Uint8List?> readLocalBytes(String filePath) async {
  try {
    final file = File(filePath);
    if (file.existsSync()) {
      return await file.readAsBytes();
    }
  } catch (e, st) {
    logWarning('[ViewerFileHelper] Failed to read local bytes', e, st);
  }
  return null;
}

/// Checks whether a local file exists.
bool fileExists(String filePath) {
  try {
    return File(filePath).existsSync();
  } catch (_) {
    return false;
  }
}
