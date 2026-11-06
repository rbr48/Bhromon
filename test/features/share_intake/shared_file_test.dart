import 'package:bhromon/features/share_intake/domain/shared_file.dart';
import 'package:flutter_test/flutter_test.dart';

const _mb = 1024 * 1024;

SharedFile _file(
  String name, {
  int size = 1000,
  String? path = '/cache/shared/copy',
}) =>
    SharedFile(name: name, sizeBytes: size, path: path);

void main() {
  group('sharedFileKind', () {
    test('sorts each accepted extension into its kind', () {
      expect(sharedFileKind('photo.JPG'), SharedFileKind.image);
      expect(sharedFileKind('clip.mp4'), SharedFileKind.video);
      expect(sharedFileKind('note.m4a'), SharedFileKind.audio);
      expect(sharedFileKind('report.pdf'), SharedFileKind.document);
      expect(sharedFileKind('sheet.csv'), SharedFileKind.document);
      expect(sharedFileKind('bundle.zip'), SharedFileKind.document);
    });

    test('refuses an extension no destination takes', () {
      expect(sharedFileKind('app.apk'), isNull);
      expect(sharedFileKind('script.exe'), isNull);
      expect(sharedFileKind('noextension'), isNull);
    });
  });

  group('maxBytesFor', () {
    test('uses the limit the media server enforces for each kind', () {
      expect(maxBytesFor(SharedFileKind.image), 10 * _mb);
      expect(maxBytesFor(SharedFileKind.video), 100 * _mb);
      expect(maxBytesFor(SharedFileKind.audio), 25 * _mb);
      expect(maxBytesFor(SharedFileKind.document), 50 * _mb);
    });
  });

  group('sharedFileIssue', () {
    test('passes a file of an accepted kind within its limit', () {
      expect(sharedFileIssue(_file('a.jpg')), isNull);
      expect(sharedFileIssue(_file('a.zip', size: 50 * _mb)), isNull);
    });

    test('reports an unsupported type before anything else', () {
      expect(
        sharedFileIssue(_file('a.exe', size: 0, path: null)),
        SharedFileIssue.unsupported,
      );
    });

    test('reports a file over the limit of its kind as too large', () {
      expect(
        sharedFileIssue(_file('a.jpg', size: 11 * _mb)),
        SharedFileIssue.tooLarge,
      );
      expect(
        sharedFileIssue(_file('a.zip', size: 51 * _mb)),
        SharedFileIssue.tooLarge,
      );
    });

    test('allows a video up to 100 MB, which is more than an image', () {
      expect(sharedFileIssue(_file('a.mp4', size: 60 * _mb)), isNull);
    });

    test('checks the size before whether the file was copied', () {
      expect(
        sharedFileIssue(_file('a.jpg', size: 20 * _mb, path: null)),
        SharedFileIssue.tooLarge,
      );
    });

    test('reports a file that was not copied as unreadable', () {
      expect(
        sharedFileIssue(_file('a.jpg', path: null)),
        SharedFileIssue.unreadable,
      );
    });

    test('reports an empty file', () {
      expect(sharedFileIssue(_file('a.jpg', size: 0)), SharedFileIssue.empty);
    });

    test('lets an unknown size through, because the uploader checks the bytes',
        () {
      expect(sharedFileIssue(_file('a.jpg', size: -1)), isNull);
    });
  });

  group('SharedFile.fromMap', () {
    test('reads the entry the Android side returns', () {
      final file = SharedFile.fromMap({
        'name': 'a.pdf',
        'sizeBytes': 12,
        'path': '/cache/a.pdf',
        'mimeType': 'application/pdf',
      });
      expect(file.name, 'a.pdf');
      expect(file.sizeBytes, 12);
      expect(file.path, '/cache/a.pdf');
      expect(file.mimeType, 'application/pdf');
    });

    test('falls back to a generic name and an unknown size', () {
      final file = SharedFile.fromMap(const {});
      expect(file.name, 'file');
      expect(file.sizeBytes, -1);
      expect(file.path, isNull);
    });
  });
}
