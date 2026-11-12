import 'package:bhromon/features/chat/domain/pasted_files.dart';
import 'package:bhromon/features/share_intake/domain/shared_file.dart';
import 'package:flutter_test/flutter_test.dart';

SharedFile _file(String name, {String? mimeType}) => SharedFile(
      name: name,
      sizeBytes: 1000,
      path: '/cache/$name',
      mimeType: mimeType,
    );

void main() {
  group('extensionForMimeType', () {
    test('gives the extension for the types a paste carries', () {
      expect(extensionForMimeType('image/png'), 'png');
      expect(extensionForMimeType('image/jpeg'), 'jpg');
      expect(extensionForMimeType('video/mp4'), 'mp4');
      expect(extensionForMimeType('application/pdf'), 'pdf');
    });

    test('ignores parameters and letter case', () {
      expect(extensionForMimeType('IMAGE/PNG; charset=binary'), 'png');
    });

    test('gives none for a missing type or one the app has no extension for',
        () {
      expect(extensionForMimeType(null), isNull);
      expect(extensionForMimeType('application/x-unknown'), isNull);
    });
  });

  group('withPastedName', () {
    test('keeps a name the app already accepts', () {
      final file = withPastedName(_file('holiday.jpg', mimeType: 'image/png'));

      expect(file.name, 'holiday.jpg');
    });

    test('takes the extension from the type when the name has none', () {
      final file = withPastedName(_file('screenshot', mimeType: 'image/png'));

      expect(file.name, 'screenshot.png');
    });

    test('names a blank paste "pasted", and keeps its type and size', () {
      final file = withPastedName(_file('', mimeType: 'video/mp4'));

      expect(file.name, 'pasted.mp4');
      expect(file.mimeType, 'video/mp4');
      expect(file.sizeBytes, 1000);
    });

    test('leaves a file unchanged when its type has no extension', () {
      final file =
          withPastedName(_file('clip', mimeType: 'application/x-unknown'));

      expect(file.name, 'clip');
    });
  });

  group('pastedRouteOf', () {
    test('sends images and videos to the caption screen', () {
      expect(pastedRouteOf(_file('a.jpg')), PastedRoute.image);
      expect(pastedRouteOf(_file('clip.mp4')), PastedRoute.video);
    });

    test('sends documents and voice notes the way the attach sheet does', () {
      expect(pastedRouteOf(_file('notes.pdf')), PastedRoute.document);
      expect(pastedRouteOf(_file('voice.m4a')), PastedRoute.document);
    });

    test('gives no route for a type the app does not accept', () {
      expect(pastedRouteOf(_file('setup.exe')), isNull);
    });
  });
}
