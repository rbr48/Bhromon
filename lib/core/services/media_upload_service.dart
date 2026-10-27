import 'dart:io';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';

/// Central media and file upload service for Bhromon.
///
/// Routes all media (chat attachments, voice notes, documents, profile pictures,
/// reels, and trip logs) to the high-performance dedicated VPS media service
/// at `https://bhromon.fun/api/media/upload`, bypassing Firebase Storage quotas.
class MediaUploadService {
  static const String baseUrl = 'https://bhromon.fun';
  static const String uploadUrl = '$baseUrl/api/media/upload';
  static const String deleteBaseUrl = '$baseUrl/api/media/media';
  static const String legacyUploadKey =
      String.fromEnvironment('MEDIA_UPLOAD_KEY', defaultValue: '');

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
    if (legacyUploadKey.isNotEmpty) {
      headers['X-Upload-Key'] = legacyUploadKey;
    }
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return Options(headers: headers);
  }

  /// Deconstructs a legacy or logical path into [tourOrChatId], [folder], and [filename].
  static (String tourId, String folder, String filename) _parsePath(
      String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length >= 3) {
      return (segments[1], segments[0], segments[2]);
    } else if (segments.length == 2) {
      return (segments[1], segments[0], segments[1]);
    } else if (segments.length == 1) {
      return ('general', 'media', segments[0]);
    }
    final randId = const Uuid().v4().replaceAll('-', '');
    return ('general', 'media', '$randId.bin');
  }

  /// Uploads [file] directly to the dedicated VPS media storage.
  static Future<String> uploadFile({
    required File file,
    required String path,
    void Function(double)? onProgress,
  }) async {
    try {
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
            format:
                extension == 'png' ? CompressFormat.png : CompressFormat.jpeg,
          );

          if (compressedFile != null) {
            final xfile = File(compressedFile.path);
            if (xfile.lengthSync() < file.lengthSync()) {
              fileToUpload = xfile;
            }
          }
        } catch (_) {}
      }

      final (tourId, folder, filename) = _parsePath(path);
      final options = await _authorizedOptions();

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          fileToUpload.path,
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

      debugPrint('MediaUploadService uploaded file to VPS: $url');
      return url;
    } catch (e) {
      debugPrint('MediaUploadService VPS Error (Path: $path): $e');
      rethrow;
    }
  }

  /// Uploads raw bytes (cross-platform, works on Web, Android, iOS) to VPS.
  static Future<String> uploadBytes({
    required List<int> bytes,
    required String path,
    String? contentType,
    void Function(double)? onProgress,
  }) async {
    try {
      final (tourId, folder, filename) = _parsePath(path);
      final options = await _authorizedOptions();

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
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

      debugPrint('MediaUploadService uploaded bytes to VPS: $url');
      return url;
    } catch (e) {
      debugPrint('MediaUploadService Bytes VPS Error (Path: $path): $e');
      rethrow;
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

      final formData = FormData.fromMap({
        'file': multipartFile,
        'tourId': tourOrChatId,
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

      debugPrint('MediaUploadService uploaded XFile to VPS: $url');
      return url;
    } catch (e) {
      debugPrint('MediaUploadService XFile VPS Error: $e');
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
          debugPrint('MediaUploadService deleted VPS media: $path');
          return;
        }
      }

      // Fallback for legacy Firebase Storage URLs
      if (path.startsWith('gs://') ||
          path.contains('firebasestorage.googleapis.com')) {
        await FirebaseStorage.instance.refFromURL(path).delete();
        debugPrint('MediaUploadService deleted legacy Firebase media: $path');
      }
    } catch (e) {
      debugPrint('MediaUploadService Delete Error (Path: $path): $e');
    }
  }
}
