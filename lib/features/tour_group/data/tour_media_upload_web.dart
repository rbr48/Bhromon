import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

/// A controller for a file the user just picked. On web the picker gives a blob URL.
VideoPlayerController createLocalVideoController(XFile file) {
  return VideoPlayerController.networkUrl(Uri.parse(file.path));
}
