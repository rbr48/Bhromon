import 'package:flutter/material.dart';

/// WhatsApp-style travel expense split bubble.
class ChatExpenseBubble extends StatelessWidget {
  final String title;
  final double amount;
  final String paidByName;
  final bool isPaidByMe;
  final bool isSettled;
  final String timeStr;
  final Widget? deliveryIcon;
  final VoidCallback? onSettle;

  const ChatExpenseBubble({
    super.key,
    required this.title,
    required this.amount,
    required this.paidByName,
    required this.isPaidByMe,
    required this.isSettled,
    required this.timeStr,
    this.deliveryIcon,
    this.onSettle,
  });

  @override
  Widget build(BuildContext context) {
    final splitAmount = amount / 2;

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: isPaidByMe ? const Color(0xFF005C4B) : const Color(0xFF202C33),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A884).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.receipt_long,
                  color: Color(0xFF00A884),
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Travel Expense Split',
                  style: TextStyle(
                    color: Color(0xFF00A884),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '৳${amount.toStringAsFixed(0)} BDT',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isPaidByMe
                ? 'You paid • ৳${splitAmount.toStringAsFixed(0)} owed to you'
                : '$paidByName paid • You owe ৳${splitAmount.toStringAsFixed(0)}',
            style: TextStyle(
              color: isPaidByMe
                  ? const Color(0xFF53BDEB)
                  : const Color(0xFFFFB74D),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          if (onSettle != null && !isSettled)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF00A884)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
                onPressed: onSettle,
                child: const Text(
                  'Mark Settled',
                  style: TextStyle(color: Color(0xFF00A884), fontSize: 12),
                ),
              ),
            ),
          if (isSettled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF00A884), size: 12),
                  SizedBox(width: 4),
                  Text(
                    'Settled',
                    style: TextStyle(color: Color(0xFF00A884), fontSize: 10),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.bottomRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: const TextStyle(color: Colors.white54, fontSize: 9.5),
                ),
                if (isPaidByMe && deliveryIcon != null) ...[
                  const SizedBox(width: 4),
                  deliveryIcon!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
