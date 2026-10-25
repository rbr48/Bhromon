import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import 'media_rules.dart';

/// Service to handle client-side automatic video compression for Reels.
/// Optimizes large camera/4K/high-bitrate videos into smooth, web-streamable
/// 720p H.264 MP4 videos under [kMaxVideoBytes].
class TourVideoCompressor {
  TourVideoCompressor._();

  /// Compresses [sourceFile] if its size exceeds [targetMaxBytes].
  ///
  /// Emits progress from 0.0 to 1.0 on [onProgress].
  /// Returns an [XFile] pointing to the compressed video, or the original
  /// [sourceFile] if no compression was needed (or on Web where native
  /// transcoders are unavailable).
  static Future<XFile> compressIfNeeded({
    required XFile sourceFile,
    int targetMaxBytes = kMaxVideoBytes,
    void Function(double progress)? onProgress,
  }) async {
    final originalSize = await sourceFile.length();
    if (originalSize <= targetMaxBytes || kIsWeb) {
      return sourceFile;
    }

    debugPrint(
      'TourVideoCompressor: Compressing video (${formatMegabytes(originalSize)}) to fit under ${formatMegabytes(targetMaxBytes)}...',
    );

    Subscription? progressSub;
    if (onProgress != null) {
      progressSub = VideoCompress.compressProgress$.subscribe((progress) {
        onProgress(progress / 100.0);
      });
    }

    try {
      // First attempt: Medium Quality (720p H.264 standard for Reels)
      MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        sourceFile.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );

      // If medium is somehow still larger than limit (rare), compress to Default/Low
      if (mediaInfo != null &&
          mediaInfo.filesize != null &&
          mediaInfo.filesize! > targetMaxBytes) {
        debugPrint(
          'TourVideoCompressor: Video still ${formatMegabytes(mediaInfo.filesize!)}, applying aggressive compression...',
        );
        mediaInfo = await VideoCompress.compressVideo(
          sourceFile.path,
          quality: VideoQuality.LowQuality,
          deleteOrigin: false,
          includeAudio: true,
        );
      }

      if (mediaInfo?.file != null && mediaInfo!.file!.existsSync()) {
        final compressedSize = await mediaInfo.file!.length();
        debugPrint(
          'TourVideoCompressor: Compression complete: ${formatMegabytes(originalSize)} -> ${formatMegabytes(compressedSize)}',
        );
        onProgress?.call(1.0);
        return XFile(mediaInfo.file!.path);
      } else {
        throw Exception('Compressed file was not generated.');
      }
    } catch (e) {
      debugPrint('TourVideoCompressor error: $e');
      rethrow;
    } finally {
      progressSub?.unsubscribe();
    }
  }

  /// Cancels active video compression, if any.
  static Future<void> cancel() async {
    if (!kIsWeb) {
      try {
        await VideoCompress.cancelCompression();
      } catch (_) {}
    }
  }

  /// Deletes cached video compression artifacts to free disk space.
  static Future<void> clearCache() async {
    if (!kIsWeb) {
      try {
        await VideoCompress.deleteAllCache();
      } catch (_) {}
    }
  }
}
