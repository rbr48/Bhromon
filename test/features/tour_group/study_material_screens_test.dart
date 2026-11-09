import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_material_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_materials_screen.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_material_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The materials of a book, with a fake repository that records each change. The rules these screens
// follow are tested on the emulator in functions/tests/study_materials_rules.test.js.

class _FakeMaterialsRepo extends TourGroupRepository {
  _FakeMaterialsRepo({
    this.materials = const [],
    this.role,
  });

  final List<StudyMaterial> materials;
  final TourRole? role;
  final bool needsApproval = true;
  final List<String> calls = [];

  @override
  String get currentEmail => 'me@x.com';

  @override
  Future<TourRole?> myRole(String tourId) async => role;

  @override
  Stream<List<StudyMaterial>> watchStudyMaterials(
          String tourId, String bookId) =>
      Stream.value(materials);

  @override
  Stream<List<StudyChapter>> watchStudyChapters(String tourId, String bookId) =>
      Stream.value(const []);

  @override
  Stream<bool> watchMaterialsNeedApproval(String tourId) =>
      Stream.value(needsApproval);

  @override
  Future<void> reportStudyMaterial(
    String tourId,
    String materialId, {
    required StudyMaterialReportReason reason,
  }) async {
    calls.add('report $materialId ${reason.name}');
  }

  @override
  Future<void> publishStudyMaterial(String tourId, String materialId) async {
    calls.add('publish $materialId');
  }

  @override
  Future<void> setMaterialsNeedApproval(
    String tourId, {
    required bool needsApproval,
  }) async {
    calls.add('approval $needsApproval');
  }

  @override
  Future<void> markStudyMaterialOpened(
      String tourId, String materialId) async {}

  @override
  Future<void> addStudyMaterial(
    String tourId, {
    required String bookId,
    required StudyMaterialKind kind,
    required String title,
    required bool isAdmin,
    required bool needsApproval,
    String? chapterId,
    String? url,
    String? fileName,
    int? sizeBytes,
    String? body,
    String? replacesId,
  }) async {
    calls.add('add ${kind.name} $title ${body ?? ''}');
  }
}

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

const _book =
    StudyBook(id: 'b1', title: 'Anna Karenina', createdByEmail: 'admin@x.com');

final _shared = StudyMaterial(
  id: 'pub',
  title: 'Chapter one summary',
  kind: StudyMaterialKind.note,
  bookId: 'b1',
  body: 'The train appears three times.',
  status: StudyMaterialStatus.published,
  createdByEmail: 'other@x.com',
  createdAt: DateTime(2030, 1, 1),
);

final _othersWaiting = StudyMaterial(
  id: 'wait',
  title: 'Hidden draft',
  kind: StudyMaterialKind.note,
  bookId: 'b1',
  body: 'Not yet approved.',
  status: StudyMaterialStatus.pending,
  createdByEmail: 'other@x.com',
  createdAt: DateTime(2030, 1, 2),
);

final _mineWaiting = StudyMaterial(
  id: 'mine',
  title: 'My draft',
  kind: StudyMaterialKind.note,
  bookId: 'b1',
  body: 'Still mine.',
  status: StudyMaterialStatus.pending,
  createdByEmail: 'me@x.com',
  createdAt: DateTime(2030, 1, 3),
);

final _hidden = StudyMaterial(
  id: 'hid',
  title: 'Reported notes',
  kind: StudyMaterialKind.note,
  bookId: 'b1',
  body: 'Under review.',
  status: StudyMaterialStatus.hidden,
  reportCount: 1,
  reportedAt: DateTime(2030, 1, 1),
  createdByEmail: 'other@x.com',
  createdAt: DateTime(2029, 12, 30),
);

void main() {
  group('the materials of a book', () {
    testWidgets(
        'a member sees the shared material and their own waiting one, not someone else\'s',
        (tester) async {
      final repo = _FakeMaterialsRepo(
        materials: [_shared, _othersWaiting, _mineWaiting],
      );
      await _pump(
        tester,
        StudyMaterialsScreen(tourId: 'T', book: _book, repository: repo),
      );

      expect(find.text('Chapter one summary'), findsOneWidget);
      expect(find.text('Your materials'), findsOneWidget);
      expect(find.text('My draft'), findsOneWidget);
      expect(find.text('Hidden draft'), findsNothing);
    });

    testWidgets('a member reports another member\'s material with a reason',
        (tester) async {
      final repo = _FakeMaterialsRepo(materials: [_shared]);
      await _pump(
        tester,
        StudyMaterialsScreen(tourId: 'T', book: _book, repository: repo),
      );

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wrong or misleading'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['report pub wrong']);
    });

    testWidgets('an admin sees the reports to review and restores one',
        (tester) async {
      final repo =
          _FakeMaterialsRepo(materials: [_hidden], role: TourRole.admin);
      await _pump(
        tester,
        StudyMaterialsScreen(tourId: 'T', book: _book, repository: repo),
      );

      expect(find.text('Reports to review'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['publish hid']);
    });

    testWidgets('an admin turns off approval for members\' materials',
        (tester) async {
      final repo = _FakeMaterialsRepo(role: TourRole.admin);
      await _pump(
        tester,
        StudyMaterialsScreen(tourId: 'T', book: _book, repository: repo),
      );

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['approval false']);
    });

    testWidgets('a member files a note, which is saved for approval',
        (tester) async {
      final repo = _FakeMaterialsRepo();
      await _pump(
        tester,
        StudyMaterialsScreen(tourId: 'T', book: _book, repository: repo),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'My summary');
      await tester.enterText(
          find.byType(TextField).at(1), 'Anna meets Vronsky.');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share with the group'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['add note My summary Anna meets Vronsky.']);
    });
  });

  group('the material composer', () {
    testWidgets(
        'it refuses a blank title and an unconfirmed note, then returns the draft',
        (tester) async {
      StudyMaterialDraft? saved;
      await _pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showStudyMaterialComposer(
                  context,
                  chapters: const [
                    StudyChapter(id: 'c1', number: 1, title: 'First')
                  ],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share with the group'));
      await tester.pumpAndSettle();
      expect(find.text('Give the material a title.'), findsOneWidget);
      expect(saved, isNull);

      await tester.enterText(find.byType(TextField).at(0), 'Chapter notes');
      await tester.tap(find.text('Share with the group'));
      await tester.pumpAndSettle();
      expect(find.text('Write the note first.'), findsOneWidget);

      await tester.enterText(
          find.byType(TextField).at(1), 'The train appears three times.');
      await tester.tap(find.text('Share with the group'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm that you have the right to share it.'),
          findsOneWidget);
      expect(saved, isNull);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share with the group'));
      await tester.pumpAndSettle();
      expect(saved?.title, 'Chapter notes');
      expect(saved?.kind, StudyMaterialKind.note);
      expect(saved?.body, 'The train appears three times.');
      expect(saved?.chapterId, isNull);
    });

    testWidgets('a link must be a web address', (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showStudyMaterialComposer(context, chapters: const []),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Reference');
      await tester.enterText(
          find.byType(TextField).at(1), 'ftp://example.com/x');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share with the group'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter a web address that starts with http:// or https://.'),
        findsOneWidget,
      );
    });
  });
}
