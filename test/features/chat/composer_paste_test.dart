import 'package:bhromon/features/chat/presentation/widgets/composer_paste.dart';
import 'package:bhromon/features/share_intake/domain/shared_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The keyboard's inserted content, answered by the activity's share channel. The platform is
// forced to Android, where the channel exists, so these tests read the same on any host.

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

  test('a sticker or GIF the keyboard inserts is copied, then handed over',
      () async {
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
    final handed = <SharedFile>[];
    var failed = false;
    final paste = ComposerPaste(
      onFiles: handed.addAll,
      onFailed: () => failed = true,
    );

    paste.insertion.onContentInserted(const KeyboardInsertedContent(
      mimeType: 'image/gif',
      uri: 'content://media/sticker/1',
    ));
    await pumpEventQueue();

    expect(handed.map((file) => file.name), ['sticker.gif']);
    expect(failed, isFalse);
  });

  test(
      'keyboard content that cannot be copied is reported, and nothing is handed over',
      () async {
    _mock((_) async => null);
    final handed = <SharedFile>[];
    var failed = false;
    final paste = ComposerPaste(
      onFiles: handed.addAll,
      onFailed: () => failed = true,
    );

    paste.insertion.onContentInserted(const KeyboardInsertedContent(
      mimeType: 'image/png',
      uri: 'content://media/sticker/2',
    ));
    await pumpEventQueue();

    expect(failed, isTrue);
    expect(handed, isEmpty);
  });

  test('the keyboard may insert the image types a sticker or GIF comes as', () {
    final paste = ComposerPaste(onFiles: (_) {}, onFailed: () {});

    expect(
      paste.insertion.allowedMimeTypes,
      containsAll(['image/gif', 'image/png', 'image/webp']),
    );
  });
}
