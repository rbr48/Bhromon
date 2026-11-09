import 'dart:async';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_summary_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The shared summary of a chapter. A member adds a revision, or restores an older one as a new revision, and an admin
// pins the revision the group reads. The fake repository acts as the server would: a new revision becomes the newest,
// and a pin changes what the chapter reports.

/// A value that tells its listeners when it changes, so the screen sees each change at once.
class _Live<T> {
  _Live(this._value);

  T _value;
  final StreamController<T> _changes = StreamController<T>.broadcast();

  T get value => _value;

  set value(T next) {
    _value = next;
    _changes.add(next);
  }

  Stream<T> get stream => Stream<T>.multi((out) {
        out.add(_value);
        final sub = _changes.stream.listen(out.add);
        out.onCancel = sub.cancel;
      });
}

class _FakeSummaryRepo extends TourGroupRepository {
  _FakeSummaryRepo({
    required this.role,
    required List<StudySummaryRevision> revisions,
    String? pinnedId,
  })  : _revisions = _Live(revisions),
        _chapter = _Live([
          StudyChapter(
            id: 'c1',
            number: 1,
            title: 'Part one',
            pinnedSummaryId: pinnedId,
          ),
        ]);

  final TourRole? role;
  final _Live<List<StudySummaryRevision>> _revisions;
  final _Live<List<StudyChapter>> _chapter;
  final List<String> calls = [];

  @override
  String get currentEmail => 'me@x.com';

  @override
  String get currentDisplayName => 'Me';

  @override
  Future<TourRole?> myRole(String tourId) async => role;

  @override
  Stream<List<StudySummaryRevision>> watchSummaries(
    String tourId,
    String bookId,
    String chapterId,
  ) =>
      _revisions.stream;

  @override
  Stream<List<StudyChapter>> watchStudyChapters(String tourId, String bookId) =>
      _chapter.stream;

  @override
  Future<void> addSummaryRevision(
    String tourId,
    String bookId,
    String chapterId, {
    required String text,
    String? restoredFromId,
  }) async {
    calls.add(restoredFromId == null
        ? 'add: $text'
        : 'restore $restoredFromId: $text');
    _revisions.value = [
      ..._revisions.value,
      StudySummaryRevision(
        id: 'added${calls.length}',
        text: text,
        editorEmail: 'me@x.com',
        editorName: 'Me',
        createdAt: DateTime(2026, 11, 11),
        restoredFromId: restoredFromId,
      ),
    ];
  }

  @override
  Future<void> setChapterPin(
    String tourId,
    String bookId,
    String chapterId, {
    String? revisionId,
  }) async {
    calls.add('pin ${revisionId ?? 'none'}');
    _chapter.value = [
      StudyChapter(
        id: 'c1',
        number: 1,
        title: 'Part one',
        pinnedSummaryId: revisionId,
      ),
    ];
  }
}

final _older = StudySummaryRevision(
  id: 'r1',
  text: 'Old summary.',
  editorEmail: 'a@x.com',
  editorName: 'Admin',
  createdAt: DateTime(2026, 2, 1, 9),
);

final _newer = StudySummaryRevision(
  id: 'r2',
  text: 'New summary.',
  editorEmail: 'b@x.com',
  editorName: 'Member',
  createdAt: DateTime(2026, 3, 1, 9),
);

const _book =
    StudyBook(id: 'b1', title: 'Anna Karenina', createdByEmail: 'admin@x.com');

Future<void> _pump(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: page,
  ));
  await tester.pumpAndSettle();
}

StudySummaryScreen _screen(_FakeSummaryRepo repo) => StudySummaryScreen(
      tourId: 't1',
      book: _book,
      chapter: const StudyChapter(id: 'c1', number: 1, title: 'Part one'),
      repository: repo,
    );

void main() {
  testWidgets(
      'with nothing pinned, the newest revision is shown and labelled as the newest',
      (tester) async {
    final repo = _FakeSummaryRepo(
      role: TourRole.member,
      revisions: [_older, _newer],
    );
    await _pump(tester, _screen(repo));

    expect(find.text('Newest revision'), findsOneWidget);
    expect(find.text('Pinned by an admin'), findsNothing);
  });

  testWidgets(
      'a member adds a revision in their own name, and it becomes the newest',
      (tester) async {
    final repo = _FakeSummaryRepo(
      role: TourRole.member,
      revisions: [_older],
    );
    await _pump(tester, _screen(repo));

    await tester.tap(find.text('Add a revision'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Written here.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['add: Written here.']);
    expect(find.text('Written here.'), findsWidgets);
  });

  testWidgets(
      'a member restores an older revision as a new revision that names it',
      (tester) async {
    final repo = _FakeSummaryRepo(
      role: TourRole.member,
      revisions: [_older, _newer],
    );
    await _pump(tester, _screen(repo));

    await tester.tap(find.text('Old summary.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore this revision'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['restore r1: Old summary.']);
  });

  testWidgets(
      'an admin pins a revision for the group, and the pinned label follows',
      (tester) async {
    final repo = _FakeSummaryRepo(
      role: TourRole.admin,
      revisions: [_older, _newer],
    );
    await _pump(tester, _screen(repo));

    await tester.tap(find.text('Old summary.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin for the group'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['pin r1']);
    expect(find.text('Pinned by an admin'), findsOneWidget);
    expect(find.text('Newest revision'), findsNothing);
  });
}
