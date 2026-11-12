import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../share_intake/domain/shared_file.dart';
import '../../domain/pasted_files.dart';

/// What the member chose to send from a review.
class PastedReview {
  const PastedReview({required this.files, required this.caption});

  /// The files left in the review, in the order they were shown.
  final List<SharedFile> files;

  /// The caption, trimmed. Empty when the review has no caption field, or none was written.
  final String caption;
}

/// Shows files pasted into a message box before anything is sent, the way a messaging app shows
/// a picture before it sends it. A file can be taken out, and a caption added where the message
/// takes one. Send returns a [PastedReview]. Closing the screen returns nothing, and nothing is
/// sent.
class PastedFilesReviewScreen extends StatefulWidget {
  const PastedFilesReviewScreen({
    super.key,
    required this.files,
    required this.allowCaption,
    this.captionMaxLength,
  });

  final List<SharedFile> files;

  /// Whether the message takes a caption.
  final bool allowCaption;

  /// The most characters a caption may hold, when the message has a limit.
  final int? captionMaxLength;

  @override
  State<PastedFilesReviewScreen> createState() =>
      _PastedFilesReviewScreenState();
}

class _PastedFilesReviewScreenState extends State<PastedFilesReviewScreen> {
  late final List<SharedFile> _files = [...widget.files];
  final TextEditingController _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _remove(int index) => setState(() => _files.removeAt(index));

  void _send() {
    if (_files.isEmpty) return;
    Navigator.of(context).pop(PastedReview(
      files: List.unmodifiable(_files),
      caption: widget.allowCaption ? _caption.text.trim() : '',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.translate('tour_cancel'),
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.translate(
          'paste_review_count',
          args: {'count': l10n.number(_files.length)},
        )),
      ),
      body: Column(
        children: [
          Expanded(
            child: _files.isEmpty
                ? Center(
                    child: Text(
                      l10n.translate('paste_review_none'),
                      style: TextStyle(color: context.forest.text54),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 160,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: _files.length,
                    itemBuilder: (context, index) => _PreviewTile(
                      key: ObjectKey(_files[index]),
                      file: _files[index],
                      onRemove: () => _remove(index),
                    ),
                  ),
          ),
          if (widget.allowCaption)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: TextField(
                controller: _caption,
                minLines: 1,
                maxLines: 4,
                maxLength: widget.captionMaxLength,
                decoration: InputDecoration(
                  hintText: l10n.translate('paste_review_caption'),
                  filled: true,
                  fillColor: context.forest.inset26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.translate('tour_send'),
        backgroundColor: AppColors.mintGreen,
        foregroundColor: AppColors.darkGreen,
        onPressed: _files.isEmpty ? null : _send,
        child: const Icon(Icons.send_rounded),
      ),
    );
  }
}

/// One file in the review: a photo shown as its picture, and any other file as its name, kind
/// and size.
class _PreviewTile extends StatefulWidget {
  const _PreviewTile({super.key, required this.file, required this.onRemove});

  final SharedFile file;
  final VoidCallback onRemove;

  @override
  State<_PreviewTile> createState() => _PreviewTileState();
}

class _PreviewTileState extends State<_PreviewTile> {
  /// The photo's bytes, read once. Null for a file that is not a photo.
  Future<Uint8List>? _picture;

  @override
  void initState() {
    super.initState();
    if (sharedFileKind(widget.file.name) == SharedFileKind.image) {
      _picture = _readPicture();
    }
  }

  Future<Uint8List> _readPicture() async {
    final path = widget.file.path;
    if (path == null) {
      throw StateError('The file has no path: ${widget.file.name}');
    }
    return XFile(path, name: widget.file.name).readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final kind = sharedFileKind(widget.file.name);
    final label = switch (kind) {
      SharedFileKind.image => l10n.translate('paste_review_photo'),
      SharedFileKind.video => l10n.translate('chan_attachment_video_label'),
      SharedFileKind.audio => l10n.translate('paste_review_audio'),
      SharedFileKind.document ||
      null =>
        l10n.translate('paste_review_document'),
    };
    return Semantics(
      label: '$label, ${widget.file.name}',
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: context.forest.inset26,
              child: _picture != null ? _pictureView() : _fileView(kind),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: l10n.translate('paste_review_remove'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 18),
                onPressed: widget.onRemove,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pictureView() {
    return FutureBuilder<Uint8List>(
      future: _picture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
        }
        if (snapshot.hasError) {
          return Center(
            child:
                Icon(Icons.broken_image_rounded, color: context.forest.text54),
          );
        }
        return const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      },
    );
  }

  Widget _fileView(SharedFileKind? kind) {
    final icon = switch (kind) {
      SharedFileKind.video => Icons.videocam_rounded,
      SharedFileKind.audio => Icons.mic_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
    final size = pastedFileSizeLabel(widget.file.sizeBytes);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 30, 10, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: AppColors.mintGreen),
          const SizedBox(height: 8),
          Text(
            widget.file.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.forest.text, fontSize: 12),
          ),
          if (size.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              size,
              style: TextStyle(color: context.forest.text54, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
