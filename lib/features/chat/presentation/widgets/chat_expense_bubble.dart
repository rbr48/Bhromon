import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/presentation/chat_palette.dart';
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
    // Accent text on your own bubble reads poorly, so it uses the main text
    // colour there.
    final accentOnBubble =
        isPaidByMe ? context.chat.text : context.chat.accentText;

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: isPaidByMe ? context.chat.outgoing : context.chat.panel,
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
                  color: AppColors.chatGreen.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.receipt_long,
                  color: context.chat.accentText,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.translate('chat_expense_split_title'),
                  style: TextStyle(
                    color: accentOnBubble,
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
            style: TextStyle(
              color: context.chat.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '৳${amount.toStringAsFixed(0)} BDT',
            style: TextStyle(
              color: context.chat.text,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isPaidByMe
                ? context.l10n.translate('chat_expense_you_paid',
                    args: {'amount': splitAmount.toStringAsFixed(0)})
                : context.l10n.translate('chat_expense_they_paid', args: {
                    'name': paidByName,
                    'amount': splitAmount.toStringAsFixed(0)
                  }),
            style: TextStyle(
              color: isPaidByMe ? context.chat.owedToYou : context.chat.youOwe,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          if (onSettle != null && !isSettled)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.chatGreen),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
                onPressed: onSettle,
                child: Text(
                  context.l10n.translate('chat_expense_mark_settled'),
                  style: TextStyle(color: accentOnBubble, fontSize: 12),
                ),
              ),
            ),
          if (isSettled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: context.chat.divider10,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: accentOnBubble, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    context.l10n.translate('chat_expense_settled'),
                    style: TextStyle(color: accentOnBubble, fontSize: 11),
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
                  style: TextStyle(color: context.chat.text54, fontSize: 11),
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
