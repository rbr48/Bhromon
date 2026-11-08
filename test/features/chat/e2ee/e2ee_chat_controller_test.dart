import 'package:bhromon/core/config/feature_flags.dart';
import 'package:bhromon/features/chat/data/e2ee/e2ee_chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

// The default build must not touch encryption: the flag is off, so no chat gets a
// service, no chat is created encrypted, and nothing reads the native library.

void main() {
  test('encryption is off unless the build turns the flag on', () {
    expect(kE2eeOneToOne, isFalse);
    expect(E2eeChatController.enabledInBuild, isFalse);
  });

  test('a build without the flag has no service for anyone', () {
    expect(E2eeChatController.instance.serviceFor('uid-a'), isNull);
    expect(E2eeChatController.instance.serviceFor(''), isNull);
    E2eeChatController.instance.release();
  });
}
