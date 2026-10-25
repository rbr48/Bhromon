import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bhromon/features/tour_group/domain/services/tour_video_compressor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TourVideoCompressor', () {
    test('returns original file if size is under targetMaxBytes', () async {
      final tempDir = Directory.systemTemp.createTempSync('compress_test');
      final testFile = File('${tempDir.path}/small_video.mp4');
      await testFile.writeAsBytes(List.filled(1024, 0)); // 1 KB

      final result = await TourVideoCompressor.compressIfNeeded(
        sourceFile: XFile(testFile.path),
        targetMaxBytes: 10 * 1024 * 1024,
      );

      expect(result.path, testFile.path);
      tempDir.deleteSync(recursive: true);
    });

    test('cancel does not throw error', () async {
      expect(TourVideoCompressor.cancel(), completes);
    });

    test('clearCache does not throw error', () async {
      expect(TourVideoCompressor.clearCache(), completes);
    });
  });
}
