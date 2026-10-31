// Shrinks a reel video in the browser. The web build runs the WebCodecs module
// in web/js; elsewhere the Android compressor is used and this does nothing.
export 'web_video_transcoder_stub.dart'
    if (dart.library.js_interop) 'web_video_transcoder_web.dart';
