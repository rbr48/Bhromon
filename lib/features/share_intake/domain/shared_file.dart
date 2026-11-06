import 'package:bhromon/features/tour_group/domain/services/media_rules.dart';

/// A file another app shared into Bhromon. [path] is a copy the app can read. It is
/// null when the file was not copied, for example because it was too large.
class SharedFile {
  const SharedFile({
    required this.name,
    required this.sizeBytes,
    this.path,
    this.mimeType,
  });

  /// Reads one entry the Android side returns.
  factory SharedFile.fromMap(Map<Object?, Object?> map) {
    return SharedFile(
      name: map['name'] as String? ?? 'file',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? -1,
      path: map['path'] as String?,
      mimeType: map['mimeType'] as String?,
    );
  }

  final String name;

  /// The size in bytes, or -1 when it is not known.
  final int sizeBytes;
  final String? path;
  final String? mimeType;
}

/// The kinds of file a destination can receive. They follow the upload rules in
/// media_rules.dart, which match the media server.
enum SharedFileKind { image, video, audio, document }

/// Why a shared file cannot be sent.
enum SharedFileIssue { unsupported, tooLarge, unreadable, empty }

/// The kind of file [name] is, or null when the app does not accept its extension.
SharedFileKind? sharedFileKind(String name) {
  if (imageContentType(name) != null) return SharedFileKind.image;
  if (videoContentType(name) != null) return SharedFileKind.video;
  if (audioContentType(name) != null) return SharedFileKind.audio;
  if (isSupportedDocName(name)) return SharedFileKind.document;
  return null;
}

/// The largest file of [kind] that can be sent.
int maxBytesFor(SharedFileKind kind) => switch (kind) {
      SharedFileKind.image => kMaxImageBytes,
      SharedFileKind.video => kMaxVideoBytes,
      SharedFileKind.audio => kMaxAudioBytes,
      SharedFileKind.document => kMaxDocBytes,
    };

/// Why [file] cannot be sent, or null when it can. The checks run in this order: the
/// type, the size, whether it was copied, and whether it is empty.
SharedFileIssue? sharedFileIssue(SharedFile file) {
  final kind = sharedFileKind(file.name);
  if (kind == null) return SharedFileIssue.unsupported;
  if (file.sizeBytes > maxBytesFor(kind)) return SharedFileIssue.tooLarge;
  if (file.path == null) return SharedFileIssue.unreadable;
  if (file.sizeBytes == 0) return SharedFileIssue.empty;
  return null;
}
