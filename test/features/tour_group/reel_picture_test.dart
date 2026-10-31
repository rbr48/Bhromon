import 'package:bhromon/features/tour_group/presentation/widgets/instafeed/reel_picture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _pictureKey = ValueKey('picture');

/// Lays a reel of [picture] size in a 390 by 844 frame, as the reel viewer does.
Future<void> _pumpReel(
  WidgetTester tester, {
  required Size? picture,
  required bool wholePicture,
}) {
  // The frame is the whole screen, so its corners are at the origin and the
  // screen's edges are the frame's.
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 390,
            height: 844,
            child: ReelFittedVideo(
              pictureSize: picture,
              wholePicture: wholePicture,
              child: const ColoredBox(key: _pictureKey, color: Colors.red),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ReelFittedVideo', () {
    testWidgets('a landscape reel is shown whole, with bars above and below',
        (tester) async {
      await _pumpReel(
        tester,
        picture: const Size(1920, 1080),
        wholePicture: true,
      );

      final fitted = tester.widget<FittedBox>(find.byType(FittedBox));
      expect(fitted.fit, BoxFit.contain);

      // Scaled to the frame width: 390 wide, 219.4 high, centred vertically.
      final topLeft = tester.getTopLeft(find.byKey(_pictureKey));
      final bottomRight = tester.getBottomRight(find.byKey(_pictureKey));
      expect(topLeft.dx, closeTo(0, 0.01));
      expect(topLeft.dy, closeTo(312.3, 0.1));
      expect(bottomRight.dx, closeTo(390, 0.01));
      expect(bottomRight.dy, closeTo(531.7, 0.1));
    });

    testWidgets('a portrait reel still fills the frame, cut only at the sides',
        (tester) async {
      await _pumpReel(
        tester,
        picture: const Size(1080, 1920),
        wholePicture: true,
      );

      final fitted = tester.widget<FittedBox>(find.byType(FittedBox));
      expect(fitted.fit, BoxFit.cover);

      final topLeft = tester.getTopLeft(find.byKey(_pictureKey));
      final bottomRight = tester.getBottomRight(find.byKey(_pictureKey));
      expect(topLeft.dy, closeTo(0, 0.01));
      expect(bottomRight.dy, closeTo(844, 0.01));
      expect(topLeft.dx, lessThan(0));
      expect(bottomRight.dx, greaterThan(390));
    });

    testWidgets('without wholePicture a landscape reel still fills, as before',
        (tester) async {
      await _pumpReel(
        tester,
        picture: const Size(1920, 1080),
        wholePicture: false,
      );

      final fitted = tester.widget<FittedBox>(find.byType(FittedBox));
      expect(fitted.fit, BoxFit.cover);

      final topLeft = tester.getTopLeft(find.byKey(_pictureKey));
      final bottomRight = tester.getBottomRight(find.byKey(_pictureKey));
      expect(topLeft.dy, closeTo(0, 0.01));
      expect(bottomRight.dy, closeTo(844, 0.01));
      expect(topLeft.dx, lessThan(0));
      expect(bottomRight.dx, greaterThan(390));
    });

    testWidgets('an unknown size lays out at the default box and fills',
        (tester) async {
      await _pumpReel(tester, picture: null, wholePicture: true);

      final fitted = tester.widget<FittedBox>(find.byType(FittedBox));
      expect(fitted.fit, BoxFit.cover);
    });
  });
}
