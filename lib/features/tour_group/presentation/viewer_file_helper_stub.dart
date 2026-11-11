import 'dart:typed_data';

/// Stub for web platforms where `dart:io` is unavailable.
Future<String?> saveTempBytes(Uint8List bytes, String fileName) async => null;

/// Stub for web platforms where `dart:io` is unavailable.
Future<String?> saveTempText(String text, String fileName) async => null;

/// Stub for web platforms where `dart:io` is unavailable.
Future<Uint8List?> readLocalBytes(String filePath) async => null;

/// Stub for web platforms where `dart:io` is unavailable.
bool fileExists(String filePath) => false;
