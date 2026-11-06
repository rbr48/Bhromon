import 'package:flutter/material.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../domain/models/channel_models.dart';
import '../../../chat/presentation/widgets/chat_formatting_toolbar.dart';
import '../../../chat/presentation/widgets/voice_message_recorder.dart';

/// A photo, video, or file picked for the next message, not yet uploaded.
class PendingAttachment {
  final XFile file;
  final bool isVideo;
  final bool isDocument;
  final int? fileSizeBytes;

  const PendingAttachment({
    required this.file,
    this.isVideo = false,
    this.isDocument = false,
    this.fileSizeBytes,
  });
}

/// One line of the mention list. [label] is what goes after the "@".
class MentionChoice {
  final String label;
  final String display;

  const MentionChoice({required this.label, required this.display});
}

/// The message box at the foot of a channel: reply or edit banner, pending
/// attachments with upload progress, the mention list, and the input row.
class ChannelComposer extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool sending;
  final ChannelReply? replyTo;
  final bool editing;
  final List<PendingAttachment> pending;

  /// Progress of the photo or video being uploaded, from 0 to 1.
  final double uploadProgress;

  /// Shown above the progress bar while uploading. Null when not uploading.
  final String? uploadLabel;
  final List<MentionChoice> mentionChoices;
  final ValueChanged<String> onChanged;
  final ValueChanged<MentionChoice> onPickMention;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onCancelContext;
  final VoidCallback onCancelUpload;
  final ValueChanged<int> onRemovePending;
  final bool recordingVoice;
  final VoidCallback onStartVoice;
  final void Function(String path, Duration duration) onVoiceSent;
  final VoidCallback onVoiceCancel;

  const ChannelComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.sending,
    required this.replyTo,
    required this.editing,
    required this.pending,
    required this.uploadProgress,
    required this.uploadLabel,
    required this.mentionChoices,
    required this.onChanged,
    required this.onPickMention,
    required this.onSend,
    required this.onAttach,
    required this.onCancelContext,
    required this.onCancelUpload,
    required this.onRemovePending,
    required this.recordingVoice,
    required this.onStartVoice,
    required this.onVoiceSent,
    required this.onVoiceCancel,
  });

  @override
  State<ChannelComposer> createState() => _ChannelComposerState();
}

