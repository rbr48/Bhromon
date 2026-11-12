import 'package:bhromon/features/share_intake/domain/shared_file.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/channel_composer.dart';
import 'package:flutter_test/flutter_test.dart';

SharedFile _file(String name, {int size = 2048, String? path = '/cache'}) {
  return SharedFile(
    name: name,
    sizeBytes: size,
    path: path == null ? null : '$path/$name',
    mimeType: null,
  );
}

void main() {
  group('pendingAttachmentFor', () {
    test('a photo is a photo attachment, with its path', () {
      final pending = pendingAttachmentFor(_file('a.jpg'));

      expect(pending.isVideo, isFalse);
      expect(pending.isDocument, isFalse);
      expect(pending.isAudio, isFalse);
      expect(pending.file.path, '/cache/a.jpg');
    });

    test('a video is a video attachment', () {
      final pending = pendingAttachmentFor(_file('clip.mp4'));

      expect(pending.isVideo, isTrue);
      expect(pending.isDocument, isFalse);
    });

    test('a voice note is an audio attachment', () {
      final pending = pendingAttachmentFor(_file('voice.m4a'));

      expect(pending.isAudio, isTrue);
      expect(pending.isVideo, isFalse);
    });

    test('a document keeps its size, for the message to show', () {
      final pending = pendingAttachmentFor(_file('notes.pdf', size: 5000));

      expect(pending.isDocument, isTrue);
      expect(pending.fileSizeBytes, 5000);
    });

    test('a file that was not copied cannot be sent', () {
      expect(
        () => pendingAttachmentFor(_file('a.jpg', path: null)),
        throwsStateError,
      );
    });

    test('a file of a type the app does not take cannot be sent', () {
      expect(
        () => pendingAttachmentFor(_file('setup.exe')),
        throwsStateError,
      );
    });
  });
}
