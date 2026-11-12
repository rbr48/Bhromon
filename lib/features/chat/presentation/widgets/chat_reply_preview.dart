import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/media/media_access.dart';
import 'package:bhromon/features/chat/presentation/chat_palette.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bhromon/core/utils/image_sizing.dart';

/// Data model representing a message being replied to or quoted.
class ReplyMessageInfo {
  final String messageId;
  final String senderId;
  final String senderName;
  final String text;
  final String
      type; // 'text' | 'image' | 'video' | 'audio' | 'document' | 'location'
  final String? mediaUrl;

  const ReplyMessageInfo({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.type,
    this.mediaUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'type': type,
      if (mediaUrl != null && mediaUrl!.isNotEmpty) 'mediaUrl': mediaUrl,
    };
  }

  factory ReplyMessageInfo.fromMap(Map<String, dynamic> map) {
    return ReplyMessageInfo(
      messageId: (map['messageId'] as String?) ?? '',
      senderId: (map['senderId'] as String?) ?? '',
      senderName: (map['senderName'] as String?) ?? 'Member',
      text: (map['text'] as String?) ?? '',
      type: (map['type'] as String?) ?? 'text',
      mediaUrl: map['mediaUrl'] as String?,
    );
  }
}

/// WhatsApp-style sticky banner shown directly above the chat text input when replying.
class ChatReplyInputBanner extends StatelessWidget {
  final ReplyMessageInfo reply;
  final VoidCallback onCancel;

  const ChatReplyInputBanner({
    super.key,
    required this.reply,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.chat.bar,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: AppColors.chatGreen, width: 4),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, color: context.chat.accentText, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reply.senderName,
                  style: TextStyle(
                    color: context.chat.accentText,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                _buildSnippet(context, reply),
              ],
            ),
          ),
          if (reply.mediaUrl != null &&
              reply.mediaUrl!.isNotEmpty &&
              reply.type == 'image')
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: kIsWeb
                  ? Image.network(
                      signedMediaUrl(reply.mediaUrl!),
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      cacheWidth: context.decodeWidth(40),
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_rounded, size: 18),
                    )
                  : CachedNetworkImage(
                      imageUrl: signedMediaUrl(reply.mediaUrl!),
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      memCacheWidth: context.decodeWidth(40),
                      placeholder: (context, _) =>
                          Container(color: context.chat.divider10),
                      errorWidget: (context, _, __) => Image.network(
                        signedMediaUrl(reply.mediaUrl!),
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image_rounded, size: 18),
                      ),
                    ),
            ),
          IconButton(
            icon:
                Icon(Icons.close_rounded, color: context.chat.text60, size: 18),
            onPressed: onCancel,
            tooltip: context.l10n.translate('chat_reply_cancel'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildSnippet(BuildContext context, ReplyMessageInfo reply) {
    IconData? icon;
    String label = reply.text;

    switch (reply.type) {
      case 'image':
        icon = Icons.photo_camera_rounded;
        if (label.isEmpty) {
          label = context.l10n.translate('chat_label_photo');
        }
        break;
      case 'video':
        icon = Icons.videocam_rounded;
        if (label.isEmpty) {
          label = context.l10n.translate('chat_video_label');
        }
        break;
      case 'audio':
        icon = Icons.mic_rounded;
        label = context.l10n.translate('chat_voice_message');
        break;
      case 'document':
        icon = Icons.insert_drive_file_rounded;
        if (label.isEmpty) {
          label = context.l10n.translate('chat_attach_document');
        }
        break;
      case 'location':
        icon = Icons.location_on_rounded;
        if (label.isEmpty) {
          label = context.l10n.translate('chat_attach_location');
        }
        break;
    }

    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: context.chat.text70),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: context.chat.text70, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// WhatsApp-style quote bubble embedded inside the message bubble.
class ChatQuotedBubble extends StatelessWidget {
  final ReplyMessageInfo reply;
  final bool isMe;
  final VoidCallback? onTap;

  const ChatQuotedBubble({
    super.key,
    required this.reply,
    required this.isMe,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: isMe
              ? context.chat
                  .outgoingRecessed // slightly darker shade of sender bubble
              : context.chat
                  .recessedDeep, // slightly darker shade of receiver bubble
          borderRadius: BorderRadius.circular(8),
          border: const Border(
            left: BorderSide(
              color: AppColors.chatGreen,
              width: 3.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    reply.senderName,
                    style: TextStyle(
                      color: context.chat.accentText,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  _buildSnippet(context, reply),
                ],
              ),
            ),
            if (reply.mediaUrl != null &&
                reply.mediaUrl!.isNotEmpty &&
                reply.type == 'image') ...[
              const SizedBox(width: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: kIsWeb
                    ? Image.network(
                        signedMediaUrl(reply.mediaUrl!),
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image_rounded, size: 14),
                      )
                    : CachedNetworkImage(
                        imageUrl: signedMediaUrl(reply.mediaUrl!),
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        placeholder: (context, _) =>
                            Container(color: context.chat.divider10),
                        errorWidget: (context, _, __) => Image.network(
                          signedMediaUrl(reply.mediaUrl!),
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image_rounded, size: 14),
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSnippet(BuildContext context, ReplyMessageInfo reply) {
    IconData? icon;
    String label = reply.text;

    switch (reply.type) {
      case 'image':
        icon = Icons.photo_camera_rounded;
        if (label.isEmpty) {
          label = context.l10n.translate('chat_label_photo');
        }
        break;
      case 'video':
        icon = Icons.videocam_rounded;
        if (label.isEmpty) {
          label = context.l10n.translate('chat_video_label');
        }
        break;
      case 'audio':
        icon = Icons.mic_rounded;
        label = context.l10n.translate('chat_voice_message');
        break;
      case 'document':
        icon = Icons.insert_drive_file_rounded;
        if (label.isEmpty) {
          label = context.l10n.translate('chat_attach_document');
        }
        break;
      case 'location':
        icon = Icons.location_on_rounded;
        if (label.isEmpty) {
          label = context.l10n.translate('chat_attach_location');
        }
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: context.chat.text60),
          const SizedBox(width: 3),
        ],
        Flexible(
          child: Text(
            label,
            style: TextStyle(color: context.chat.text60, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
