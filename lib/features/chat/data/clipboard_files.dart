import 'package:bhromon/core/utils/logger.dart';
import 'package:bhromon/features/share_intake/domain/shared_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads files from the Android clipboard, and copies one file the keyboard inserted. The
/// activity copies each file into the app's cache, so the chat can send it the way it sends a
/// shared file. Text is never read here: a paste with no files falls through to the text field.
///
/// Only Android has this channel. On the web, the paste event supplies the files instead (see
/// web_paste_listener.dart). On iOS a paste of files is not supported yet, and the text is pasted.
class ClipboardFiles {
  ClipboardFiles._();

  /// The activity's share channel, which also serves the clipboard and the keyboard.
  static const MethodChannel _channel =
      MethodChannel('com.bhromon.app/share_intake');

  /// Whether this platform reads files through the activity.
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// The files on the clipboard, copied into the cache. Empty when there are none, or when this
  /// platform cannot read them. A file that could not be copied keeps no path, so the chat
  /// refuses it with the reason.
  static Future<List<SharedFile>> readClipboard() async {
    if (!supported) return const [];
    try {
      final raw = await _channel
          .invokeListMethod<Map<Object?, Object?>>('readClipboardFiles');
      return [
        for (final item in raw ?? const <Map<Object?, Object?>>[])
          SharedFile.fromMap(item),
      ];
    } on PlatformException catch (e, st) {
      logWarning('[Clipboard] could not read the clipboard files', e, st);
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// One item the keyboard inserted, such as a sticker, GIF or image, copied into the cache.
  /// Null when the platform cannot read it or it could not be copied.
  static Future<SharedFile?> copyContentUri(String uri) async {
    if (!supported) return null;
    try {
      final raw = await _channel
          .invokeMapMethod<Object?, Object?>('copyContentUri', {'uri': uri});
      return raw == null ? null : SharedFile.fromMap(raw);
    } on PlatformException catch (e, st) {
      logWarning('[Clipboard] could not copy the inserted content', e, st);
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
