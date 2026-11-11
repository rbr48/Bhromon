import 'dart:typed_data';

/// Stub for non-web platforms. Web file downloads are handled via
/// [tour_pdf_download_web.dart].
Future<void> downloadWebFile(
  Uint8List bytes,
  String filename, {
  String mimeType = 'application/pdf',
}) async {
  throw UnsupportedError('downloadWebFile is only supported on web');
}

/// Stub for non-web platforms. Web blob opening is handled via
/// [tour_pdf_download_web.dart].
Future<void> openWebBlob(
  Uint8List bytes, {
  String mimeType = 'application/pdf',
  String? filename,
}) async {
  throw UnsupportedError('openWebBlob is only supported on web');
}
