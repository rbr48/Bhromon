import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_problem_models.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_work_reviews_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The reviews sheet an admin opens on a working: who reviewed and what they said, and a take-back that asks first and
// then removes the review for its reviewer.

class _FakeReviewsRepo extends TourGroupRepository {
  _FakeReviewsRepo(this.reviews);

  final List<StudyWorkReview> reviews;
  final List<String> takenBack = [];

  @override
  Future<List<StudyWorkReview>> loadWorkReviews(
    String tourId,
    String subjectId,
    String problemId,
    String solverEmail,
  ) async =>
      List.of(reviews);

  @override
  Future<void> withdrawOtherWorkReview(
    String tourId,
    String subjectId,
    String problemId,
    String solverEmail,
    StudyWorkReview review,
  ) async {
    takenBack.add(review.reviewerEmail);
    reviews.removeWhere((r) => r.reviewerEmail == review.reviewerEmail);
  }
}

Future<void> _pump(WidgetTester tester, TourGroupRepository repo) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: StudyWorkReviewsSheet(
        repository: repo,
        tourId: 'T',
        subjectId: 'phy',
        problemId: 'p1',
        solverEmail: 'solver@x.com',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'the reviews show who reviewed, the verdict, and the note of a gap',
      (tester) async {
    await _pump(
      tester,
      _FakeReviewsRepo([
        StudyWorkReview(reviewerEmail: 'a@x.com', verdict: WorkVerdict.right),
        StudyWorkReview(
          reviewerEmail: 'b@x.com',
          verdict: WorkVerdict.gap,
          note: 'Step three is missing.',
        ),
      ]),
    );

    expect(find.text('a@x.com marked it right'), findsOneWidget);
    expect(find.text('b@x.com marked a gap'), findsOneWidget);
    expect(find.text('Step three is missing.'), findsOneWidget);
    expect(find.byIcon(Icons.undo_rounded), findsNWidgets(2));
  });

  testWidgets(
      'taking a review back asks first, then removes it and shows the list again',
      (tester) async {
    final repo = _FakeReviewsRepo([
      StudyWorkReview(reviewerEmail: 'a@x.com', verdict: WorkVerdict.right),
      StudyWorkReview(reviewerEmail: 'b@x.com', verdict: WorkVerdict.right),
    ]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.undo_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Take this review back?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.takenBack, isEmpty);

    await tester.tap(find.byIcon(Icons.undo_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(repo.takenBack, ['a@x.com']);
    expect(find.text('a@x.com marked it right'), findsNothing);
    expect(find.text('b@x.com marked it right'), findsOneWidget);
  });

  testWidgets('a working no one has reviewed says so', (tester) async {
    await _pump(tester, _FakeReviewsRepo([]));

    expect(find.text('No one has reviewed this yet.'), findsOneWidget);
    expect(find.byIcon(Icons.undo_rounded), findsNothing);
  });
}
