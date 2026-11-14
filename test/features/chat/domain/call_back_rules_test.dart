import 'package:bhromon/features/chat/domain/call_back_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// Back on the call screen minimizes a call that is still on, on Android, and leaves the screen
// otherwise. Picture-in-picture is allowed only for a connected video call that is not over.

void main() {
  group('callBackActionFor', () {
    test('minimizes a call that is still on, on Android', () {
      expect(
        callBackActionFor(onAndroid: true, callOver: false),
        CallBackAction.minimize,
      );
    });

    test('leaves the screen once the call is over', () {
      expect(
        callBackActionFor(onAndroid: true, callOver: true),
        CallBackAction.leave,
      );
    });

    test('leaves the screen off Android, as it always has', () {
      expect(
        callBackActionFor(onAndroid: false, callOver: false),
        CallBackAction.leave,
      );
    });
  });

  group('callShrinksToPip', () {
    test('a connected video call that is not over may shrink', () {
      expect(
        callShrinksToPip(videoMode: true, connected: true, callOver: false),
        isTrue,
      );
    });

    test('a voice call may not', () {
      expect(
        callShrinksToPip(videoMode: false, connected: true, callOver: false),
        isFalse,
      );
    });

    test('a video call that is still connecting or reconnecting may not', () {
      expect(
        callShrinksToPip(videoMode: true, connected: false, callOver: false),
        isFalse,
      );
    });

    test('a call that is over may not', () {
      expect(
        callShrinksToPip(videoMode: true, connected: true, callOver: true),
        isFalse,
      );
    });
  });
}
