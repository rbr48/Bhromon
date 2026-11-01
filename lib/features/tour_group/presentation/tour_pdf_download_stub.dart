import 'dart:typed_data';

/// Stub for non-web platforms. Web file downloads are handled via
/// [tour_pdf_download_web.dart].
Future<void> downloadWebFile(Uint8List bytes, String filename) async {
  throw UnsupportedError('downloadWebFile is only supported on web');
}
