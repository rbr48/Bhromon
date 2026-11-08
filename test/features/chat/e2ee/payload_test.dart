import 'package:bhromon/features/chat/domain/e2ee/e2ee_exceptions.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_payload.dart';
import 'package:flutter_test/flutter_test.dart';

const E2eePayload samplePayload = E2eePayload(
  chatId: 'chat-1',
  senderUid: 'uid-a',
  recipientUid: 'uid-b',
  messageId: 'msg-1',
  sentAtMillis: 1700000000000,
  text: 'নমস্কার',
);

void main() {
  test('encodes with a fixed field order and no spaces', () {
    expect(
      samplePayload.encode(),
      '{"v":1,"chat":"chat-1","from":"uid-a","to":"uid-b","msg":"msg-1",'
      '"sentAt":1700000000000,"text":"নমস্কার"}',
    );
  });

  test('round trips through encode and decode', () {
    final decoded = E2eePayload.decode(samplePayload.encode());
    expect(decoded.chatId, 'chat-1');
    expect(decoded.senderUid, 'uid-a');
    expect(decoded.recipientUid, 'uid-b');
    expect(decoded.messageId, 'msg-1');
    expect(decoded.sentAtMillis, 1700000000000);
    expect(decoded.text, 'নমস্কার');
  });

  test('accepts the identifiers it was sent with', () {
    expect(
      () => samplePayload.checkBinding(
        expectedChatId: 'chat-1',
        expectedSenderUid: 'uid-a',
        expectedRecipientUid: 'uid-b',
        expectedMessageId: 'msg-1',
      ),
      returnsNormally,
    );
  });

  test('refuses a payload for another chat, sender, recipient or message', () {
    final cases = <({String name, void Function() check})>[
      (
        name: 'chat',
        check: () => samplePayload.checkBinding(
              expectedChatId: 'chat-2',
              expectedSenderUid: 'uid-a',
              expectedRecipientUid: 'uid-b',
              expectedMessageId: 'msg-1',
            ),
      ),
      (
        name: 'sender',
        check: () => samplePayload.checkBinding(
              expectedChatId: 'chat-1',
              expectedSenderUid: 'uid-x',
              expectedRecipientUid: 'uid-b',
              expectedMessageId: 'msg-1',
            ),
      ),
      (
        name: 'recipient',
        check: () => samplePayload.checkBinding(
              expectedChatId: 'chat-1',
              expectedSenderUid: 'uid-a',
              expectedRecipientUid: 'uid-x',
              expectedMessageId: 'msg-1',
            ),
      ),
      (
        name: 'message',
        check: () => samplePayload.checkBinding(
              expectedChatId: 'chat-1',
              expectedSenderUid: 'uid-a',
              expectedRecipientUid: 'uid-b',
              expectedMessageId: 'msg-2',
            ),
      ),
    ];
    for (final c in cases) {
      expect(
        c.check,
        throwsA(isA<E2eeSecurityException>()),
        reason: 'mismatched ${c.name}',
      );
    }
  });

  test('refuses malformed payloads', () {
    final cases = <String>[
      'not json',
      '[1, 2]',
      '{"v":2,"chat":"c","from":"a","to":"b","msg":"m","sentAt":1,"text":"t"}',
      '{"v":1,"chat":"c","from":"a","to":"b","msg":"m","sentAt":-1,"text":"t"}',
      '{"v":1,"chat":"","from":"a","to":"b","msg":"m","sentAt":1,"text":"t"}',
      '{"v":1,"chat":"c","from":"a","to":"b","msg":"m","sentAt":1,"text":"t",'
          '"extra":1}',
    ];
    for (final source in cases) {
      expect(
        () => E2eePayload.decode(source),
        throwsA(isA<E2eeFormatException>()),
        reason: source,
      );
    }
  });

  test('refuses text over the size limit', () {
    final tooLong = 'a' * (E2eePayload.maxTextBytes + 1);
    final source = E2eePayload(
      chatId: 'chat-1',
      senderUid: 'uid-a',
      recipientUid: 'uid-b',
      messageId: 'msg-1',
      sentAtMillis: 1,
      text: tooLong,
    ).encode();
    expect(
      () => E2eePayload.decode(source),
      throwsA(isA<E2eeFormatException>()),
    );
  });
}
