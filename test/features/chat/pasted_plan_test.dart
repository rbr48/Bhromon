import 'package:bhromon/features/chat/domain/pasted_files.dart';
import 'package:bhromon/features/share_intake/domain/shared_file.dart';
import 'package:flutter_test/flutter_test.dart';

SharedFile _file(
  String name, {
  int size = 1000,
  String? path = '/cache/x',
  String? mimeType,
}) =>
    SharedFile(name: name, sizeBytes: size, path: path, mimeType: mimeType);

void main() {
  group('pastedFilesPlan', () {
    test('keeps the files the app can send, in the order they were pasted', () {
      final plan = pastedFilesPlan([
        _file('a.jpg'),
        _file('notes.pdf'),
        _file('clip.mp4'),
      ]);

      expect(plan.sendable.map((file) => file.name),
          ['a.jpg', 'notes.pdf', 'clip.mp4']);
      expect(plan.refused, 0);
    });

    test('counts the files it leaves out, and the rest still go', () {
      final plan = pastedFilesPlan([
        _file('setup.exe'),
        _file('empty.pdf', size: 0),
        _file('big.mp4', size: 900 * 1024 * 1024),
        _file('kept.png'),
        _file('unread.pdf', path: null),
      ]);

      expect(plan.sendable.map((file) => file.name), ['kept.png']);
      expect(plan.refused, 4);
    });

    test('names a pasted file from its type, so it is sent with an extension',
        () {
      final plan = pastedFilesPlan([_file('', mimeType: 'image/png')]);

      expect(plan.sendable.single.name, 'pasted.png');
      expect(plan.refused, 0);
    });

    test('an empty paste has nothing to send and nothing to refuse', () {
      final plan = pastedFilesPlan(const []);

      expect(plan.sendable, isEmpty);
      expect(plan.refused, 0);
    });
  });

  group('pastedFileSizeLabel', () {
    test('shows bytes, kilobytes and megabytes', () {
      expect(pastedFileSizeLabel(0), '0 B');
      expect(pastedFileSizeLabel(1023), '1023 B');
      expect(pastedFileSizeLabel(2048), '2 KB');
      expect(pastedFileSizeLabel(3 * 1024 * 1024), '3.0 MB');
    });

    test('shows nothing when the size is not known', () {
      expect(pastedFileSizeLabel(-1), '');
    });
  });
}
