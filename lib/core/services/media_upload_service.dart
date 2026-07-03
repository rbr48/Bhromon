import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class MediaUploadService {
  /// Maps legacy directory paths to match the security constraints in storage.rules.
  static String _mapPath(String path) {
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

  /// Uploads a file to Firebase Storage at the specified [path].
  /// Optionally reports progress using [onProgress].
  /// Returns the public download URL on success.
  static Future<String> uploadFile({
    required File file,
    required String path,
    void Function(double)? onProgress,
  }) async {
    try {
      if (kIsWeb) {
        throw UnsupportedError('Direct File upload is not supported on web. Use bytes instead.');
      }
      if (!file.existsSync()) {
        throw FileSystemException('File does not exist at path: ${file.path}');
      }

      File fileToUpload = file;
      final extension = file.path.split('.').last.toLowerCase();
      if (extension == 'jpg' || extension == 'jpeg' || extension == 'png') {
        try {
          final tempDir = await getTemporaryDirectory();
          final targetPath = '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.$extension';
          
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
              debugPrint('Compressed image from ${file.lengthSync()} to ${xfile.lengthSync()} bytes');
            }
          }
        } catch (e) {
          debugPrint('Image compression failed: $e');
        }
      }

      final mappedPath = _mapPath(path);
      final ref = FirebaseStorage.instance.ref().child(mappedPath);
      
      final uploadTask = ref.putFile(
        fileToUpload,
        SettableMetadata(contentType: _getContentTypeForExtension(extension)),
      );

      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((snap) {
          final progress = snap.bytesTransferred / (snap.totalBytes > 0 ? snap.totalBytes : 1);
          onProgress(progress);
        });
      }

      await uploadTask;
      final downloadUrl = await ref.getDownloadURL();
      debugPrint('MediaUploadService uploaded file to path: $mappedPath');
      return downloadUrl;
    } catch (e) {
      debugPrint('MediaUploadService Error (Path: $path): $e');
      rethrow;
    }
  }

  /// Uploads raw bytes (useful for Web or compressed data) to Firebase Storage.
  static Future<String> uploadBytes({
    required List<int> bytes,
    required String path,
    String? contentType,
    void Function(double)? onProgress,
  }) async {
    try {
      final mappedPath = _mapPath(path);
      final ref = FirebaseStorage.instance.ref().child(mappedPath);
      
      final uploadTask = ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(contentType: contentType),
      );

      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((snap) {
          final progress = snap.bytesTransferred / (snap.totalBytes > 0 ? snap.totalBytes : 1);
          onProgress(progress);
        });
      }

      await uploadTask;
      final downloadUrl = await ref.getDownloadURL();
      debugPrint('MediaUploadService uploaded bytes to path: $mappedPath');
      return downloadUrl;
    } catch (e) {
      debugPrint('MediaUploadService Bytes Error (Path: $path): $e');
      rethrow;
    }
  }

  /// Deletes a file from Firebase Storage at the specified [path].
  static Future<void> deleteFile({required String path}) async {
    try {
      final mappedPath = _mapPath(path);
      final ref = FirebaseStorage.instance.ref().child(mappedPath);
      await ref.delete();
      debugPrint('MediaUploadService deleted file from path: $mappedPath');
    } catch (e) {
      debugPrint('MediaUploadService Delete Error (Path: $path): $e');
      rethrow;
    }
  }

  static String _getContentTypeForExtension(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      case 'aac':
        return 'audio/aac';
      case 'm4a':
        return 'audio/m4a';
      case 'mp3':
        return 'audio/mp3';
      case 'wav':
        return 'audio/wav';
      default:
        return 'application/octet-stream';
    }
  }
}
