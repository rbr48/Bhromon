// Listens for files pasted into the page. Only the web has paste events, so the web build reads
// them from the browser and every other build gets a listener that does nothing.
export 'web_paste_listener_stub.dart'
    if (dart.library.js_interop) 'web_paste_listener_web.dart';
