import 'dart:async';

import 'package:flutter/material.dart';

import '../../../share_intake/domain/shared_file.dart';
import '../../data/clipboard_files.dart';

/// Paste and keyboard insertion for a message box. The chat box and the channel boxes both use
/// it, so a file is taken the same way everywhere.
///
/// Stickers, GIFs and images from the keyboard arrive as content and are copied into the cache.
/// The text field's Paste takes the clipboard's files first, and pastes the text when the
/// clipboard holds no files. Each file goes to [onFiles], and the caller shows it for review
/// before anything is sent.
class ComposerPaste {
  ComposerPaste({required this.onFiles, required this.onFailed});

  /// Receives the files, in the order they were copied.
  final void Function(List<SharedFile> files) onFiles;

  /// Called when keyboard content could not be copied into the app.
  final void Function() onFailed;

  /// The keyboard insertion for the text field.
  ContentInsertionConfiguration get insertion => ContentInsertionConfiguration(
        onContentInserted: (content) => unawaited(_receive(content)),
      );

  Future<void> _receive(KeyboardInsertedContent content) async {
    final file = await ClipboardFiles.copyContentUri(content.uri);
    if (file == null) {
      onFailed();
      return;
    }
    onFiles([file]);
  }

  /// The text field's menu. Its Paste takes files from the clipboard first. Flutter shows the
  /// standard Paste only when the clipboard holds text, so one is added when it is missing: an
  /// image or a file copied from another app would otherwise have no Paste at all.
  Widget contextMenu(BuildContext context, EditableTextState state) {
    final items = <ContextMenuButtonItem>[];
    var hasPaste = false;
    for (final item in state.contextMenuButtonItems) {
      if (item.kind == ContextMenuButtonKind.paste) {
        hasPaste = true;
        items.add(_pasteButton(state));
      } else {
        items.add(item);
      }
    }
    if (!hasPaste) items.add(_pasteButton(state));
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: items,
    );
  }

  ContextMenuButtonItem _pasteButton(EditableTextState state) {
    return ContextMenuButtonItem(
      kind: ContextMenuButtonKind.paste,
      onPressed: () => unawaited(_paste(state)),
    );
  }

  Future<void> _paste(EditableTextState state) async {
    state.hideToolbar();
    final files = await ClipboardFiles.readClipboard();
    if (files.isNotEmpty) {
      onFiles(files);
      return;
    }
    await state.pasteText(SelectionChangedCause.toolbar);
  }
}
