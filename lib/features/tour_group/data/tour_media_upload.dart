// Uploads a picked file to Firebase Storage without touching dart:io on web.
// Mobile streams the file from disk; web reads the bytes first.
export 'tour_media_upload_web.dart'
    if (dart.library.io) 'tour_media_upload_io.dart';
