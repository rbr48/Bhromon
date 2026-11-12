/// Lays a printable booklet out away from the screen's thread where the platform has isolates.
///
/// The layout is seconds of CPU work for one chapter, and on the UI thread it froze the app until
/// Android offered to close it. Native builds use the background isolate in the io file, which
/// reports progress and can be stopped. The web has no isolates, so it gets the stub, which lays
/// the booklet out on the page's thread.
library;

export 'study_booklet_isolate_stub.dart'
    if (dart.library.io) 'study_booklet_isolate_io.dart';
