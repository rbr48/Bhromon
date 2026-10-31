import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import '../../../../core/utils/app_logger.dart';
import 'media_rules.dart';
import 'web_video_plan.dart';
import 'web_video_transcoder.dart';

/// A compression the user stopped. It is not an error to show.
class TourVideoCompressionCancelled implements Exception {
  const TourVideoCompressionCancelled();
}

/// A compression that could not bring the video under the size limit.
class TourVideoCompressionException implements Exception {
  final String message;
  const TourVideoCompressionException(this.message);

  @override
  String toString() => message;
}

/// Service to handle client-side automatic video compression for Reels.
/// Optimizes large camera/4K/high-bitrate videos into smooth, web-streamable
/// 720p H.264 MP4 videos under [kMaxVideoBytes].
class TourVideoCompressor {
  TourVideoCompressor._();

  static bool _active = false;
  static bool _cancelRequested = false;

  static const String _couldNotCompress =
      'ভিডিওটি সংকুচিত করা যায়নি। ছোট ভিডিও বাছাই করুন।';
  static const String _stillTooLarge =
      'ভিডিওটি সীমার চেয়ে বড় রয়ে গেছে। ছোট ভিডিও বাছাই করুন।';

  /// Compresses [sourceFile] if its size exceeds [targetMaxBytes].
  ///
  /// Emits progress from 0.0 to 1.0 on [onProgress].
  /// Returns an [XFile] pointing to the compressed video, or the original
  /// [sourceFile] if no compression was needed. On the web the video is
  /// shrunk in the browser instead of by the native transcoder.
  ///
  /// Throws [TourVideoCompressionCancelled] after [cancel], and
  /// [TourVideoCompressionException] when even the lowest quality is still over
  /// [targetMaxBytes]. Either way the output file is deleted.
  static Future<XFile> compressIfNeeded({
    required XFile sourceFile,
    int targetMaxBytes = kMaxVideoBytes,
    void Function(double progress)? onProgress,
  }) async {
    final originalSize = await sourceFile.length();
    if (originalSize <= targetMaxBytes) {
      return sourceFile;
    }
    if (kIsWeb) {
      return _compressInBrowser(
        sourceFile: sourceFile,
        originalSize: originalSize,
        targetMaxBytes: targetMaxBytes,
        onProgress: onProgress,
      );
    }

    logInfo(
      'TourVideoCompressor: Compressing video (${formatMegabytes(originalSize)}) to fit under ${formatMegabytes(targetMaxBytes)}...',
    );

    Subscription? progressSub;
    if (onProgress != null) {
      progressSub = VideoCompress.compressProgress$.subscribe((progress) {
        onProgress(progress / 100.0);
      });
    }

    _active = true;
    _cancelRequested = false;
    try {
      // Medium quality first: 720p H.264 is the standard for Reels.
      final medium = (await VideoCompress.compressVideo(
        sourceFile.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      ))
          ?.file;

      var output = medium;
      if (medium != null && medium.existsSync()) {
        final mediumSize = await medium.length();
        if (mediumSize > targetMaxBytes) {
          logInfo(
            'TourVideoCompressor: Video still ${formatMegabytes(mediumSize)}, applying aggressive compression...',
          );
          // The second pass re-encodes the medium output, which is already
          // smaller than the source, then the medium file is freed.
          output = (await VideoCompress.compressVideo(
            medium.path,
            quality: VideoQuality.LowQuality,
            deleteOrigin: false,
            includeAudio: true,
          ))
              ?.file;
          if (medium.existsSync()) await medium.delete();
        }
      }

      if (_cancelRequested) {
        if (output != null && output.existsSync()) await output.delete();
        throw const TourVideoCompressionCancelled();
      }
      if (output == null || !output.existsSync()) {
        throw const TourVideoCompressionException(_couldNotCompress);
      }

      final compressedSize = await output.length();
      if (compressedSize > targetMaxBytes) {
        await output.delete();
        throw const TourVideoCompressionException(_stillTooLarge);
      }

      logInfo(
        'TourVideoCompressor: Compression complete: ${formatMegabytes(originalSize)} -> ${formatMegabytes(compressedSize)}',
      );
      onProgress?.call(1.0);
      return XFile(output.path);
    } catch (e, st) {
      if (_cancelRequested) throw const TourVideoCompressionCancelled();
      logWarning('TourVideoCompressor error', e, st);
      rethrow;
    } finally {
      progressSub?.unsubscribe();
      _active = false;
    }
  }

  /// The browser shrinks the video in the same two steps as the native
  /// transcoder: 720p first, then 480p if the result is still too large.
  static Future<XFile> _compressInBrowser({
    required XFile sourceFile,
    required int originalSize,
    required int targetMaxBytes,
    void Function(double progress)? onProgress,
  }) async {
    if (originalSize > kMaxWebVideoSourceBytes ||
        !WebVideoTranscoder.isSupported) {
      throw const TourVideoCompressionException(_couldNotCompress);
    }

    logInfo(
      'TourVideoCompressor: Shrinking video in the browser (${formatMegabytes(originalSize)}) to fit under ${formatMegabytes(targetMaxBytes)}...',
    );

    _active = true;
    _cancelRequested = false;
    try {
      final bytes = await sourceFile.readAsBytes();
      final info = await WebVideoTranscoder.probe(bytes);
      if (info == null) {
        throw const TourVideoCompressionException(_couldNotCompress);
      }
      final passes = webVideoPasses(
        durationSeconds: info.durationSeconds,
        targetMaxBytes: targetMaxBytes,
      );
      for (var index = 0; index < passes.length; index++) {
        final output = await WebVideoTranscoder.transcode(
          bytes,
          passes[index],
          onProgress: (progress) =>
              onProgress?.call((index + progress) / passes.length),
        );
        if (_cancelRequested || output == null) {
          throw const TourVideoCompressionCancelled();
        }
        if (output.length <= targetMaxBytes) {
          logInfo(
            'TourVideoCompressor: Browser compression complete: ${formatMegabytes(originalSize)} -> ${formatMegabytes(output.length)}',
          );
          onProgress?.call(1.0);
          return XFile.fromData(
            output,
            name: 'reel.mp4',
            mimeType: 'video/mp4',
          );
        }
        logInfo(
          'TourVideoCompressor: Video still ${formatMegabytes(output.length)}, trying a smaller size...',
        );
      }
      throw const TourVideoCompressionException(_stillTooLarge);
    } catch (e, st) {
      if (_cancelRequested || e is TourVideoCompressionCancelled) {
        throw const TourVideoCompressionCancelled();
      }
      if (e is TourVideoCompressionException) rethrow;
      logWarning('TourVideoCompressor browser error', e, st);
      throw const TourVideoCompressionException(_couldNotCompress);
    } finally {
      _active = false;
    }
  }

  /// Stops the compression in progress, if there is one. The pending
  /// [compressIfNeeded] then throws [TourVideoCompressionCancelled].
  static Future<void> cancel() async {
    if (!_active) return;
    _cancelRequested = true;
    if (kIsWeb) {
      WebVideoTranscoder.cancel();
      return;
    }
    try {
      await VideoCompress.cancelCompression();
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  /// Deletes cached video compression artifacts to free disk space.
  static Future<void> clearCache() async {
    if (!kIsWeb) {
      try {
        await VideoCompress.deleteAllCache();
      } catch (error, stackTrace) {
        logSkipped(error, stackTrace);
      }
    }
  }
}
