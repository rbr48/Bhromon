import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_banking_master_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_firestore.dart';

const _tour = 't1';
const _subject = 's1';
const _book = 'b1';

/// The repository signed in as an admin, over the in-memory store.
class _Repo extends TourGroupRepository {
  _Repo(FakeFirestore store) : super(firestore: store);

  @override
  String get currentEmail => 'admin@x.com';
}

void main() {
  group('master item ids', () {
    test('an id is the same each time and differs by scope, kind and title',
        () {
      final tip =
          StudyBankingMasterCatalog.masterItemId('BA', 'tip', 'Exam Blueprint');

      expect(
        StudyBankingMasterCatalog.masterItemId('BA', 'tip', 'Exam Blueprint'),
        tip,
      );
      expect(
        StudyBankingMasterCatalog.masterItemId('BA', 'paper', 'Exam Blueprint'),
        isNot(tip),
      );
      expect(
        StudyBankingMasterCatalog.masterItemId('BA', 'tip', 'Another title'),
        isNot(tip),
      );
      expect(
        StudyBankingMasterCatalog.masterItemId('LPGB', 'tip', 'Exam Blueprint'),
        isNot(tip),
      );
      expect(tip, startsWith('master_'));
    });

    test('the items of every subject have distinct ids within the subject', () {
      for (final code in StudyBankingMasterCatalog.allSubjectCodes) {
        final ids = [
          for (final t in StudyBankingMasterCatalog.tipsFor(code))
            StudyBankingMasterCatalog.masterItemId(code, 'tip', t.title),
          for (final p in StudyBankingMasterCatalog.problemsFor(code))
            StudyBankingMasterCatalog.masterItemId(code, 'problem', p.title),
          for (final p in StudyBankingMasterCatalog.pastPapersFor(code))
            StudyBankingMasterCatalog.masterItemId(code, 'paper', p.title),
        ];
        expect(ids.toSet(), hasLength(ids.length), reason: code);
      }
    });

    test('the glossary terms of every subject have distinct ids in their book',
        () {
      for (final code in StudyBankingMasterCatalog.allSubjectCodes) {
        final ids = [
          for (final g in StudyBankingMasterCatalog.glossaryFor(code))
            StudyBankingMasterCatalog.masterItemId(
                StudyBankingMasterCatalog.glossaryScope, 'term', g.term),
        ];
        expect(ids.toSet(), hasLength(ids.length), reason: code);
      }
    });
  });

  group('loading the official pack again', () {
    test('a post is created once, and a second load leaves it as it is',
        () async {
      final store = FakeFirestore();
      final repo = _Repo(store);
      final id =
          StudyBankingMasterCatalog.masterItemId('BA', 'tip', 'Exam Blueprint');
      const path = 'tours/$_tour/study_subjects/$_subject/tips';

      expect(
        await repo.addStudyPostIfAbsent(
          _tour,
          _subject,
          StudyModuleKey.tips,
          id: id,
          title: 'Exam Blueprint',
          text: 'The official words',
          shown: true,
        ),
        isTrue,
      );
      expect(store.docsIn(path), hasLength(1));

      // A member or admin edits the loaded post. A second load must not overwrite it.
      store.seed(path, id, {'text': 'Edited words', 'shown': true});

      expect(
        await repo.addStudyPostIfAbsent(
          _tour,
          _subject,
          StudyModuleKey.tips,
          id: id,
          title: 'Exam Blueprint',
          text: 'The official words',
          shown: true,
        ),
        isFalse,
      );
      expect(store.docsIn(path), hasLength(1));
      expect(store.read('$path/$id')!['text'], 'Edited words');
    });

    test('a problem is created once and says whether it was new', () async {
      final store = FakeFirestore();
      final repo = _Repo(store);
      final id = StudyBankingMasterCatalog.masterItemId(
          'BA', 'problem', 'Break-Even Point');
      const path = 'tours/$_tour/study_subjects/$_subject/problems';

      for (var pass = 0; pass < 2; pass++) {
        final created = await repo.addStudyProblemIfAbsent(
          _tour,
          _subject,
          id: id,
          title: 'Break-Even Point',
          text: 'Work out the break-even point.',
          releaseAt: DateTime.utc(2026, 11, 11),
          shown: true,
        );
        expect(created, pass == 0);
      }
      expect(store.docsIn(path), hasLength(1));
    });

    test('a reference solution is saved once and an existing one stays',
        () async {
      final store = FakeFirestore();
      final repo = _Repo(store);
      const problemId = 'master_problem_example';
      const path =
          'tours/$_tour/study_subjects/$_subject/problems/$problemId/reference';

      expect(
        await repo.saveStudyReferenceIfAbsent(_tour, _subject, problemId,
            text: 'Model answer'),
        isTrue,
      );
      store.seed(path, 'solution', {'text': 'Edited answer'});
      expect(
        await repo.saveStudyReferenceIfAbsent(_tour, _subject, problemId,
            text: 'Model answer'),
        isFalse,
      );
      expect(store.read('$path/solution')!['text'], 'Edited answer');
    });

    test('a glossary term is added once to its book', () async {
      final store = FakeFirestore();
      final repo = _Repo(store);
      final id = StudyBankingMasterCatalog.masterItemId(
          StudyBankingMasterCatalog.glossaryScope, 'term', 'Liquidity');
      const path = 'tours/$_tour/study_books/$_book/glossary';

      for (var pass = 0; pass < 2; pass++) {
        final added = await repo.addGlossaryTermIfAbsent(
          _tour,
          _book,
          id: id,
          term: 'Liquidity',
          definition: 'The ability to meet obligations as they fall due.',
          approved: true,
        );
        expect(added, pass == 0);
      }
      expect(store.docsIn(path), hasLength(1));
    });
  });
}
