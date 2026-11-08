import 'package:bhromon/features/chat/domain/e2ee/encrypted_chat_actions.dart';
import 'package:flutter_test/flutter_test.dart';

// The actions a message offers in a chat (E2EE_DESIGN.md, section 11, M4 item 7). An
// encrypted chat offers only what its first slice supports: the rules refuse the rest.

void main() {
  test('a plaintext chat offers every action', () {
    for (final action in ChatAction.values) {
      expect(chatActionAllowed(action, encrypted: false), isTrue,
          reason: action.name);
    }
  });

  test('an encrypted chat offers only copy and delete for me', () {
    final allowed = {
      for (final action in ChatAction.values)
        if (chatActionAllowed(action, encrypted: true)) action,
    };

    expect(allowed, {ChatAction.copy, ChatAction.deleteForMe});
  });
}
