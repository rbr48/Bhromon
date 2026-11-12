import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/study_reading_position.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_material_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_book_chapters_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// A huge book opens without building every chapter card: the list builds the rows on screen and
// the rest as the member scrolls. The chapters are built lazily, so a book of hundreds of chapters
// does not hold up the screen when it opens.

class _BookRepo extends TourGroupRepository {
  _BookRepo(this.chapters);

  final List<StudyChapter> chapters;

  @override
  String get currentEmail => 'me@x.com';

  @override
  Future<TourRole?> myRole(String tourId) async => null;

  @override
  Stream<TourGroup?> watchGroup(String tourId) => Stream.value(null);

  @override
  Stream<List<StudyChapter>> watchStudyChapters(String tourId, String bookId) =>
      Stream.value(chapters);

  @override
  Stream<List<StudyMaterial>> watchStudyMaterials(
          String tourId, String bookId) =>
      Stream.value(const []);

  @override
  Stream<Map<String, StudyReadMark>> watchMyReadMarks(
    String tourId,
    String bookId,
  ) =>
      Stream.value(const {});

  @override
  Stream<List<TourMember>> watchMembers(String tourId) =>
      Stream.value(const []);
}

class _NoPosition extends StudyReadingPosition {
  _NoPosition();

  @override
  Future<int?> load({required String tourId, required String bookId}) async =>
      null;
}

void main() {
  testWidgets('a huge book builds the chapters on screen when it opens',
      (tester) async {
    const count = 300;
    final chapters = [
      for (var i = 1; i <= count; i++)
        StudyChapter(id: 'c$i', number: i, title: 'Chapter $i title'),
    ];

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: StudyBookChaptersScreen(
        tourId: 't',
        book: const StudyBook(id: 'b', title: 'Huge book'),
        repository: _BookRepo(chapters),
        position: _NoPosition(),
      ),
    ));
    await tester.pumpAndSettle();

    // The first chapter is on screen; the last is not built until the member scrolls to it.
    expect(find.textContaining('Chapter 1 title'), findsOneWidget);
    expect(find.textContaining('Chapter $count title'), findsNothing);
    expect(find.byType(Card).evaluate().length, lessThan(30));

    await tester.dragUntilVisible(
      find.textContaining('Chapter $count title'),
      find.byType(ListView),
      const Offset(0, -1000),
      maxIteration: 200,
    );
    expect(find.textContaining('Chapter $count title'), findsOneWidget);
  });
}
