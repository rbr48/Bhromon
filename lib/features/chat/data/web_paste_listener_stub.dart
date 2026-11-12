import 'package:bhromon/features/share_intake/domain/shared_file.dart';

/// Outside the web there are no paste events, so nothing is listened for. The returned function
/// stops listening, and here it does nothing.
void Function() attachWebPasteListener({
  required bool Function() accept,
  required void Function(List<SharedFile> files) onFiles,
}) {
  return () {};
}

/// Object URLs exist only on the web, so there is nothing to free here.
void releasePastedFiles(List<SharedFile> files) {}
