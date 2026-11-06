import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../domain/chat_list_sort.dart';
import '../chat_palette.dart';

/// The sort control at the end of the chats list's chip row. It shows the order in
/// use, and its menu picks the other order.
class ChatListSortButton extends StatelessWidget {
  const ChatListSortButton({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ChatListSort value;
  final ValueChanged<ChatListSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<ChatListSort>(
      tooltip: l10n.translate('chats_sort_tooltip'),
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in ChatListSort.values)
          PopupMenuItem<ChatListSort>(
            value: option,
            child: Text(
              _label(context.l10n, option),
              style: TextStyle(color: context.chat.text),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: context.chat.bar,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, size: 14, color: context.chat.text60),
            const SizedBox(width: 6),
            Text(
              _label(l10n, value),
              style: TextStyle(
                color: context.chat.text60,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _label(AppLocalizations l10n, ChatListSort option) =>
      switch (option) {
        ChatListSort.recent => l10n.translate('chats_sort_recent'),
        ChatListSort.name => l10n.translate('chats_sort_name'),
      };
}
