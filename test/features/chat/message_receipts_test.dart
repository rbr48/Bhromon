import 'package:bhromon/features/chat/data/vps_chat_service.dart';
import 'package:bhromon/features/chat/domain/message_receipts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('receiptStateFor', () {
    test('a write this phone has not finished is pending', () {
      expect(receiptStateFor(status: 'pending'), ReceiptState.pending);
    });

    test('a saved message with no receipt yet is sent', () {
      expect(receiptStateFor(status: 'sent'), ReceiptState.sent);
      expect(receiptStateFor(), ReceiptState.sent);
    });

    test('a delivered message shows delivered', () {
      expect(receiptStateFor(status: 'delivered'), ReceiptState.delivered);
    });

    test('a read message shows read, from the status or the older seen flag',
        () {
      expect(receiptStateFor(status: 'read'), ReceiptState.read);
      expect(receiptStateFor(status: 'sent', seen: true), ReceiptState.read);
    });

    test('a pending write stays pending even when the server has seen it', () {
      expect(
          receiptStateFor(status: 'pending', seen: true), ReceiptState.pending);
    });
  });

  group('advanceReceipt', () {
    test('a receipt moves forward through sent, delivered and read', () {
      var receipt = ReceiptState.pending;
      final seen = <ReceiptState>[receipt];
      for (final next in [
        ReceiptState.sent,
        ReceiptState.delivered,
        ReceiptState.read,
      ]) {
        receipt = advanceReceipt(receipt, next);
        seen.add(receipt);
      }

      expect(seen, [
        ReceiptState.pending,
        ReceiptState.sent,
        ReceiptState.delivered,
        ReceiptState.read,
      ]);
    });

    test('a late delivered never hides a read that arrived first', () {
      expect(
        advanceReceipt(ReceiptState.read, ReceiptState.delivered),
        ReceiptState.read,
      );
    });

    test('the same state again changes nothing', () {
      expect(
        advanceReceipt(ReceiptState.delivered, ReceiptState.delivered),
        ReceiptState.delivered,
      );
    });
  });

  group('shouldRecordDelivery', () {
    test('only a message still at sent is recorded as delivered', () {
      expect(shouldRecordDelivery('sent'), isTrue);
      expect(shouldRecordDelivery(null), isTrue);
    });

    test('a delivered or read message is left where it is', () {
      expect(shouldRecordDelivery('delivered'), isFalse);
      expect(shouldRecordDelivery('read'), isFalse);
    });

    test('a pending write is not recorded from the recipient side', () {
      expect(shouldRecordDelivery('pending'), isFalse);
    });
  });

  group('sendMessageBody', () {
    test('carries the client message id when one is given', () {
      final body = sendMessageBody(
        chatId: 'chat-1',
        recipientId: 'uid-bob',
        text: 'hi',
        clientMessageId: 'msg-42',
      );

      expect(body['clientMessageId'], 'msg-42');
      expect(body['text'], 'hi');
    });

    test('leaves the client message id out when there is none', () {
      final body = sendMessageBody(chatId: 'chat-1', recipientId: 'uid-bob');

      expect(body.containsKey('clientMessageId'), isFalse);
      expect(body['text'], '');
    });

    test('a retry sends the same id as the first attempt', () {
      final first = sendMessageBody(
        chatId: 'chat-1',
        recipientId: 'uid-bob',
        text: 'hi',
        clientMessageId: 'msg-42',
      );
      final retry = sendMessageBody(
        chatId: 'chat-1',
        recipientId: 'uid-bob',
        text: 'hi',
        clientMessageId: 'msg-42',
      );

      expect(retry['clientMessageId'], first['clientMessageId']);
    });
  });
}
