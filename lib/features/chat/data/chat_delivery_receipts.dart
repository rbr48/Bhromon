import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/app_logger.dart';
import '../domain/message_receipts.dart';

/// Records on the sender's copy of a message that the recipient's phone has it.
///
/// This runs on the recipient's phone. firestore.rules let a recipient change
/// only the receipt fields of a message they did not send, so a message moves
/// from "sent" to "delivered" here and never from the sender's side.
class ChatDeliveryReceipts {
  ChatDeliveryReceipts._();

  /// Moves the message to delivered, unless it is already delivered or read.
  /// A message the sender's device has not saved yet is left alone; its status
  /// stays as the sender wrote it.
  static Future<void> recordDelivered({
    required String chatId,
    required String messageId,
  }) async {
    final db = FirebaseFirestore.instance;
    final ref = db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);
    try {
      await db.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (!snapshot.exists) return;
        final status = snapshot.data()?['status'] as String?;
        if (!shouldRecordDelivery(status)) return;
        transaction.update(ref, {
          'status': 'delivered',
          'deliveredAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (error, stackTrace) {
      logWarning('[ChatReceipts] Delivery not recorded', error, stackTrace);
    }
  }
}
