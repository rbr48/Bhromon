import 'dart:js_interop';

import 'package:bhromon/features/share_intake/domain/shared_file.dart';
import 'package:web/web.dart' as web;

/// Listens for paste events on the page. When [accept] says the paste belongs to the chat box
/// and the clipboard holds files, the browser's own paste is stopped and [onFiles] receives the
/// files. Each file is given as an object URL, which is how the image picker gives files on the
/// web, so the caption screen and the upload read it the same way. Text is left to the browser.
///
/// Returns the function that stops listening.
void Function() attachWebPasteListener({
  required bool Function() accept,
  required void Function(List<SharedFile> files) onFiles,
}) {
  void handlePaste(web.Event event) {
    final clipboard = (event as web.ClipboardEvent).clipboardData;
    final files = clipboard?.files;
    if (files == null || files.length == 0) return;
    if (!accept()) return;
    event.preventDefault();
    final pasted = <SharedFile>[];
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null) continue;
      pasted.add(SharedFile(
        name: file.name,
        sizeBytes: file.size,
        path: web.URL.createObjectURL(file),
        mimeType: file.type,
      ));
    }
    if (pasted.isNotEmpty) onFiles(pasted);
  }

  final listener = handlePaste.toJS;
  web.document.addEventListener('paste', listener);
  return () => web.document.removeEventListener('paste', listener);
}

/// Frees the object URLs of pasted files once they have been sent or set aside. A file whose path
/// is not an object URL, such as one the clipboard copied into the app's cache, is left alone.
void releasePastedFiles(List<SharedFile> files) {
  for (final file in files) {
    final path = file.path;
    if (path != null && path.startsWith('blob:')) {
      web.URL.revokeObjectURL(path);
    }
  }
}