class _ChannelComposerState extends State<ChannelComposer> {
  bool _showFormatting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.replyTo != null || widget.editing)
            _ContextBanner(
              text: widget.editing
                  ? l10n.translate('chan_editing')
                  : l10n.translate('chan_reply_to',
                      args: {'name': widget.replyTo!.senderName}),
              onCancel: widget.onCancelContext,
            ),
          if (widget.pending.isNotEmpty)
            _PendingRow(
              pending: widget.pending,
              onRemove: widget.sending ? null : widget.onRemovePending,
            ),
          if (widget.sending && widget.uploadLabel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.uploadLabel!,
                            style: TextStyle(
                                color: context.forest.text54, fontSize: 11)),
                        const SizedBox(height: 3),
                        LinearProgressIndicator(
                          value: widget.uploadProgress,
                          color: AppColors.mintGreen,
                          backgroundColor: context.forest.divider10,
                          minHeight: 3,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.translate('tour_cancel'),
                    icon: Icon(Icons.close, color: context.forest.text54),
                    onPressed: widget.onCancelUpload,
                  ),
                ],
              ),
            ),
          if (widget.mentionChoices.isNotEmpty)
            _MentionList(
                choices: widget.mentionChoices, onPick: widget.onPickMention),
          if (_showFormatting)
            ChatFormattingToolbar(
              controller: widget.controller,
              focusNode: widget.focusNode,
              onClose: () => setState(() => _showFormatting = false),
            ),
          if (widget.recordingVoice)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: VoiceMessageRecorder(
                onVoiceSent: widget.onVoiceSent,
                onCancel: widget.onVoiceCancel,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: l10n.translate('chan_attach_tooltip'),
                    icon: Icon(Icons.attach_file, color: context.forest.text70),
                    onPressed: widget.sending ? null : widget.onAttach,
                  ),
                  IconButton(
                    tooltip: l10n.translate('format_toolbar_toggle'),
                    padding: EdgeInsets.zero,
                    icon: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2.5),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _showFormatting
                              ? AppColors.mintGreen
                              : context.forest.text70,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        color: _showFormatting
                            ? AppColors.mintGreen.withValues(alpha: 0.15)
                            : Colors.transparent,
                      ),
                      child: Text(
                        'Aa',
                        style: TextStyle(
                          color: _showFormatting
                              ? AppColors.mintGreen
                              : context.forest.text70,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    onPressed: widget.sending
                        ? null
                        : () =>
                            setState(() => _showFormatting = !_showFormatting),
                  ),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onChanged: widget.onChanged,
                      onSubmitted: (_) => widget.onSend(),
                      style: TextStyle(color: context.forest.text),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: widget.hint,
                        hintStyle: TextStyle(
                            color: context.forest.text54, fontSize: 13),
                        filled: true,
                        fillColor: context.forest.inset26,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.controller,
                    builder: (context, value, _) {
                      final canRecord = !widget.sending &&
                          !widget.editing &&
                          widget.pending.isEmpty &&
                          value.text.trim().isEmpty;
                      if (canRecord) {
                        return IconButton(
                          tooltip: l10n.translate('chan_voice_tooltip'),
                          icon: Icon(Icons.mic_rounded,
                              color: context.forest.accentText),
                          onPressed: widget.onStartVoice,
                        );
                      }
                      return IconButton(
                        tooltip: l10n.translate('tour_send'),
                        icon: widget.sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: AppColors.mintGreen, strokeWidth: 2),
                              )
                            : Icon(Icons.send_rounded,
                                color: context.forest.accentText),
                        onPressed: widget.sending ? null : widget.onSend,
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ContextBanner extends StatelessWidget {
  final String text;
  final VoidCallback onCancel;

  const _ContextBanner({required this.text, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: const BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.all(Radius.circular(8)),
        border: Border(left: BorderSide(color: AppColors.gold, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: context.l10n.translate('tour_cancel'),
            icon: const Icon(Icons.close, size: 18, color: Colors.white54),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  final List<PendingAttachment> pending;
  final ValueChanged<int>? onRemove;

  const _PendingRow({required this.pending, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        itemCount: pending.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final item = pending[i];
          return Chip(
            avatar: Icon(
              item.isVideo
                  ? Icons.videocam
                  : item.isDocument
                      ? Icons.insert_drive_file
                      : Icons.photo,
              size: 16,
              color: AppColors.mintGreen,
            ),
            label: Text(
              item.isVideo
                  ? l10n.translate('chan_attachment_video_label')
                  : item.file.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            backgroundColor: Colors.black26,
            onDeleted: onRemove == null ? null : () => onRemove!(i),
            deleteIconColor: Colors.white54,
            deleteButtonTooltipMessage:
                l10n.translate('chan_remove_attachment'),
          );
        },
      ),
    );
  }
}

class _MentionList extends StatelessWidget {
  final List<MentionChoice> choices;
  final ValueChanged<MentionChoice> onPick;

  const _MentionList({required this.choices, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      constraints: const BoxConstraints(maxHeight: 200),
      child: Material(
        color: context.forest.surfaceFor(const Color(0xFF1E3326)),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            for (final choice in choices)
              ListTile(
                dense: true,
                leading: Icon(Icons.alternate_email,
                    size: 18, color: context.forest.accentText),
                title: Text(
                  choice.display,
                  style: TextStyle(color: context.forest.text, fontSize: 13),
                ),
                onTap: () => onPick(choice),
              ),
          ],
        ),
      ),
    );
  }
}
