import 'package:bhromon/features/share_intake/domain/shared_file.dart';

/// Files pasted into the chat box, or inserted from the keyboard. A pasted item often has no
/// usable name, such as a screenshot copied from an editor, so it takes its extension from its
/// type. Each file is then routed the way the attach button routes the same kind of file.

/// The extension for a type a paste can carry, or null when the app has no extension for it.
/// A type with no extension is refused when the file is checked, like any other unsupported file.
String? extensionForMimeType(String? mimeType) {
  final type = mimeType?.split(';').first.trim().toLowerCase();
  return switch (type) {
    'image/jpeg' || 'image/jpg' => 'jpg',
    'image/png' => 'png',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'video/mp4' => 'mp4',
    'video/quicktime' => 'mov',
    'video/webm' => 'webm',
    'audio/mpeg' => 'mp3',
    'audio/mp4' || 'audio/x-m4a' => 'm4a',
    'audio/ogg' => 'ogg',
    'application/pdf' => 'pdf',
    'text/plain' => 'txt',
    'text/csv' => 'csv',
    'application/msword' => 'doc',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
      'docx',
    'application/vnd.ms-excel' => 'xls',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' =>
      'xlsx',
    'application/vnd.ms-powerpoint' => 'ppt',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
      'pptx',
    _ => null,
  };
}

/// [file] with a name the app accepts. A name that already has a supported extension is kept
/// as it is. Otherwise the extension comes from the file's type, and a blank name becomes
/// "pasted".
SharedFile withPastedName(SharedFile file) {
  if (sharedFileKind(file.name) != null) return file;
  final extension = extensionForMimeType(file.mimeType);
  if (extension == null) return file;
  final base = file.name.trim().isEmpty ? 'pasted' : file.name.trim();
  return SharedFile(
    name: '$base.$extension',
    sizeBytes: file.sizeBytes,
    path: file.path,
    mimeType: file.mimeType,
  );
}

/// Where a pasted file is sent. Images and videos go through the caption screen, as a picked
/// image does. Documents and voice notes are sent as the attach sheet sends them.
enum PastedRoute { image, video, document }

/// The route for [file], or null when the app does not accept its type.
PastedRoute? pastedRouteOf(SharedFile file) {
  return switch (sharedFileKind(file.name)) {
    SharedFileKind.image => PastedRoute.image,
    SharedFileKind.video => PastedRoute.video,
    SharedFileKind.audio || SharedFileKind.document => PastedRoute.document,
    null => null,
  };
}
