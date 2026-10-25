import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Starts an upload from disk. Large videos are streamed, not loaded into memory.
Future<UploadTask> startTourMediaUpload(
  Reference ref,
  XFile file,
  SettableMetadata metadata,
) async {
  return ref.putFile(File(file.path), metadata);
}
