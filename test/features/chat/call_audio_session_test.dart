import 'package:bhromon/core/audio/call_audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The loudspeaker request goes to the phone's audio manager on Android, and the answer
/// says whether the route took.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.bhromon.app/call_audio');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('asks the phone for the loudspeaker and reports that it took', () async {
    MethodCall? seen;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return true;
    });

    expect(await CallAudioSession.setSpeakerphone(true), isTrue);
    expect(seen?.method, 'setSpeakerphone');
    expect(seen?.arguments, {'enabled': true});
  });

  test('reports false when the phone did not change the route', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);

    expect(await CallAudioSession.setSpeakerphone(true), isFalse);
  });

  test('reports false when the phone has no native handler', () async {
    // No handler is set, so the platform call throws MissingPluginException.
    expect(await CallAudioSession.setSpeakerphone(false), isFalse);
  });

  test('asks the phone to turn off loudspeaker and reports that it took',
      () async {
    MethodCall? seen;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return true;
    });

    expect(await CallAudioSession.setSpeakerphone(false), isTrue);
    expect(seen?.method, 'setSpeakerphone');
    expect(seen?.arguments, {'enabled': false});
  });

  test('releases the audio session cleanly', () async {
    MethodCall? seen;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return null;
    });

    await CallAudioSession.release();
    expect(seen?.method, 'release');
  });

  test('reads the route the phone reports, with text keys', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'routeSnapshot');
      return {
        'communicationDevice': 'speaker',
        'mode': 3,
        'outputs': ['speaker'],
      };
    });

    expect(await CallAudioSession.routeSnapshot(), {
      'communicationDevice': 'speaker',
      'mode': 3,
      'outputs': ['speaker'],
    });
  });

  test('has no route to read off Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(await CallAudioSession.routeSnapshot(), isNull);
  });

  test('asks the phone to enter Picture-in-Picture mode on Android', () async {
    MethodCall? seen;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return true;
    });

    final entered = await CallAudioSession.enterPip();
    expect(entered, isTrue);
    expect(seen?.method, 'enterPip');
  });

  test('enterPip returns false when phone fails or rejects PiP', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);

    expect(await CallAudioSession.enterPip(), isFalse);
  });
  });
}
