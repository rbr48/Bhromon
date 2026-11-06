import 'package:image_picker/image_picker.dart';

import '../../tour_group/data/tour_channel_repository.dart';
import '../../tour_group/data/tour_media_uploader.dart';
import '../../tour_group/domain/models/channel_models.dart';
import '../domain/share_plan.dart';
import '../domain/shared_file.dart';

/// Sends shared files to a group channel. Each file is uploaded in turn, and the files
/// of one message are posted together. The channel repository checks each file again
/// as it uploads, so a file that slipped past the sheet is still refused.
class ChannelShareSender {
  ChannelShareSender({required TourChannelRepository repository})
      : _repo = repository;

  final TourChannelRepository _repo;

  /// Sends [files] to the channel. [onProgress] reports how many have been sent.
  Future<void> send({
    required String tourId,
    required String channelId,
    required List<SharedFile> files,
    void Function(int sent, int total)? onProgress,
  }) async {
    var sent = 0;
    for (final batch in planChannelMessages(files)) {
      final uploads = <TourMediaUpload>[];
      try {
        final attachments = <ChannelAttachment>[];
        for (final file in batch) {
          final upload = await _startUpload(tourId, file);
          uploads.add(upload);
          final url = await upload.finish();
          attachments.add(_attachmentFor(file, url));
        }
        await _repo.sendMessage(
          tourId,
          channelId,
          text: '',
          attachments: attachments,
        );
      } catch (_) {
        // Remove what already reached the server, so nothing is left unposted.
        for (final upload in uploads) {
          await upload.discard();
        }
        rethrow;
      }
      sent += batch.length;
      onProgress?.call(sent, files.length);
    }
  }

  Future<TourMediaUpload> _startUpload(String tourId, SharedFile file) {
    final path = file.path;
    final kind = sharedFileKind(file.name);
    if (path == null || kind == null) {
      throw StateError('The file was not checked before sending: ${file.name}');
    }
    // The name carries the extension the uploader checks, so it is passed on.
    final xfile = XFile(path, name: file.name);
    return switch (kind) {
      SharedFileKind.image =>
        _repo.startAttachment(tourId, xfile, isVideo: false),
      SharedFileKind.video =>
        _repo.startAttachment(tourId, xfile, isVideo: true),
      SharedFileKind.document =>
        _repo.startAttachment(tourId, xfile, isVideo: false, isDocument: true),
      SharedFileKind.audio => _repo.startVoice(tourId, xfile),
    };
  }

  ChannelAttachment _attachmentFor(SharedFile file, String url) {
    final kind = sharedFileKind(file.name);
    return switch (kind) {
      SharedFileKind.video => ChannelAttachment(url: url, isVideo: true),
      SharedFileKind.audio => ChannelAttachment(url: url, isAudio: true),
      SharedFileKind.document => ChannelAttachment(
          url: url,
          isFile: true,
          fileName: file.name,
          fileSizeBytes: file.sizeBytes >= 0 ? file.sizeBytes : null,
        ),
      _ => ChannelAttachment(url: url),
    };
  }
}
