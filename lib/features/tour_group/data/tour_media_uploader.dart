import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../domain/services/media_rules.dart';

/// A user-facing upload failure. The message is shown as-is.
class TourUploadException implements Exception {
  final String message;
  const TourUploadException(this.message);

  @override
  String toString() => message;
}

/// Thrown by [TourMediaUpload.finish] after [TourMediaUpload.cancel].
class TourUploadCancelled implements Exception {
  const TourUploadCancelled();
}

/// One file on its way to VPS media storage. Cancel it, wait for it, or delete
/// it again if the post it belongs to is never saved.
class TourMediaUpload {
  static const Duration _maxWait = Duration(minutes: 20);

  final Future<String> Function() _finishFn;
  final Stream<double> _progressStream;
  final CancelToken _cancelToken;
  final Future<void> Function() _discardFn;

  const TourMediaUpload._({
    required Future<String> Function() finishFn,
    required Stream<double> progressStream,
    required CancelToken cancelToken,
    required Future<void> Function() discardFn,
  })  : _finishFn = finishFn,
        _progressStream = progressStream,
        _cancelToken = cancelToken,
        _discardFn = discardFn;

  /// Progress from 0.0 to 1.0.
  Stream<double> get progress => _progressStream;

  /// Waits for the upload and returns its download URL.
  Future<String> finish() async {
    try {
      return await _finishFn().timeout(_maxWait);
    } on TourUploadCancelled {
      rethrow;
    } on TimeoutException {
      await cancel();
      throw const TourUploadException(
          'আপলোড শেষ হয়নি। ইন্টারনেট সংযোগ দেখে আবার চেষ্টা করুন।');
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        throw const TourUploadCancelled();
      }
      if (e is TourUploadException) rethrow;
      throw TourUploadException(
          'আপলোড ব্যর্থ হয়েছে: $e। ইন্টারনেট সংযোগ দেখে আবার চেষ্টা করুন।');
    }
  }

  Future<void> cancel() async {
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel();
    }
  }

  /// Deletes the uploaded file. Failures are ignored: the file is orphaned at
  /// worst, and the post still was not created.
  Future<void> discard() async {
    try {
      await _discardFn();
    } catch (_) {}
  }
}

class TourMediaUploader {
  static const String baseUrl = 'https://bhromon.fun';
  static const String uploadUrl = '$baseUrl/api/media/upload';
  static const String deleteBaseUrl = '$baseUrl/api/media/media';
  static const String uploadKey = 'bhromon_vps_media_2026_sec';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(minutes: 20),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );

  /// Uploads [file] to the dedicated VPS media server under {tourId}/{folder}/
  /// with streaming support and high-performance CDN delivery.
  /// Size and type are validated beforehand.
  static Future<TourMediaUpload> start({
    required String tourId,
    required String folder,
    required XFile file,
    required String contentType,
    required String extension,
    required int maxBytes,
    required String uploaderEmail,
  }) async {
    final size = await file.length();
    if (size == 0) {
      throw const TourUploadException('ফাইলটি খালি। অন্য ফাইল বাছাই করুন।');
    }
    if (size > maxBytes) {
      throw TourUploadException(
          'ফাইলটি খুব বড় (${formatMegabytes(size)})। সর্বোচ্চ ${formatMegabytes(maxBytes)} হতে পারে।');
    }

    final cancelToken = CancelToken();
    double currentProgress = 0.0;
    StreamController<double>? progressController;
    progressController = StreamController<double>.broadcast(
      onListen: () {
        if (!progressController!.isClosed) {
          progressController.add(currentProgress);
        }
      },
    );

    String? uploadedUrl;

    Future<String> executeUpload() async {
      try {
        final filename = '${const Uuid().v4()}.$extension';
        final MultipartFile multipartFile;

        if (kIsWeb) {
          final bytes = await file.readAsBytes();
          multipartFile = MultipartFile.fromBytes(
            bytes,
            filename: filename,
          );
        } else {
          multipartFile = await MultipartFile.fromFile(
            file.path,
            filename: filename,
          );
        }

        final formData = FormData.fromMap({
          'file': multipartFile,
          'tourId': tourId,
          'folder': folder,
          'uploaderEmail': uploaderEmail,
        });

        final response = await _dio.post<Map<String, dynamic>>(
          uploadUrl,
          data: formData,
          cancelToken: cancelToken,
          options: Options(
            headers: {
              'X-Upload-Key': uploadKey,
            },
          ),
          onSendProgress: (sent, total) {
            if (total > 0) {
              currentProgress = sent / total;
              if (!progressController!.isClosed) {
                progressController.add(currentProgress);
              }
            }
          },
        );

        if (response.statusCode != 200 || response.data == null) {
          throw TourUploadException(
              'আপলোড সম্পন্ন করা যায়নি (কোড: ${response.statusCode})');
        }

        final data = response.data!;
        final url = data['url'] as String?;
        if (url == null || url.isEmpty) {
          throw const TourUploadException(
              'সার্ভার থেকে সঠিক ইউআরএল পাওয়া যায়নি।');
        }

        uploadedUrl = url;
        currentProgress = 1.0;
        if (!progressController!.isClosed) {
          progressController.add(1.0);
        }
        return url;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          throw const TourUploadCancelled();
        }
        final msg = e.response?.data is Map
            ? (e.response!.data as Map)['detail']?.toString()
            : e.message;
        throw TourUploadException(
            'আপলোড ব্যর্থ হয়েছে: ${msg ?? "নেটওয়ার্ক সমস্যা"}');
      } finally {
        if (!progressController!.isClosed) {
          await progressController.close();
        }
      }
    }

    final uploadFuture = executeUpload();

    return TourMediaUpload._(
      finishFn: () => uploadFuture,
      progressStream: progressController.stream,
      cancelToken: cancelToken,
      discardFn: () async {
        if (!cancelToken.isCancelled) {
          cancelToken.cancel();
        }
        if (uploadedUrl != null) {
          await deleteMedia(uploadedUrl!);
        }
      },
    );
  }

  /// Deletes a remote media file from the VPS or Firebase Storage.
  static Future<void> deleteMedia(String url) async {
    try {
      final uri = Uri.parse(url);
      if (uri.path.startsWith('/media/')) {
        final segments = uri.pathSegments; // ['media', tourId, folder, filename]
        if (segments.length >= 4) {
          final tourId = segments[1];
          final folder = segments[2];
          final filename = segments[3];
          final deleteUrl = '$deleteBaseUrl/$tourId/$folder/$filename';
          await _dio.delete<dynamic>(
            deleteUrl,
            options: Options(
              headers: {'X-Upload-Key': uploadKey},
            ),
          );
          return;
        }
      }

      // Fallback for legacy Firebase Storage URLs
      if (url.contains('firebasestorage.googleapis.com')) {
        await FirebaseStorage.instance.refFromURL(url).delete();
      }
    } catch (e) {
      debugPrint('[TourMediaUploader] Could not delete media ($url): $e');
    }
  }
}
