import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/entities/trip_block.dart';

void main() {
  group('TripBlock.fromJson', () {
    test('reads a typed document as written', () {
      final block = TripBlock.fromJson({
        'runtimeType': 'text',
        'id': 'b1',
        'content': 'Hello',
        'isBold': true,
      });

      expect(block, isA<TextBlock>());
      expect((block as TextBlock).content, 'Hello');
      expect(block.isBold, isTrue);
    });

    test('infers a video from a legacy .mp4 storage URL', () {
      final block = TripBlock.fromJson({
        'id': 'b2',
        'storageUrl': 'https://cdn.example/clips/sunset.MP4',
        'caption': 'Sunset',
      });

      expect(block, isA<VideoBlock>());
    });

    test('infers an image from a legacy photo path', () {
      final block = TripBlock.fromJson({
        'id': 'b3',
        'localPath': '/storage/emulated/0/DCIM/photo.jpg',
      });

      expect(block, isA<ImageBlock>());
    });

    test('infers a voice note from a duration', () {
      final block = TripBlock.fromJson({
        'id': 'b4',
        'durationSeconds': 42,
      });

      expect(block, isA<VoiceNoteBlock>());
      expect((block as VoiceNoteBlock).durationSeconds, 42);
    });

    test('infers a cost entry, defaulting the currency to BDT', () {
      final block = TripBlock.fromJson({
        'id': 'b5',
        'items': <dynamic>[],
      });

      expect(block, isA<CostEntryBlock>());
      expect((block as CostEntryBlock).currency, 'BDT');
    });

    test('falls back to a plain text block when nothing else matches', () {
      final block = TripBlock.fromJson({'id': 'b6'});

      expect(block, isA<TextBlock>());
      expect((block as TextBlock).content, '');
    });

    test('gives a block an id when the document has none', () {
      final block = TripBlock.fromJson({'content': 'No id'});

      expect(block.id, startsWith('blk_'));
    });
  });
}
