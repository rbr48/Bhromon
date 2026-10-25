import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

/// Starts an upload on web, where the picked file is a blob with no disk path.
Future<UploadTask> startTourMediaUpload(
  Reference ref,
  XFile file,
  SettableMetadata metadata,
) async {
  final bytes = await file.readAsBytes();
  return ref.putData(bytes, metadata);
}

/// A controller for a file the user just picked. On web the picker gives a blob URL.
VideoPlayerController createLocalVideoController(XFile file) {
  return VideoPlayerController.networkUrl(Uri.parse(file.path));
}
