import 'package:bhromon/features/chat/data/call_notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The end-of-call push must stop a ring on a phone that has not answered, and must never
/// end a call the phone has answered. The server also sends it to the phone that answered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_callkit_incoming');

  late List<String> ended;
  late List<Map<String, dynamic>> nativeCalls;
  late bool listFails;

  setUp(() {
    ended = [];
    nativeCalls = [];
    listFails = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'activeCalls':
          if (listFails) throw PlatformException(code: 'unavailable');
          return nativeCalls;
        case 'endCall':
          ended.add((call.arguments as Map)['id'] as String);
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Map<String, dynamic> ringing(String id) => {
        'id': id,
        'isAccepted': false,
        'extra': {'callId': id},
      };

  test('ends a call this phone still holds as ringing', () async {
    nativeCalls = [ringing('c1')];

    await CallNotificationService.endNativeIncomingCall('c1');

    expect(ended, ['c1']);
  });

  test('leaves a call this phone answered on its own call screen', () async {
    nativeCalls = [
      {...ringing('c1'), 'isAccepted': true},
    ];

    await CallNotificationService.endNativeIncomingCall('c1');

    expect(ended, isEmpty);
  });

  test('ends nothing for a call the phone does not hold', () async {
    nativeCalls = [ringing('c2')];

    await CallNotificationService.endNativeIncomingCall('c1');

    expect(ended, isEmpty);
  });

  test('a call list that cannot be read cuts no call', () async {
    listFails = true;

    await CallNotificationService.endNativeIncomingCall('c1');

    expect(ended, isEmpty);
  });
}
