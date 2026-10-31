import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';

import '../utils/app_logger.dart';

/// Central media and file upload service for Bhromon.
///
/// Seamlessly handles uploads to dedicated VPS media storage and Firebase Storage
/// with automatic bidirectional fallback to ensure zero upload failures.
class MediaUploadService {
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

  static Future<Options> _authorizedOptions() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return Options(headers: headers);
  }

  static bool _isProfilePath(String path) {
    return path.startsWith('explorer_avatars') ||
        path.startsWith('explorer_covers') ||
        path.startsWith('explorer_profiles') ||
        path.startsWith('voice_bios');
  }

  /// Maps legacy directory paths to match the security constraints in storage.rules.
  static String _mapStoragePath(String path) {
    if (path.startsWith('explorer_avatars/')) {
      final filename = path.substring('explorer_avatars/'.length);
      final parts = filename.split('_');
      if (parts.isNotEmpty) {
        final uid = parts[0];
        return 'explorer_profiles/$uid/avatar_${parts.sublist(1).join('_')}';
      }
    } else if (path.startsWith('explorer_covers/')) {
      final filename = path.substring('explorer_covers/'.length);
      final parts = filename.split('_');
      if (parts.isNotEmpty) {
        final uid = parts[0];
        return 'explorer_profiles/$uid/cover_${parts.sublist(1).join('_')}';
      }
    } else if (path.startsWith('voice_bios/')) {
      final parts = path.split('/');
      if (parts.length >= 3) {
        final uid = parts[1];
        return 'explorer_profiles/$uid/bio.m4a';
      }
    }
    return path;
  }

  static String _getContentTypeForExtension(String ext) {
    switch (ext.toLowerCase().replaceAll('.', '')) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      case 'm4a':
      case 'aac':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }

  /// Deconstructs a logical path into [tourOrChatId], [folder], and [filename].
  static (String tourId, String folder, String filename) _parsePath(
      String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length >= 3) {
      final folder = segments[0];
      final tourId = _normalizeTourOrChatId(segments[1], folder);
      return (tourId, folder, segments[2]);
    } else if (segments.length == 2) {
      final seg0 = segments[0];
      final seg1 = segments[1];
      if (seg0 == 'explorer_avatars' || seg0 == 'avatars') {
        return ('profiles', 'avatars', seg1);
      } else if (seg0 == 'explorer_covers' || seg0 == 'covers') {
        return ('profiles', 'covers', seg1);
      } else if (seg0 == 'voice_bios') {
        return ('profiles', 'voice_bios', seg1);
      }
      return ('general', seg0, seg1);
    } else if (segments.length == 1) {
      return ('general', 'media', segments[0]);
    }
    final randId = const Uuid().v4().replaceAll('-', '');
    return ('general', 'media', '$randId.bin');
  }

  /// Normalizes a space/chat ID so that chat media always maps to a recognized
  /// chat space on the VPS media server (`chat_*`), adhering to length (<= 64)
  /// and character set (`[A-Za-z0-9_-]`) constraints.
  static String _normalizeTourOrChatId(String id, String folder) {
    if (folder.startsWith('chat_')) {
      final clean = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      if (clean.startsWith('chat_') && clean.length <= 64) {
        return clean;
      }
      final candidate = 'chat_$clean';
      if (candidate.length <= 64) {
        return candidate;
      }
      // A shared fallback space would let any signed-in person into this chat's files.
      throw ArgumentError.value(id, 'id', 'Too long to store as a chat space');
    }
    return id;
  }

  /// Uploads bytes directly to Firebase Storage.
  static Future<String> _uploadBytesToFirebase({
    required List<int> bytes,
    required String path,
    String? contentType,
    void Function(double)? onProgress,
  }) async {
    final mappedPath = _mapStoragePath(path);
    final ref = FirebaseStorage.instance.ref().child(mappedPath);
    final ext = path.split('.').last.toLowerCase();
    final effectiveContentType =
        contentType ?? _getContentTypeForExtension(ext);

    final uploadTask = ref.putData(
      Uint8List.fromList(bytes),
      SettableMetadata(contentType: effectiveContentType),
    );

    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((snap) {
        final total = snap.totalBytes;
        if (total > 0) {
          onProgress(snap.bytesTransferred / total);
        }
      });
    }

    await uploadTask;
    final downloadUrl = await ref.getDownloadURL();
    logInfo(
        'MediaUploadService uploaded bytes to Firebase Storage: $downloadUrl');
    return downloadUrl;
  }

  /// Uploads a file directly to Firebase Storage.
  static Future<String> _uploadFileToFirebase({
    required File file,
    required String path,
    void Function(double)? onProgress,
  }) async {
    final mappedPath = _mapStoragePath(path);
    final ref = FirebaseStorage.instance.ref().child(mappedPath);
    final ext = file.path.split('.').last.toLowerCase();
    final effectiveContentType = _getContentTypeForExtension(ext);

    final uploadTask = ref.putFile(
      file,
      SettableMetadata(contentType: effectiveContentType),
    );

    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((snap) {
        final total = snap.totalBytes;
        if (total > 0) {
          onProgress(snap.bytesTransferred / total);
        }
      });
    }

    await uploadTask;
    final downloadUrl = await ref.getDownloadURL();
    logInfo(
        'MediaUploadService uploaded file to Firebase Storage: $downloadUrl');
    return downloadUrl;
  }

  /// Uploads bytes directly to VPS media storage.
  static Future<String> _uploadBytesToVps({
    required List<int> bytes,
    required String path,
    String? contentType,
    void Function(double)? onProgress,
  }) async {
    final (tourId, folder, filename) = _parsePath(path);
    final options = await _authorizedOptions();

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType:
            contentType != null ? DioMediaType.parse(contentType) : null,
      ),
      'tourId': tourId,
      'folder': folder,
    });

    final response = await _dio.post<Map<String, dynamic>>(
      uploadUrl,
      data: formData,
      options: options,
      onSendProgress: (sent, total) {
        if (total > 0 && onProgress != null) {
          onProgress(sent / total);
        }
      },
    );

    final url = response.data?['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('VPS media server did not return a valid download URL');
    }

    logInfo('MediaUploadService uploaded bytes to VPS: $url');
    return url;
  }

  /// Uploads a file directly to VPS media storage.
  static Future<String> _uploadFileToVps({
    required File file,
    required String path,
    void Function(double)? onProgress,
  }) async {
    final (tourId, folder, filename) = _parsePath(path);
    final options = await _authorizedOptions();

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: filename,
      ),
      'tourId': tourId,
      'folder': folder,
    });

    final response = await _dio.post<Map<String, dynamic>>(
      uploadUrl,
      data: formData,
      options: options,
      onSendProgress: (sent, total) {
        if (total > 0 && onProgress != null) {
          onProgress(sent / total);
        }
      },
    );

    final url = response.data?['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('VPS media server did not return a valid download URL');
    }

    logInfo('MediaUploadService uploaded file to VPS: $url');
    return url;
  }

  /// Uploads [file] with automatic compression and resilient fallback.
  static Future<String> uploadFile({
    required File file,
    required String path,
    void Function(double)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
          'Direct File upload is not supported on web. Use uploadBytes instead.');
    }
    if (!file.existsSync()) {
      throw FileSystemException('File does not exist at path: ${file.path}');
    }

    File fileToUpload = file;
    final extension = file.path.split('.').last.toLowerCase();
    if (extension == 'jpg' || extension == 'jpeg' || extension == 'png') {
      try {
        final tempDir = await getTemporaryDirectory();
        final targetPath =
            '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.$extension';

        final compressedFile = await FlutterImageCompress.compressAndGetFile(
          file.absolute.path,
          targetPath,
          quality: 75,
          format: extension == 'png' ? CompressFormat.png : CompressFormat.jpeg,
        );

        if (compressedFile != null) {
          final xfile = File(compressedFile.path);
          if (xfile.lengthSync() < file.lengthSync()) {
            fileToUpload = xfile;
          }
        }
      } catch (error, stackTrace) {
        logSkipped(error, stackTrace);
      }
    }

    // Prioritize Firebase Storage for profile and personal media paths
    if (_isProfilePath(path)) {
      try {
        return await _uploadFileToFirebase(
          file: fileToUpload,
          path: path,
          onProgress: onProgress,
        );
      } catch (fbErr, st) {
        logWarning(
            'MediaUploadService: Firebase Storage profile upload failed, falling back to VPS...',
            fbErr,
            st);
        try {
          return await _uploadFileToVps(
            file: fileToUpload,
            path: path,
            onProgress: onProgress,
          );
        } catch (vpsErr, vst) {
          logError('MediaUploadService: VPS fallback also failed', vpsErr, vst);
          rethrow;
        }
      }
    }

    // For other media, prioritize VPS and fallback to Firebase Storage
    try {
      return await _uploadFileToVps(
        file: fileToUpload,
        path: path,
        onProgress: onProgress,
      );
    } catch (vpsErr, st) {
      logWarning(
          'MediaUploadService: VPS upload failed, falling back to Firebase Storage...',
          vpsErr,
          st);
      try {
        return await _uploadFileToFirebase(
          file: fileToUpload,
          path: path,
          onProgress: onProgress,
        );
      } catch (fbErr, fst) {
        logError('MediaUploadService: Firebase Storage fallback also failed',
            fbErr, fst);
        rethrow;
      }
    }
  }

  /// Uploads raw bytes (cross-platform, works on Web, Android, iOS) with resilient fallback.
  static Future<String> uploadBytes({
    required List<int> bytes,
    required String path,
    String? contentType,
    void Function(double)? onProgress,
  }) async {
    // Prioritize Firebase Storage for profile and personal media paths
    if (_isProfilePath(path)) {
      try {
        return await _uploadBytesToFirebase(
          bytes: bytes,
          path: path,
          contentType: contentType,
          onProgress: onProgress,
        );
      } catch (fbErr, st) {
        logWarning(
            'MediaUploadService: Firebase Storage profile bytes upload failed, falling back to VPS...',
            fbErr,
            st);
        try {
          return await _uploadBytesToVps(
            bytes: bytes,
            path: path,
            contentType: contentType,
            onProgress: onProgress,
          );
        } catch (vpsErr, vst) {
          logError('MediaUploadService: VPS fallback also failed', vpsErr, vst);
          rethrow;
        }
      }
    }

    // For other media, prioritize VPS and fallback to Firebase Storage
    try {
      return await _uploadBytesToVps(
        bytes: bytes,
        path: path,
        contentType: contentType,
        onProgress: onProgress,
      );
    } catch (vpsErr, st) {
      logWarning(
          'MediaUploadService: VPS bytes upload failed, falling back to Firebase Storage...',
          vpsErr,
          st);
      try {
        return await _uploadBytesToFirebase(
          bytes: bytes,
          path: path,
          contentType: contentType,
          onProgress: onProgress,
        );
      } catch (fbErr, fst) {
        logError('MediaUploadService: Firebase Storage fallback also failed',
            fbErr, fst);
        rethrow;
      }
    }
  }

  /// Uploads an [XFile] (from ImagePicker or file picker) cross-platform to VPS.
  static Future<String> uploadXFile({
    required XFile file,
    required String tourOrChatId,
    required String folder,
    void Function(double)? onProgress,
  }) async {
    try {
      final options = await _authorizedOptions();
      final ext = file.name.split('.').last.toLowerCase();
      final uniqueName = '${const Uuid().v4().replaceAll('-', '')}.$ext';

      final MultipartFile multipartFile;
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        multipartFile = MultipartFile.fromBytes(bytes, filename: uniqueName);
      } else {
        multipartFile =
            await MultipartFile.fromFile(file.path, filename: uniqueName);
      }

      final effectiveTourId = _normalizeTourOrChatId(tourOrChatId, folder);
      final formData = FormData.fromMap({
        'file': multipartFile,
        'tourId': effectiveTourId,
        'folder': folder,
      });

      final response = await _dio.post<Map<String, dynamic>>(
        uploadUrl,
        data: formData,
        options: options,
        onSendProgress: (sent, total) {
          if (total > 0 && onProgress != null) {
            onProgress(sent / total);
          }
        },
      );

      final url = response.data?['url'] as String?;
      if (url == null || url.isEmpty) {
        throw Exception('VPS media server did not return a valid download URL');
      }

      logInfo('MediaUploadService uploaded XFile to VPS: $url');
      return url;
    } catch (e, st) {
      logError('MediaUploadService XFile VPS Error', e, st);
      rethrow;
    }
  }

  /// Deletes a file from either VPS storage or legacy Firebase Storage.
  static Future<void> deleteFile({required String path}) async {
    try {
      if (path.contains('/media/')) {
        // VPS storage URL: https://bhromon.fun/media/{tourId}/{folder}/{filename}
        final uri = Uri.tryParse(path);
        if (uri != null && uri.pathSegments.length >= 4) {
          final tourId = uri.pathSegments[1];
          final folder = uri.pathSegments[2];
          final filename = uri.pathSegments[3];
          final options = await _authorizedOptions();
          await _dio.delete<void>(
            '$deleteBaseUrl/$tourId/$folder/$filename',
            options: options,
          );
          logInfo('MediaUploadService deleted VPS media: $path');
          return;
        }
      }

      // Fallback for legacy Firebase Storage URLs
      if (path.startsWith('gs://') ||
          path.contains('firebasestorage.googleapis.com')) {
        await FirebaseStorage.instance.refFromURL(path).delete();
        logInfo('MediaUploadService deleted legacy Firebase media: $path');
      }
    } catch (e, st) {
      logWarning('MediaUploadService Delete Error (Path: $path)', e, st);
    }
  }
}
