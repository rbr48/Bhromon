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
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
