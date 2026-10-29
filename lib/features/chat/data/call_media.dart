import '../../../core/utils/app_logger.dart';

/// Local media for a call or a voice room. [hasVideo] says whether the camera
/// is part of it.
class CallMedia<T> {
  const CallMedia({required this.stream, required this.hasVideo});

  final T stream;

  /// False when the camera was not asked for, or could not be opened.
  final bool hasVideo;
}

/// Constraints for the microphone and, when [video] is set, the front camera.
Map<String, dynamic> callMediaConstraints({required bool video}) {
  return <String, dynamic>{
    'audio': {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
    },
    'video': video
        ? <String, dynamic>{
            'facingMode': 'user',
            'width': {'ideal': 640},
            'height': {'ideal': 480},
            'frameRate': {'ideal': 30},
          }
        : false,
  };
}

/// Opens the microphone, and the camera when [wantVideo] is set.
///
/// A camera that cannot be opened (none on the device, in use by another app,
/// or refused by the browser) does not end the call. The call carries on with
/// audio, and [CallMedia.hasVideo] is false. A microphone that cannot be opened
/// is an error, so it is thrown.
Future<CallMedia<T>> captureCallMedia<T>({
  required bool wantVideo,
  required Future<T> Function(Map<String, dynamic> constraints) getUserMedia,
}) async {
  if (wantVideo) {
    try {
      final stream = await getUserMedia(callMediaConstraints(video: true));
      return CallMedia(stream: stream, hasVideo: true);
    } catch (e) {
      logWarning('Camera unavailable, continuing with audio only', e);
    }
  }
  final stream = await getUserMedia(callMediaConstraints(video: false));
  return CallMedia(stream: stream, hasVideo: false);
}
