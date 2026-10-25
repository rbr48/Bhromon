import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bhromon/features/tour_group/data/tour_media_uploader.dart';

void main() {
  group('TourMediaUploader & TourMediaUpload', () {
    test('rejects empty file with a clear Bengali error message', () async {
      final emptyFile = XFile.fromData(
        Uint8List(0),
        name: 'empty.jpg',
      );

      expect(
        () => TourMediaUploader.start(
          tourId: 'tour_123',
          folder: 'photos',
          file: emptyFile,
          contentType: 'image/jpeg',
          extension: 'jpg',
          maxBytes: 10 * 1024 * 1024,
          uploaderEmail: 'test@bhromon.fun',
        ),
        throwsA(
          isA<TourUploadException>().having(
            (e) => e.message,
            'message',
            contains('ফাইলটি খালি'),
          ),
        ),
      );
    });

    test('rejects file larger than maxBytes with size formatting', () async {
      // 5 bytes with maxBytes set to 2 bytes
      final oversizedFile = XFile.fromData(
        Uint8List.fromList([1, 2, 3, 4, 5]),
        name: 'test.jpg',
      );

      expect(
        () => TourMediaUploader.start(
          tourId: 'tour_123',
          folder: 'photos',
          file: oversizedFile,
          contentType: 'image/jpeg',
          extension: 'jpg',
          maxBytes: 2,
          uploaderEmail: 'test@bhromon.fun',
        ),
        throwsA(
          isA<TourUploadException>().having(
            (e) => e.message,
            'message',
            contains('ফাইলটি খুব বড়'),
          ),
        ),
      );
    });

    test('constants point to the production VPS media domain', () {
      expect(TourMediaUploader.baseUrl, 'https://bhromon.fun');
      expect(
          TourMediaUploader.uploadUrl, 'https://bhromon.fun/api/media/upload');
      expect(TourMediaUploader.deleteBaseUrl,
          'https://bhromon.fun/api/media/media');
      expect(TourMediaUploader.uploadKey, isNotEmpty);
    });

    test(
        'deleteMedia gracefully ignores non-remote or invalid URLs without throwing',
        () async {
      // Should not throw
      await TourMediaUploader.deleteMedia('');
      await TourMediaUploader.deleteMedia('/local/path/img.jpg');
      await TourMediaUploader.deleteMedia('blob:http://localhost/xyz');
    });
  });
}
