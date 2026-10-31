import 'package:bhromon/features/tour_group/domain/services/reel_fit.dart';
import 'package:flutter_test/flutter_test.dart';

/// A phone screen in portrait, 390 by 844 logical pixels.
const double _phone = 390 / 844;

void main() {
  group('reelFillFor', () {
    test('a landscape reel is fitted whole in a portrait screen', () {
      expect(
        reelFillFor(pictureAspect: 16 / 9, spaceAspect: _phone),
        ReelFill.fitInside,
      );
    });

    test('a portrait reel still fills a tall phone screen as before', () {
      // Filling cuts about 18 % of a 9:16 reel on a tall phone, within the limit.
      expect(
        reelFillFor(pictureAspect: 9 / 16, spaceAspect: _phone),
        ReelFill.fill,
      );
    });

    test('a square reel is fitted, since filling would cut half of it', () {
      expect(
        reelFillFor(pictureAspect: 1, spaceAspect: _phone),
        ReelFill.fitInside,
      );
    });

    test('a reel whose shape matches the space fills it', () {
      expect(
        reelFillFor(pictureAspect: 16 / 9, spaceAspect: 16 / 9),
        ReelFill.fill,
      );
    });

    test('a reel of unknown shape fills the space', () {
      expect(
        reelFillFor(pictureAspect: null, spaceAspect: _phone),
        ReelFill.fill,
      );
      expect(
        reelFillFor(pictureAspect: 0, spaceAspect: _phone),
        ReelFill.fill,
      );
    });

    test('a space of unknown shape fills, rather than dividing by nothing', () {
      expect(
        reelFillFor(pictureAspect: 16 / 9, spaceAspect: 0),
        ReelFill.fill,
      );
    });

    test('the limit is a fifth of the picture', () {
      // A space 80 % as wide as a square cuts exactly a fifth of it.
      expect(
        reelFillFor(pictureAspect: 1, spaceAspect: 0.8),
        ReelFill.fill,
      );
      expect(
        reelFillFor(pictureAspect: 1, spaceAspect: 0.79),
        ReelFill.fitInside,
      );
    });
  });
}
