// Upload limits and file types. These must match storage.rules.

const int kMaxImageBytes = 10 * 1024 * 1024; // 10 MB
const int kMaxVideoBytes = 100 * 1024 * 1024; // 100 MB
// The largest video the browser tries to shrink. A bigger file cannot be held in
// browser memory, so it is refused on the web.
const int kMaxWebVideoSourceBytes = 250 * 1024 * 1024; // 250 MB
const int kMaxReelSeconds = 180; // 3 minutes
const int kMaxPhotosPerPost = 10;
const int kMaxAudioBytes = 25 * 1024 * 1024; // 25 MB, as the media server
const int kMaxDocBytes =
    50 * 1024 * 1024; // 50 MB, matching media-server MAX_DOC_BYTES

const Map<String, String> _imageTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'heif': 'image/heif',
};

const Map<String, String> _videoTypes = {
  'mp4': 'video/mp4',
  'm4v': 'video/x-m4v',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  '3gp': 'video/3gpp',
  'mkv': 'video/x-matroska',
};

const Map<String, String> _audioTypes = {
  'm4a': 'audio/mp4',
  'mp3': 'audio/mpeg',
  'aac': 'audio/aac',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'opus': 'audio/opus',
};

const Map<String, String> _docTypes = {
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'zip': 'application/zip',
};

String _extension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1).toLowerCase();
}

/// The content type to upload a photo with, or null when the type is not
/// allowed (for example a PDF or an unknown extension).
String? imageContentType(String fileName) => _imageTypes[_extension(fileName)];

/// The content type to upload a video with, or null when not allowed.
String? videoContentType(String fileName) => _videoTypes[_extension(fileName)];

/// Whether a video named [fileName] can be stored. These are the containers the
/// media server keeps (VIDEO_EXTENSIONS in media-server/main.py). A name with no
/// extension is allowed, as it always was, and is stored as an mp4.
bool isSupportedVideoName(String fileName) {
  final ext = _extension(fileName);
  return ext.isEmpty || _videoTypes.containsKey(ext);
}

/// The content type to upload a voice note with, or null when not allowed.
String? audioContentType(String fileName) => _audioTypes[_extension(fileName)];

/// The content type to upload a document or file with, or null when not allowed.
String? docContentType(String fileName) => _docTypes[_extension(fileName)];

/// Whether a document named [fileName] is supported.
bool isSupportedDocName(String fileName) {
  final ext = _extension(fileName);
  return ext.isNotEmpty && _docTypes.containsKey(ext);
}

/// Extension to store a file under. Falls back to [fallback] when the name has none.
String storedExtension(String fileName, String fallback) {
  final ext = _extension(fileName);
  return ext.isEmpty ? fallback : ext;
}

/// Human-readable size for error messages, for example "12.4 MB".
String formatMegabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
