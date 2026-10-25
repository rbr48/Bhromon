import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../domain/services/media_rules.dart';
import 'tour_media_upload.dart';

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

/// One file on its way to Storage. Cancel it, wait for it, or delete it again
/// if the post it belongs to is never saved.
class TourMediaUpload {
  static const Duration _maxWait = Duration(minutes: 20);

  final UploadTask _task;
  final Reference _ref;

  const TourMediaUpload._(this._task, this._ref);

  /// Progress from 0.0 to 1.0.
  Stream<double> get progress => _task.snapshotEvents
      .map((s) => s.totalBytes == 0 ? 0.0 : s.bytesTransferred / s.totalBytes);

  /// Waits for the upload and returns its download URL.
  Future<String> finish() async {
    try {
      final snapshot = await _task.timeout(_maxWait);
      return await snapshot.ref.getDownloadURL();
    } on FirebaseException catch (e) {
      if (e.code == 'canceled') throw const TourUploadCancelled();
      rethrow;
    } on TimeoutException {
      await cancel();
      throw const TourUploadException(
          'আপলোড শেষ হয়নি। ইন্টারনেট সংযোগ দেখে আবার চেষ্টা করুন।');
    }
  }

  Future<void> cancel() async {
    await _task.cancel();
  }

  /// Deletes the uploaded file. Failures are ignored: the file is orphaned at
  /// worst, and the post still was not created.
  Future<void> discard() async {
    try {
      await _ref.delete();
    } catch (_) {}
  }
}

class TourMediaUploader {
  /// Uploads [file] under tours/{tourId}/{folder}/ and tags it with the
  /// uploader's email, which the storage rules use to allow later deletes.
  /// Size and type are checked here so a refused upload fails with a clear message.
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
    final ref = FirebaseStorage.instance
        .ref('tours/$tourId/$folder/${const Uuid().v4()}.$extension');
    final task = await startTourMediaUpload(
      ref,
      file,
      SettableMetadata(
        contentType: contentType,
        customMetadata: {'uploadedByEmail': uploaderEmail},
      ),
    );
    return TourMediaUpload._(task, ref);
  }
}
