import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../domain/services/media_rules.dart';
import 'tour_media_journal.dart';

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

/// One file on its way to the media server.
///
/// The file stays in the [TourMediaJournal] until [commit] (it was saved in a
/// post or story) or until [discard] removes it. A crash in between is cleaned
/// up by the journal sweep.
class TourMediaUpload {
  static const Duration _maxWait = Duration(minutes: 20);

  final List<TourMediaRef> _refHolder;
  TourMediaRef get ref => _refHolder[0];

  final TourMediaJournal _journal;
  final Future<String> Function() _finishFn;
  final Stream<double> _progressStream;
  final CancelToken _cancelToken;
  bool _settled = false;

  TourMediaUpload._({
    required TourMediaRef ref,
    required TourMediaJournal journal,
    required Future<String> Function() finishFn,
    required Stream<double> progressStream,
    required CancelToken cancelToken,
    List<TourMediaRef>? refHolder,
  })  : _refHolder = refHolder ?? [ref],
        _journal = journal,
        _finishFn = finishFn,
        _progressStream = progressStream,
        _cancelToken = cancelToken;

  /// Progress from 0.0 to 1.0.
  Stream<double> get progress => _progressStream;

  /// Waits for the upload and returns its URL.
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
    } finally {
      _settled = true;
    }
  }

  Future<void> cancel() async {
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel();
    }
  }

  /// Called once the post or story that uses this file is saved. The file is
  /// no longer an orphan, so the journal forgets it.
  Future<void> commit() => _journal.resolve(ref.url);

  /// Removes the file because the post or story that needed it was not saved.
  ///
  /// The file is removed at once only when the upload has finished. A running
  /// upload might still store the file after the delete, so its journal entry
  /// is kept for the sweep to remove later.
  Future<void> discard() async {
    await cancel();
    await _journal.markDelete(ref);
    final gone = await TourMediaUploader.deleteMedia(ref.url);
    if (gone && _settled) {
      await _journal.resolve(ref.url);
    }
  }
}

class TourMediaUploader {
  static const String baseUrl = 'https://bhromon.fun';
  static const String uploadUrl = '$baseUrl/api/media/upload';
  static const String deleteBaseUrl = '$baseUrl/api/media/media';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(minutes: 20),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );

  /// Authentication options for media server requests. The server accepts only
  /// the signed-in member's Firebase ID token; there is no shared key.
  static Future<Options> _authorized() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return Options(headers: headers);
  }

  /// Uploads [file] to the media server under {tourId}/{folder}/. Size and type
  /// are checked before anything is sent.
  static Future<TourMediaUpload> start({
    required String tourId,
    required String folder,
    required XFile file,
    required String contentType,
    required String extension,
    required int maxBytes,
    TourMediaJournal? journal,
  }) async {
    final size = await file.length();
    if (size == 0) {
      throw const TourUploadException('ফাইলটি খালি। অন্য ফাইল বাছাই করুন।');
    }
    if (size > maxBytes) {
      throw TourUploadException(
          'ফাইলটি খুব বড় (${formatMegabytes(size)})। সর্বোচ্চ ${formatMegabytes(maxBytes)} হতে পারে।');
    }

    final store = journal ?? TourMediaJournal.instance;
    final objectId = const Uuid().v4().replaceAll('-', '');
    final ext = extension.toLowerCase();
    final ref = TourMediaRef(
      tourId: tourId,
      folder: folder,
      filename: '$objectId.$ext',
    );
    final refHolder = <TourMediaRef>[ref];
    await store.recordPending(ref);

    final Options options;
    try {
      options = await _authorized();
    } catch (_) {
      await store.resolve(ref.url);
      rethrow;
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

    Future<String> executeUpload() async {
      try {
        final MultipartFile multipartFile;
        if (kIsWeb) {
          final bytes = await file.readAsBytes();
          multipartFile =
              MultipartFile.fromBytes(bytes, filename: ref.filename);
        } else {
          multipartFile =
              await MultipartFile.fromFile(file.path, filename: ref.filename);
        }

        final user = FirebaseAuth.instance.currentUser;
        final formData = FormData.fromMap({
          'file': multipartFile,
          'tourId': tourId,
          'folder': folder,
          'objectId': objectId,
          if (user?.email != null) 'uploaderEmail': user!.email,
        });

        final response = await _dio.post<Map<String, dynamic>>(
          uploadUrl,
          data: formData,
          cancelToken: cancelToken,
          options: options,
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
        final url = response.data!['url'] as String?;
        if (url == null || url.isEmpty) {
          await store.markDelete(ref);
          throw const TourUploadException(
              'সার্ভার থেকে সঠিক ইউআরএল পাওয়া যায়নি।');
        }

        if (url != ref.url) {
          // The server assigned a different filename (e.g. v1 VPS media server),
          // update ref and journal entry so commit and discard track the real URL.
          await store.resolve(ref.url);
          final actualRef = TourMediaRef.tryParse(url);
          if (actualRef != null) {
            await store.recordPending(actualRef);
            refHolder[0] = actualRef;
          }
        }

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

    return TourMediaUpload._(
      ref: ref,
      journal: store,
      finishFn: executeUpload,
      progressStream: progressController.stream,
      cancelToken: cancelToken,
      refHolder: refHolder,
    );
  }

  /// Removes a file from the media server, or from legacy Firebase Storage.
  /// Returns true when the file is gone, including when it was never there.
  static Future<bool> deleteMedia(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return true;

    if (uri.path.startsWith('/media/')) {
      // ['media', tourId, folder, filename]
      final segments = uri.pathSegments;
      if (segments.length < 4) return true;
      try {
        final options = await _authorized();
        final response = await _dio.delete<dynamic>(
          '$deleteBaseUrl/${segments[1]}/${segments[2]}/${segments[3]}',
          options: options,
        );
        return response.statusCode == 200;
      } catch (e) {
        debugPrint('[TourMediaUploader] Could not delete media ($url): $e');
        return false;
      }
    }

    if (url.contains('firebasestorage.googleapis.com')) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
        return true;
      } catch (e) {
        debugPrint(
            '[TourMediaUploader] Could not delete legacy media ($url): $e');
        return false;
      }
    }

    return true;
  }
}
