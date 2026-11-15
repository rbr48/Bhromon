import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/media/media_access.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/image_sizing.dart';
import '../../domain/cached_messages.dart';
import '../../domain/message_receipts.dart';
import '../chat_palette.dart';
import 'chat_bubble_clippers.dart';
import 'chat_document_bubble.dart';
import 'chat_expense_bubble.dart';
import 'chat_location_bubble.dart';
import 'chat_media_bubble.dart';
import 'chat_reaction_bar.dart';
import 'chat_reply_preview.dart';
import 'chat_rich_text.dart';
import 'swipe_to_reply.dart';
import 'voice_message_bubble.dart';

/// Where each message bubble on screen is, by message id. The chat uses it to scroll to a
/// message, without a global key on every bubble.
class ChatBubbleRegistry {
  final Map<String, BuildContext> _contexts = {};

  /// The place of the bubble of [messageId], or null while it is not built.
  BuildContext? contextOf(String messageId) {
    final context = _contexts[messageId];
    return context != null && context.mounted ? context : null;
  }

  void _attach(String messageId, BuildContext context) =>
      _contexts[messageId] = context;

  void _detach(String messageId, BuildContext context) {
    if (identical(_contexts[messageId], context)) _contexts.remove(messageId);
  }
}

/// One message of a one-to-one chat: its bubble, its reply swipe, its selection and its
/// reactions. The bubble is drawn again only when its own message, its selection or the theme
/// changes, so a new message or a tick elsewhere in the chat leaves it as it is.
class ChatMessageBubble extends StatefulWidget {
  const ChatMessageBubble({
    super.key,
    required this.messageId,
    required this.data,
    required this.hasPendingWrites,
    required this.fromLocalCache,
    required this.currentUid,
    required this.isSelected,
    required this.isHighlighted,
    required this.replyEnabled,
    required this.formatTime,
    required this.onScrollToMessage,
    required this.onExpandText,
    required this.onReply,
    required this.onTap,
    required this.onLongPress,
    required this.onSettleExpense,
    required this.onViewOnceOpened,
    this.registry,
  });

  final String messageId;

  /// The message as the list shows it. An encrypted message carries its readable text.
  final Map<String, dynamic> data;

  final bool hasPendingWrites;

  /// The message comes from the phone's cache and the server has not answered yet.
  final bool fromLocalCache;

  final String currentUid;
  final bool isSelected;
  final bool isHighlighted;
  final bool replyEnabled;
  final ChatBubbleRegistry? registry;

  final String Function(DateTime time) formatTime;
  final void Function(String messageId) onScrollToMessage;
  final void Function(Map<String, dynamic> message) onExpandText;
  final VoidCallback onReply;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// An expense in the message was marked settled.
  final VoidCallback onSettleExpense;

  /// A view-once photo or video was opened and closed.
  final VoidCallback onViewOnceOpened;

