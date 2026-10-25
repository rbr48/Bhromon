// Platform-specific upload and preview helpers. dart:io is only used on
// mobile and desktop; web uses blobs and bytes.
export 'tour_media_upload_web.dart'
    if (dart.library.io) 'tour_media_upload_io.dart';
