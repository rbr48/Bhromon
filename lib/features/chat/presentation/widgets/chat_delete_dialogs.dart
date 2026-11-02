import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/presentation/chat_palette.dart';
import 'package:bhromon/core/utils/app_logger.dart';
import 'package:bhromon/features/chat/data/chat_deletion_service.dart';
import 'package:bhromon/features/chat/domain/chat_deletion.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum _MessageDeleteChoice { forMe, forEveryone }

/// Asks how to delete the selected [messages], then deletes them.
///
/// "Delete for everyone" is offered only when at least one message can still be
/// deleted for everyone, and it applies only to those messages. Returns the ids
/// that were changed, so the caller can reload them, or null when nothing was
/// deleted.
Future<Set<String>?> showDeleteMessagesDialog(
  BuildContext context, {
  required List<QueryDocumentSnapshot> messages,
  required String chatId,
  required String currentUid,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final failedText = context.l10n.translate('chat_delete_failed');
  final now = DateTime.now();

  final allIds = <String>[];
  final everyoneIds = <String>[];
  var refusedForEveryone = 0;
  for (final doc in messages) {
    final data =
        (doc.data() as Map<String, dynamic>?) ?? const <String, dynamic>{};
    allIds.add(doc.id);
    final alreadyDeleted =
        data['type'] == 'deleted' || data['isDeleted'] == true;
    final allowed = canDeleteForEveryone(
      senderId: data['senderId'] as String?,
      currentUid: currentUid,
      sentAt: ChatDeletionService.timestampOf(data['timestamp']),
      now: now,
      alreadyDeleted: alreadyDeleted,
    );
    if (allowed) {
      everyoneIds.add(doc.id);
    } else if (!alreadyDeleted) {
      refusedForEveryone++;
    }
  }
  if (allIds.isEmpty) return null;

  final choice = await showDialog<_MessageDeleteChoice>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      return AlertDialog(
        backgroundColor: context.chat.bar,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          allIds.length == 1
              ? l10n.translate('chat_delete_message_title')
              : l10n.translate('chat_delete_messages_title',
                  args: {'count': allIds.length}),
          style: TextStyle(
            color: context.chat.text,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('chat_delete_messages_body'),
              style: TextStyle(color: context.chat.text70, fontSize: 13),
            ),
            if (everyoneIds.isNotEmpty && refusedForEveryone > 0) ...[
              const SizedBox(height: 10),
              Text(
                l10n.translate(
                  'chat_delete_everyone_partial',
                  args: {
                    'count': refusedForEveryone,
                    'hours': kDeleteForEveryoneWindow.inHours,
                  },
                ),
                style: TextStyle(color: context.chat.text54, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              l10n.translate('chat_delete_cancel'),
              style: TextStyle(color: context.chat.accentText),
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _MessageDeleteChoice.forMe),
            child: Text(
              l10n.translate('chat_delete_for_me'),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
          if (everyoneIds.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(
                  dialogContext, _MessageDeleteChoice.forEveryone),
              child: Text(
                l10n.translate('chat_delete_for_everyone'),
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
        ],
      );
    },
  );
  if (choice == null) return null;

  final forEveryone = choice == _MessageDeleteChoice.forEveryone;
  final targets = forEveryone ? everyoneIds : allIds;
  try {
    final service = ChatDeletionService();
    if (forEveryone) {
      await service.deleteForEveryone(chatId: chatId, messageIds: targets);
    } else {
      await service.deleteForMe(
        chatId: chatId,
        uid: currentUid,
        messageIds: targets,
      );
    }
    return targets.toSet();
  } catch (error, stackTrace) {
    logWarning('Could not delete messages in $chatId', error, stackTrace);
    messenger.showSnackBar(
      SnackBar(
        content: Text(failedText),
        backgroundColor: const Color(0xFF1F2C34),
      ),
    );
    return null;
  }
}

/// Asks to confirm deleting a whole chat for [uid] only, then deletes it.
/// Returns true when the chat was deleted.
Future<bool> showDeleteChatDialog(
  BuildContext context, {
  required String chatId,
  required String uid,
  required String otherName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final title = l10n.translate('chat_delete_chat_title');
  final body =
      l10n.translate('chat_delete_chat_body', args: {'name': otherName});
  final action = l10n.translate('chat_delete_chat_action');
  final cancel = l10n.translate('chat_delete_cancel');
  final doneText = l10n.translate('chat_delete_chat_done');
  final failedText = l10n.translate('chat_delete_failed');

  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.chat.bar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        title,
        style: TextStyle(
          color: context.chat.text,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Text(
        body,
        style: TextStyle(color: context.chat.text70, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(
            cancel,
            style: TextStyle(color: context.chat.accentText),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            action,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  try {
    await ChatDeletionService().deleteChatForMe(chatId: chatId, uid: uid);
    messenger.showSnackBar(
      SnackBar(
        content: Text(doneText),
        backgroundColor: const Color(0xFF00A884),
      ),
    );
    return true;
  } catch (error, stackTrace) {
    logWarning('Could not delete chat $chatId', error, stackTrace);
    messenger.showSnackBar(
      SnackBar(
        content: Text(failedText),
        backgroundColor: const Color(0xFF1F2C34),
      ),
    );
    return false;
  }
}
