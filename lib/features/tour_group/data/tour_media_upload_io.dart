import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

/// Starts an upload from disk. Large videos are streamed, not loaded into memory.
Future<UploadTask> startTourMediaUpload(
  Reference ref,
  XFile file,
  SettableMetadata metadata,
) async {
  return ref.putFile(File(file.path), metadata);
}

/// A controller for a file the user just picked, so they can preview it.
VideoPlayerController createLocalVideoController(XFile file) {
  return VideoPlayerController.file(File(file.path));
}
