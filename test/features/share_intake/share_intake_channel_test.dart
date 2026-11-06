import 'package:bhromon/features/share_intake/data/share_intake_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shares the Android side holds. The app takes them once, in a single call.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.bhromon.app/share_intake');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void answerWith(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  test('takes nothing on a platform without a share target', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var asked = false;
    answerWith((_) async {
      asked = true;
      return <Object?>[];
    });

    final batch = await ShareIntakeChannel.instance.takePending();

    expect(ShareIntakeChannel.instance.supported, isFalse);
    expect(batch.isEmpty, isTrue);
    expect(asked, isFalse);
  });

  test('turns the native entries into files and a text flag', () async {
    String? method;
    answerWith((call) async {
      method = call.method;
      return <Object?>[
        {
          'name': 'notes.pdf',
          'sizeBytes': 12,
          'path': '/cache/shared/notes.pdf',
          'mimeType': 'application/pdf',
        },
        {'text': 'a link'},
      ];
    });

    final batch = await ShareIntakeChannel.instance.takePending();

    expect(method, 'takePendingShares');
    expect(batch.files.map((file) => file.name), ['notes.pdf']);
    expect(batch.files.single.path, '/cache/shared/notes.pdf');
    expect(batch.hasText, isTrue);
    expect(batch.isEmpty, isFalse);
  });

  test('is empty when nothing is pending', () async {
    answerWith((_) async => <Object?>[]);

    final batch = await ShareIntakeChannel.instance.takePending();

    expect(batch.isEmpty, isTrue);
  });

  test('is empty when the native side refuses', () async {
    answerWith((_) async {
      throw PlatformException(code: 'unavailable', message: 'busy');
    });

    final batch = await ShareIntakeChannel.instance.takePending();

    expect(batch.isEmpty, isTrue);
  });

  test('is empty when the share channel is not registered', () async {
    // No handler is set, so the platform reports a missing plugin.
    final batch = await ShareIntakeChannel.instance.takePending();

    expect(batch.isEmpty, isTrue);
  });

  test('a batch with only text is not empty, so the user hears about it', () {
    const batch = ShareBatch(hasText: true);

    expect(batch.files, isEmpty);
    expect(batch.isEmpty, isFalse);
  });
}
