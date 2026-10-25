// Upload limits and file types. These must match storage.rules.

const int kMaxImageBytes = 10 * 1024 * 1024; // 10 MB
const int kMaxVideoBytes = 100 * 1024 * 1024; // 100 MB
const int kMaxReelSeconds = 180; // 3 minutes
const int kMaxPhotosPerPost = 10;

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

/// Extension to store a file under. Falls back to [fallback] when the name has none.
String storedExtension(String fileName, String fallback) {
  final ext = _extension(fileName);
  return ext.isEmpty ? fallback : ext;
}

/// Human-readable size for error messages, for example "12.4 MB".
String formatMegabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
