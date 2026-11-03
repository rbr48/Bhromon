/// Delivery receipts for a message the signed-in user sent.
///
/// The values are in the order a receipt moves: a message is pending while this
/// phone is still writing it, sent once it is saved, delivered when the
/// recipient's phone has it, and read when the recipient opens the chat.
enum ReceiptState { pending, sent, delivered, read }

/// The receipt to show for a message with the stored [status] and the older
/// [seen] flag. A write this phone has not finished shows as pending, whatever
/// the server holds, and a message the recipient has seen is read.
ReceiptState receiptStateFor({String? status, bool seen = false}) {
  if (status == 'pending') return ReceiptState.pending;
  if (status == 'read' || seen) return ReceiptState.read;
  if (status == 'delivered') return ReceiptState.delivered;
  return ReceiptState.sent;
}

/// A receipt moves from [current] to [next] but never backwards, so a late
/// "delivered" cannot hide a "read" that arrived first.
ReceiptState advanceReceipt(ReceiptState current, ReceiptState next) {
  return next.index > current.index ? next : current;
}

/// Whether the recipient's phone should record that it received a message whose
/// stored status is [status]. Only a message still at "sent" moves on.
bool shouldRecordDelivery(String? status) => status == null || status == 'sent';
