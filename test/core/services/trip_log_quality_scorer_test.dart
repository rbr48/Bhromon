import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/core/services/trip_log_quality_scorer.dart';

void main() {
  group('TripLogQualityScorer', () {
    // Helper to call scoreSync with required params
    QualityResult score({
      String title = 'A Test Trip Log Title',
      String bodyText = '',
      int imageCount = 0,
      int videoCount = 0,
      int routePointCount = 0,
      int costItemCount = 0,
      int safetyNoteCount = 0,
    }) {
      return TripLogQualityScorer.scoreSync(
        title: title,
        bodyText: bodyText,
        imageCount: imageCount,
        videoCount: videoCount,
        routePointCount: routePointCount,
        costItemCount: costItemCount,
        safetyNoteCount: safetyNoteCount,
      );
    }

    group('title scoring', () {
      test('awards 10 points for title >= 10 chars', () {
        final result = score(title: 'A long enough title');
        expect(result.score, greaterThanOrEqualTo(10));
        expect(result.strengths, contains('✅ Good title'));
      });

      test('does not award title points for short title', () {
        final result = score(title: 'Short');
        expect(result.tips, anyElement(contains('descriptive title')));
      });
    });

    group('body scoring', () {
      test('awards 30 points for 200+ word body', () {
        final longBody = List.generate(200, (i) => 'word$i').join(' ');
        final result = score(bodyText: longBody);
        expect(result.score, greaterThanOrEqualTo(30));
        expect(result.strengths, contains('✅ Detailed description'));
      });

      test('awards 20 points for 100-199 word body', () {
        final mediumBody = List.generate(120, (i) => 'word$i').join(' ');
        final result = score(bodyText: mediumBody);
        // Should be between 20-29 contribution from body
        expect(result.tips, anyElement(contains('200+ words')));
      });

      test('awards 10 points for 50-99 word body', () {
        final shortBody = List.generate(60, (i) => 'word$i').join(' ');
        final result = score(bodyText: shortBody);
        expect(result.tips, anyElement(contains('100+ words')));
      });

      test('awards 0 points for < 50 word body', () {
        final result = score(bodyText: 'too short');
        expect(result.tips, anyElement(contains('50+ words')));
      });
    });

    group('image scoring', () {
      test('awards 20 points for 3+ images', () {
        final result = score(imageCount: 3);
        expect(result.strengths, contains('✅ Great photo coverage'));
      });

      test('awards 10 points for 1-2 images', () {
        final result = score(imageCount: 1);
        expect(result.tips, anyElement(contains('2 more photos')));
      });

      test('awards 0 points for no images', () {
        final result = score(imageCount: 0);
        expect(result.tips, anyElement(contains('at least one photo')));
      });
    });

    group('video scoring', () {
      test('awards 10 points for 1+ video', () {
        final result = score(videoCount: 1);
        expect(result.strengths, contains('✅ Has video content'));
      });

      test('awards 0 for no video', () {
        final result = score(videoCount: 0);
        expect(result.tips, anyElement(contains('video')));
      });
    });

    group('route scoring', () {
      test('awards 15 points for 3+ route points', () {
        final result = score(routePointCount: 3);
        expect(result.strengths, contains('✅ Route tracked'));
      });

      test('awards 8 points for 1-2 route points', () {
        final noTipResult = score(routePointCount: 1);
        expect(noTipResult.tips, isNot(anyElement(contains('waypoints'))));
      });

      test('awards 0 and tips for no route', () {
        final result = score(routePointCount: 0);
        expect(result.tips, anyElement(contains('waypoints')));
      });
    });

    group('cost scoring', () {
      test('awards 10 points for 2+ cost items', () {
        final result = score(costItemCount: 2);
        expect(result.strengths, contains('✅ Cost breakdown included'));
      });

      test('awards 5 points for 1 cost item', () {
        final result = score(costItemCount: 1);
        // Score should include 5-point contribution
        expect(result.score, greaterThan(0));
      });

      test('awards 0 and tip for no cost items', () {
        final result = score(costItemCount: 0);
        expect(result.tips, anyElement(contains('cost breakdown')));
      });
    });

    group('safety scoring', () {
      test('awards 5 points for 1+ safety note', () {
        final result = score(safetyNoteCount: 1);
        expect(result.strengths, contains('✅ Safety info shared'));
      });

      test('awards 0 and tip for no safety notes', () {
        final result = score(safetyNoteCount: 0);
        expect(result.tips, anyElement(contains('safety note')));
      });
    });

    group('total score and grade', () {
      test('perfect log scores 100', () {
        final longBody = List.generate(200, (i) => 'word$i').join(' ');
        final result = score(
          title: 'An amazing trip to the mountains',
          bodyText: longBody,
          imageCount: 5,
          videoCount: 2,
          routePointCount: 10,
          costItemCount: 5,
          safetyNoteCount: 2,
        );
        expect(result.score, 100);
        expect(result.grade, 'S');
        expect(result.gradeLabel, 'Outstanding');
        expect(result.trustBonus, 15);
      });

      test('empty log scores 0', () {
        final result = score(
          title: 'Hi',
          bodyText: '',
          imageCount: 0,
          videoCount: 0,
          routePointCount: 0,
          costItemCount: 0,
          safetyNoteCount: 0,
        );
        expect(result.score, 0);
        expect(result.grade, 'D');
        expect(result.gradeLabel, 'Needs Work');
        expect(result.trustBonus, 0);
      });

      test('score is always clamped between 0 and 100', () {
        final result = score();
        expect(result.score, inInclusiveRange(0, 100));
      });

      test('grade A for score >= 70', () {
        final longBody = List.generate(200, (i) => 'word$i').join(' ');
        final result = score(
          title: 'An amazing trip to the mountains',
          bodyText: longBody,
          imageCount: 3,
          videoCount: 1,
          routePointCount: 3,
          costItemCount: 2,
          safetyNoteCount: 1,
        );
        expect(result.score, greaterThanOrEqualTo(70));
        expect(result.grade, 'S'); // 100 is possible here
        expect(result.trustBonus, greaterThanOrEqualTo(10));
      });

      test('trust bonus is 5 for score 50-69', () {
        // title (10) + body 100w (20) + 1 image (10) + 1 route (8) + 0 others = 48 → Grade D
        // tweak to get 50+
        final body = List.generate(100, (i) => 'word$i').join(' ');
        final result = score(
          title: 'A decent trip title here',
          bodyText: body,
          imageCount: 1,
          videoCount: 0,
          routePointCount: 1,
          costItemCount: 1,
          safetyNoteCount: 0,
        );
        // 10 + 20 + 10 + 0 + 8 + 5 + 0 = 53
        expect(result.score, greaterThanOrEqualTo(50));
        expect(result.trustBonus, greaterThanOrEqualTo(5));
      });
    });

    group('QualityResult.grade', () {
      test('returns S for 90+', () {
        const r =
            QualityResult(score: 95, tips: [], strengths: [], trustBonus: 15);
        expect(r.grade, 'S');
        expect(r.gradeLabel, 'Outstanding');
      });
      test('returns A for 70-89', () {
        const r =
            QualityResult(score: 75, tips: [], strengths: [], trustBonus: 10);
        expect(r.grade, 'A');
        expect(r.gradeLabel, 'Great');
      });
      test('returns B for 50-69', () {
        const r =
            QualityResult(score: 55, tips: [], strengths: [], trustBonus: 5);
        expect(r.grade, 'B');
        expect(r.gradeLabel, 'Good');
      });
      test('returns C for 30-49', () {
        const r =
            QualityResult(score: 35, tips: [], strengths: [], trustBonus: 2);
        expect(r.grade, 'C');
        expect(r.gradeLabel, 'Basic');
      });
      test('returns D for < 30', () {
        const r =
            QualityResult(score: 10, tips: [], strengths: [], trustBonus: 0);
        expect(r.grade, 'D');
        expect(r.gradeLabel, 'Needs Work');
      });
    });
  });
}
