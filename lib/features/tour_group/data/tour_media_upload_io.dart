import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

/// A controller for a file the user just picked, so they can preview it.
VideoPlayerController createLocalVideoController(XFile file) {
  return VideoPlayerController.file(File(file.path));
}
