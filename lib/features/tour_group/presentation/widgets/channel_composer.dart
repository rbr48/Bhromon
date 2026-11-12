import 'package:flutter/material.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../domain/models/channel_models.dart';
import '../../../chat/presentation/widgets/chat_formatting_toolbar.dart';
import '../../../chat/presentation/widgets/voice_message_recorder.dart';
import '../../../chat/data/web_paste_listener.dart';
import '../../../chat/presentation/widgets/composer_paste.dart';
import '../../../share_intake/domain/shared_file.dart';

/// A photo, video, or file picked for the next message, not yet uploaded.
class PendingAttachment {
  final XFile file;
  final bool isVideo;
  final bool isDocument;
  final bool isAudio;
  final int? fileSizeBytes;

  const PendingAttachment({
    required this.file,
    this.isVideo = false,
    this.isDocument = false,
    this.isAudio = false,
    this.fileSizeBytes,
  });
}

/// The pending attachment for a pasted file the member has confirmed. Its kind comes from its
/// name, the way the uploader and the server read it.
PendingAttachment pendingAttachmentFor(SharedFile file) {
  final path = file.path;
  if (path == null) {
    throw StateError(
        'The file was not copied before it was sent: ${file.name}');
  }
  final size = file.sizeBytes >= 0 ? file.sizeBytes : null;
  final xfile = XFile(path, name: file.name, length: size);
  return switch (sharedFileKind(file.name)) {
    SharedFileKind.image => PendingAttachment(file: xfile),
    SharedFileKind.video => PendingAttachment(file: xfile, isVideo: true),
    SharedFileKind.audio => PendingAttachment(file: xfile, isAudio: true),
    SharedFileKind.document => PendingAttachment(
        file: xfile,
        isDocument: true,
        fileSizeBytes: size,
      ),
    null => throw StateError('The file has no supported type: ${file.name}'),
  };
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

  /// Files pasted or inserted into the box. The screen shows them for review before anything is
  /// sent.
  final ValueChanged<List<SharedFile>> onPastedFiles;

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
    required this.onPastedFiles,
  });

  @override
  State<ChannelComposer> createState() => _ChannelComposerState();
}

class _ChannelComposerState extends State<ChannelComposer> {
  bool _showFormatting = false;
  void Function()? _stopWebPaste;

  /// Paste and keyboard insertion. The files go up to the screen, which shows them for review.
  late final ComposerPaste _paste = ComposerPaste(
    onFiles: (files) => widget.onPastedFiles(files),
    onFailed: _showReadFailed,
  );

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // A file pasted while this box has focus is taken, as it is in the chat box. A paste while
      // the box is busy, or while a voice note is being recorded, is left to the browser.
      _stopWebPaste = attachWebPasteListener(
        accept: () =>
            mounted &&
            widget.focusNode.hasFocus &&
            !widget.sending &&
            !widget.editing &&
            !widget.recordingVoice,
        onFiles: (files) => widget.onPastedFiles(files),
      );
    }
  }

  @override
  void dispose() {
    _stopWebPaste?.call();
    super.dispose();
  }

  void _showReadFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.translate('chan_file_read_failed')),
        backgroundColor: AppColors.amber,
      ),
    );
  }

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
                                color: context.forest.text54, fontSize: 12)),
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
                    icon:
                        Icon(Icons.close_rounded, color: context.forest.text54),
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.forest.inset26,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: TextField(
                                controller: widget.controller,
                                focusNode: widget.focusNode,
                                minLines: 1,
                                maxLines: 6,
                                textInputAction: TextInputAction.send,
                                onChanged: widget.onChanged,
                                onSubmitted: (_) => widget.onSend(),
                                contentInsertionConfiguration: _paste.insertion,
                                contextMenuBuilder: _paste.contextMenu,
                                style: TextStyle(
                                  color: context.forest.text,
                                  fontSize: 16,
                                  height: 1.38,
                                  letterSpacing: 0.05,
                                  fontFamily: 'NotoSansBengali',
                                  fontFamilyFallback: const [
                                    'HindSiliguri',
                                    'Roboto',
                                    'sans-serif'
                                  ],
                                ),
                                decoration: InputDecoration(
                                  counterText: '',
                                  hintText: widget.hint,
                                  hintStyle: TextStyle(
                                    color: context.forest.text54,
                                    fontSize: 15,
                                    fontFamily: 'NotoSansBengali',
                                    fontFamilyFallback: const [
                                      'HindSiliguri',
                                      'Roboto',
                                      'sans-serif'
                                    ],
                                  ),
                                  border: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ),
                          Semantics(
                            label: l10n.translate('format_toolbar_toggle'),
                            button: true,
                            child: SizedBox(
                              width: 32,
                              height: 48,
                              child: IconButton(
                                tooltip:
                                    l10n.translate('format_toolbar_toggle'),
                                padding: EdgeInsets.zero,
                                icon: Text(
                                  'Aa',
                                  style: TextStyle(
                                    color: _showFormatting
                                        ? AppColors.mintGreen
                                        : context.forest.text70,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    letterSpacing: -0.5,
                                    decoration: _showFormatting
                                        ? TextDecoration.underline
                                        : TextDecoration.none,
                                    decorationColor: AppColors.mintGreen,
                                  ),
                                ),
                                onPressed: widget.sending
                                    ? null
                                    : () => setState(() =>
                                        _showFormatting = !_showFormatting),
                              ),
                            ),
                          ),
                          Semantics(
                            label: l10n.translate('chan_attach_tooltip'),
                            button: true,
                            child: SizedBox(
                              width: 34,
                              height: 48,
                              child: IconButton(
                                tooltip: l10n.translate('chan_attach_tooltip'),
                                padding: EdgeInsets.zero,
                                icon: Icon(Icons.attach_file_rounded,
                                    color: context.forest.text70, size: 22),
                                onPressed:
                                    widget.sending ? null : widget.onAttach,
                              ),
                            ),
                          ),
                        ],
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
            icon: const Icon(Icons.close_rounded,
                size: 18, color: Colors.white54),
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
                  ? Icons.videocam_rounded
                  : item.isAudio
                      ? Icons.mic_rounded
                      : item.isDocument
                          ? Icons.insert_drive_file_rounded
                          : Icons.photo_rounded,
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
        color: context.forest.surfaceFor(AppColors.forestRaised),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            for (final choice in choices)
              ListTile(
                dense: true,
                leading: Icon(Icons.alternate_email_rounded,
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
