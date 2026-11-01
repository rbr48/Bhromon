import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Downloads a binary payload directly in the browser via an object URL blob,
/// avoiding Chrome mobile data-URL limits and CORS sharing restrictions.
Future<void> downloadWebFile(Uint8List bytes, String filename) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..target = '_blank'
    ..rel = 'noopener noreferrer'
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  // Keep the blob URL alive for 60 seconds to ensure the browser download starts
  // and finishes without being prematurely destroyed.
  Future<void>.delayed(const Duration(seconds: 60), () {
    anchor.remove();
    web.URL.revokeObjectURL(url);
  });
}