  /// How many times a bubble's content has been drawn. For tests of the rebuild rule.
  @visibleForTesting
  static int debugContentBuilds = 0;

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble> {
  // The bubble as last drawn. Handing the same widget back makes Flutter skip it.
  Widget? _drawn;

  @override
  void initState() {
    super.initState();
    widget.registry?._attach(widget.messageId, context);
  }

  @override
  void didUpdateWidget(ChatMessageBubble old) {
    super.didUpdateWidget(old);
    if (old.messageId != widget.messageId || old.registry != widget.registry) {
      old.registry?._detach(old.messageId, context);
      widget.registry?._attach(widget.messageId, context);
    }
    final same = old.messageId == widget.messageId &&
        old.hasPendingWrites == widget.hasPendingWrites &&
        old.fromLocalCache == widget.fromLocalCache &&
        old.currentUid == widget.currentUid &&
        old.isSelected == widget.isSelected &&
        old.isHighlighted == widget.isHighlighted &&
        old.replyEnabled == widget.replyEnabled &&
        messageDataEquals(old.data, widget.data);
    if (!same) _drawn = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The theme or the language changed.
    _drawn = null;
  }

  @override
  void dispose() {
    widget.registry?._detach(widget.messageId, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _drawn ??= _draw(context);

  Widget _draw(BuildContext context) {
    ChatMessageBubble.debugContentBuilds++;
    final data = widget.data;
    final currentUid = widget.currentUid;
    final String msgType = (data['type'] as String?) ?? 'text';
    final String text = (data['text'] as String?) ?? '';
    final String mediaUrl = (data['mediaUrl'] as String?) ?? '';
    final List<String>? mediaUrls = (data['mediaUrls'] is List)
        ? (data['mediaUrls'] as List).cast<String>()
        : null;
    final senderId = data['senderId'] ?? '';
    final isMe = senderId == currentUid;
    final bool seen = data['seen'] as bool? ?? false;
    // Delivery status: 'pending' (clock) | 'sent' (single check) | 'delivered' (double grey) | 'read' (double blue)
    final bool hasPendingWrites = widget.hasPendingWrites;
    final String status = hasPendingWrites
        ? 'pending'
        : ((data['status'] as String?) ?? (seen ? 'read' : 'sent'));
    final timestamp = data['timestamp'] as Timestamp?;

    // Locale-aware time string
    String timeStr = '';
    if (timestamp != null) {
      final date = timestamp.toDate();
      try {
        timeStr = widget.formatTime(date);
      } catch (_) {
        timeStr = localizedDateFormat('h:mm a').format(date);
      }
    }

    // Delivery tick icon: a clock while pending, a single check
    // when sent, double grey when delivered, double blue when read.
    Widget deliveryIcon() {
      switch (receiptStateFor(status: status, seen: seen)) {
        case ReceiptState.pending:
          return Icon(Icons.access_time_rounded,
              size: 11, color: context.chat.text54);
        case ReceiptState.read:
          return const Icon(Icons.done_all_rounded,
              size: 13, color: Color(0xFF53BDEB));
        case ReceiptState.delivered:
          return Icon(Icons.done_all_rounded,
              size: 13, color: context.chat.text54);
        case ReceiptState.sent:
          return Icon(Icons.done_rounded, size: 13, color: context.chat.text54);
      }
    }

    final isSelected = widget.isSelected;
    final isHighlighted = widget.isHighlighted;
    final replyData = data['replyTo'] as Map<String, dynamic>?;
    final replyModel =
        replyData != null ? ReplyMessageInfo.fromMap(replyData) : null;
    final reactions = (data['reactions'] as Map<String, dynamic>?) ?? {};
    final starredBy = (data['starredBy'] as Map<String, dynamic>?) ?? {};
    final isStarred = starredBy[currentUid] == true;
    final isEdited = data['isEdited'] == true;
    final isForwarded = data['isForwarded'] == true;

    Widget metaRow() {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEdited) ...[
            Text(context.l10n.translate('chat_edited'),
                style: TextStyle(color: context.chat.text38, fontSize: 11)),
            const SizedBox(width: 3),
          ],
          Text(
            timeStr,
            style: TextStyle(
              color: context.chat.text54,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (isStarred) ...[
            const SizedBox(width: 3),
            Icon(Icons.star_rounded, size: 10, color: context.chat.text60),
          ],
          if (isMe) ...[
            const SizedBox(width: 4),
            deliveryIcon(),
          ],
        ],
      );
    }

    Widget bubbleBody;

    // ── Deleted Message Tombstone (WhatsApp Style) ──
    if (msgType == 'deleted' || data['isDeleted'] == true) {
      bubbleBody = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.chat.bar,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.chat.divider10,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.block_flipped,
              size: 14,
              color: context.chat.text38,
            ),
            const SizedBox(width: 6),
            Text(
              isMe
                  ? context.l10n.translate('chat_deleted_by_me')
                  : context.l10n.translate('chat_deleted_message'),
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: context.chat.text54,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              timeStr,
              style: TextStyle(
                color: context.chat.text30,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }
    // ── Document Message ──────────────────────────────
    else if (msgType == 'document') {
      bubbleBody = Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (replyModel != null)
            ChatQuotedBubble(
              reply: replyModel,
              isMe: isMe,
              onTap: () => widget.onScrollToMessage(replyModel.messageId),
            ),
          ChatDocumentBubble(
            documentUrl: (data['documentUrl'] as String?) ?? '',
            fileName: (data['fileName'] as String?) ??
                context.l10n.translate('chat_attach_document'),
            fileSizeBytes: (data['fileSizeBytes'] as num?)?.toInt() ?? 0,
            isMe: isMe,
            timeStr: timeStr,
            deliveryIcon: isMe ? deliveryIcon() : null,
          ),
        ],
      );
    }
    // ── Location Message ──────────────────────────────
    else if (msgType == 'location') {
      bubbleBody = Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (replyModel != null)
            ChatQuotedBubble(
              reply: replyModel,
              isMe: isMe,
              onTap: () => widget.onScrollToMessage(replyModel.messageId),
            ),
          ChatLocationBubble(
            latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
            longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
            title: (data['title'] as String?) ??
                context.l10n.translate('chat_location_title'),
            address: (data['address'] as String?) ?? '',
            isMe: isMe,
            timeStr: timeStr,
            deliveryIcon: isMe ? deliveryIcon() : null,
          ),
        ],
      );
    }
    // ── Travel Expense / Split Message ────────────────
    else if (msgType == 'expense') {
      bubbleBody = Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (replyModel != null)
            ChatQuotedBubble(
              reply: replyModel,
              isMe: isMe,
              onTap: () => widget.onScrollToMessage(replyModel.messageId),
            ),
          ChatExpenseBubble(
            title: (data['expenseTitle'] as String?) ??
                context.l10n.translate('chat_expense_split_title'),
            amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
            paidByName: (data['paidByName'] as String?) ??
                context.l10n.translate('chats_member'),
            isPaidByMe: data['paidById'] == currentUid,
            isSettled: data['isSettled'] == true,
            timeStr: timeStr,
            deliveryIcon: isMe ? deliveryIcon() : null,
            onSettle: data['isSettled'] == true
                ? null
                : () {
                    widget.onSettleExpense();
                  },
          ),
        ],
      );
    }
    // ── Media Message (Photo / Video with Caption) ───
    else if (msgType == 'image' || msgType == 'video') {
      final bool isViewOnce = data['isViewOnce'] == true;
      final bool isOpened = data['isOpened'] == true;

      if (isViewOnce) {
        if (isOpened) {
          bubbleBody = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isMe ? context.chat.outgoing : context.chat.panel,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.looks_one_outlined,
                    color: context.chat.text54, size: 18),
                const SizedBox(width: 6),
                Text(context.l10n.translate('chat_opened'),
                    style: TextStyle(
                        color: context.chat.text54,
                        fontStyle: FontStyle.italic,
                        fontSize: 13)),
                const SizedBox(width: 8),
                Text(timeStr,
                    style: TextStyle(color: context.chat.text38, fontSize: 11)),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  deliveryIcon(),
                ],
              ],
            ),
          );
        } else {
          bubbleBody = InkWell(
            onTap: () {
              if (isMe) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text(context.l10n.translate('chat_view_once_sent'))),
                );
                return;
              }
              // A cached copy may be out of date: the photo may have been opened already.
              if (widget.fromLocalCache) return;
              // Decoded at the screen's width, not at the photo's full size.
              final decodeWidth = context.decodeWidth();
              Navigator.of(context)
                  .push(
                MaterialPageRoute<void>(
                  builder: (ctx) => Scaffold(
                    backgroundColor: Colors.black,
                    appBar: AppBar(
                      backgroundColor: Colors.black,
                      iconTheme: const IconThemeData(color: Colors.white),
                      title: Text(
                          msgType == 'video'
                              ? context.l10n.translate('chat_view_once_video')
                              : context.l10n.translate('chat_view_once_photo'),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16)),
                    ),
                    body: Center(
                      child: InteractiveViewer(
                        child: kIsWeb
                            ? Image.network(
                                signedMediaUrl(mediaUrl),
                                fit: BoxFit.contain,
                                cacheWidth: decodeWidth,
                              )
                            : CachedNetworkImage(
                                imageUrl: signedMediaUrl(mediaUrl),
                                fit: BoxFit.contain,
                                memCacheWidth: decodeWidth,
                                errorWidget: (_, __, ___) => Image.network(
                                  signedMediaUrl(mediaUrl),
                                  fit: BoxFit.contain,
                                  cacheWidth: decodeWidth,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              )
                  .then((_) {
                widget.onViewOnceOpened();
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMe ? context.chat.outgoing : context.chat.panel,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFF00A884), width: 1.5),
                    ),
                    child: Center(
                      child: Text('1',
                          style: TextStyle(
                              color: context.chat.accentText,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                      msgType == 'video'
                          ? context.l10n.translate('chat_video_label')
                          : context.l10n.translate('chat_label_photo'),
                      style: TextStyle(
                          color: context.chat.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  const SizedBox(width: 8),
                  Text(timeStr,
                      style:
                          TextStyle(color: context.chat.text54, fontSize: 11)),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    deliveryIcon(),
                  ],
                ],
              ),
            ),
          );
        }
      } else {
        bubbleBody = Container(
          decoration: BoxDecoration(
            color: isMe ? context.chat.outgoing : context.chat.panel,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (isForwarded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.forward_rounded,
                          size: 11, color: context.chat.text54),
                      const SizedBox(width: 3),
                      Text(context.l10n.translate('chat_forwarded_label'),
                          style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: context.chat.text54,
                              fontSize: 11)),
                    ],
                  ),
                ),
              if (replyModel != null)
                ChatQuotedBubble(
                  reply: replyModel,
                  isMe: isMe,
                  onTap: () => widget.onScrollToMessage(replyModel.messageId),
                ),
              ChatMediaBubble(
                mediaUrl: mediaUrl,
                mediaUrls: mediaUrls,
                type: msgType,
                isMe: isMe,
              ),
              if (text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: context.chat.text,
                      fontSize: 16,
                      height: 1.4,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
                child: metaRow(),
              ),
            ],
          ),
        );
      }
    }
    // ── Voice / Audio message ────────────────────────
    else if (msgType == 'audio') {
      bubbleBody = Container(
        decoration: BoxDecoration(
          color: isMe ? context.chat.outgoing : context.chat.panel,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isMe ? const Radius.circular(12) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(12),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (replyModel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: ChatQuotedBubble(
                  reply: replyModel,
                  isMe: isMe,
                  onTap: () => widget.onScrollToMessage(replyModel.messageId),
                ),
              ),
            VoiceMessageBubble(
              audioUrl: mediaUrl,
              durationSeconds: (data['durationSeconds'] as num?)?.toInt(),
              isMe: isMe,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: metaRow(),
            ),
          ],
        ),
      );
    }
    // ── Text bubble ─────────────────────────────────
    else {
      bubbleBody = PhysicalShape(
        clipper: isMe ? SenderBubbleClipper() : ReceiverBubbleClipper(),
        color: isMe ? context.chat.outgoing : context.chat.panel,
        elevation: 1,
        child: Padding(
          padding: EdgeInsets.fromLTRB(isMe ? 10 : 16, 6, isMe ? 16 : 10, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (isForwarded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.forward_rounded,
                          size: 11, color: context.chat.text54),
                      const SizedBox(width: 3),
                      Text(context.l10n.translate('chat_forwarded_label'),
                          style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: context.chat.text54,
                              fontSize: 11)),
                    ],
                  ),
                ),
              if (replyModel != null)
                ChatQuotedBubble(
                  reply: replyModel,
                  isMe: isMe,
                  onTap: () => widget.onScrollToMessage(replyModel.messageId),
                ),
              ChatRichText(
                text: text,
                collapsible: true,
                onExpandFullScreen: () => widget.onExpandText({
                  'id': widget.messageId,
                  'text': text,
                  'senderId': senderId,
                  'timestamp': timestamp,
                }),
                baseStyle: TextStyle(
                  color: context.chat.text,
                  fontSize: 16,
                  height: 1.4,
                  letterSpacing: 0.05,
                  fontFamily: 'NotoSansBengali',
                  fontFamilyFallback: const [
                    'HindSiliguri',
                    'Roboto',
                    'sans-serif'
                  ],
                ),
                isMine: isMe,
              ),
              const SizedBox(height: 2),
              metaRow(),
            ],
          ),
        ),
      );
    }

    return SwipeToReply(
      isMe: isMe,
      enabled: widget.replyEnabled,
      onReply: () => widget.onReply(),
      child: GestureDetector(
        onTap: () => widget.onTap(),
        onLongPress: () => widget.onLongPress(),
        child: Container(
          color: isSelected
              ? AppColors.chatGreen.withValues(alpha: 0.18)
              : isHighlighted
                  ? AppColors.chatGreen.withValues(alpha: 0.28)
                  : Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: 8,
                    left: isMe ? 48 : 0,
                    right: isMe ? 0 : 48,
                  ),
                  child: bubbleBody,
                ),
              ),
              if (reactions.isNotEmpty)
                Positioned(
                  bottom: 0,
                  right: isMe ? 8 : null,
                  left: isMe ? null : 8,
                  child: ChatReactionBadge(
                    reactions: reactions,
                    onTap: () => showReactionDetailsSheet(
                      context,
                      reactions: reactions,
                      currentUid: currentUid,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
