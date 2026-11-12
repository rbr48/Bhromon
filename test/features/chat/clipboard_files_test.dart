import 'package:bhromon/features/chat/data/clipboard_files.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The activity's share channel, mocked. The platform is forced to Android, where the channel
// exists, so these tests read the same on any host.

const MethodChannel _channel = MethodChannel('com.bhromon.app/share_intake');

void _mock(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    _mock((_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('reads the files the activity copied from the clipboard, in order',
      () async {
    _mock((call) async {
      expect(call.method, 'readClipboardFiles');
      return [
        {
          'name': 'photo.png',
          'sizeBytes': 2048,
          'path': '/cache/a_photo.png',
          'mimeType': 'image/png',
        },
        {
          'name': 'notes.pdf',
          'sizeBytes': 10,
          'path': '/cache/b_notes.pdf',
          'mimeType': 'application/pdf',
        },
      ];
    });

    final files = await ClipboardFiles.readClipboard();

    expect(files.map((file) => file.name), ['photo.png', 'notes.pdf']);
    expect(files.first.path, '/cache/a_photo.png');
    expect(files.first.sizeBytes, 2048);
    expect(files.first.mimeType, 'image/png');
  });

  test('an empty clipboard gives no files, so the text field pastes its text',
      () async {
    _mock((_) async => <Object?>[]);

    expect(await ClipboardFiles.readClipboard(), isEmpty);
  });

  test(
      'a file the activity could not copy keeps no path, so the chat refuses it',
      () async {
    _mock((_) async => [
          {
            'name': 'big.mp4',
            'sizeBytes': 900000000,
            'path': null,
            'mimeType': 'video/mp4'
          },
        ]);

    final files = await ClipboardFiles.readClipboard();

    expect(files.single.name, 'big.mp4');
    expect(files.single.path, isNull);
  });

  test('a platform without the channel reads nothing and calls nothing',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var called = false;
    _mock((_) async {
      called = true;
      return <Object?>[];
    });

    expect(await ClipboardFiles.readClipboard(), isEmpty);
    expect(await ClipboardFiles.copyContentUri('content://media/sticker/1'),
        isNull);
    expect(called, isFalse);
  });

  test('a failed read gives no files, rather than an error in the chat',
      () async {
    _mock((_) async => throw PlatformException(code: 'clipboard_busy'));

    expect(await ClipboardFiles.readClipboard(), isEmpty);
    expect(await ClipboardFiles.copyContentUri('content://media/sticker/1'),
        isNull);
  });

  test('copyContentUri sends the uri and returns the copied file', () async {
    _mock((call) async {
      expect(call.method, 'copyContentUri');
      expect(call.arguments, {'uri': 'content://media/sticker/1'});
      return {
        'name': 'sticker.gif',
        'sizeBytes': 300,
        'path': '/cache/c_sticker.gif',
        'mimeType': 'image/gif',
      };
    });

    final file =
        await ClipboardFiles.copyContentUri('content://media/sticker/1');

    expect(file?.name, 'sticker.gif');
    expect(file?.path, '/cache/c_sticker.gif');
    expect(file?.mimeType, 'image/gif');
  });
}
