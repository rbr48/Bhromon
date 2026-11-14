import 'package:bhromon/features/tour_group/domain/models/study_glossary_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_glossary_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StudyGlossaryRules Unit Tests', () {
    test('termProblem validates empty and non-empty terms', () {
      expect(
        termProblem(term: '', definition: 'some definition'),
        StudyTermProblem.emptyTerm,
      );
      expect(
        termProblem(term: '   ', definition: 'some definition'),
        StudyTermProblem.emptyTerm,
      );
      expect(
        termProblem(term: 'Valid Term', definition: ''),
        StudyTermProblem.emptyDefinition,
      );
      expect(
        termProblem(term: 'Valid Term', definition: '   '),
        StudyTermProblem.emptyDefinition,
      );
      expect(
        termProblem(term: 'Valid Term', definition: 'Valid definition'),
        isNull,
      );
    });

    test('approvedTerms filters out unapproved proposals and sorts A to Z', () {
      const terms = [
        StudyGlossaryTerm(
          id: '1',
          term: 'Zebra',
          definition: 'Animal',
          approved: true,
          createdByEmail: 'admin@x.com',
        ),
        StudyGlossaryTerm(
          id: '2',
          term: 'Apple',
          definition: 'Fruit',
          approved: false, // proposal
          createdByEmail: 'user@x.com',
        ),
        StudyGlossaryTerm(
          id: '3',
          term: 'banana',
          definition: 'Fruit',
          approved: true,
          createdByEmail: 'admin@x.com',
        ),
      ];

      final res = approvedTerms(terms);
      expect(res.length, 2);
      expect(res[0].term, 'banana');
      expect(res[1].term, 'Zebra');
    });

    test('canApproveTerm only allows admins', () {
      expect(canApproveTerm(isAdmin: true), isTrue);
      expect(canApproveTerm(isAdmin: false), isFalse);
    });

    test('canRemoveTerm allows admins or author of pending proposal', () {
      const proposal = StudyGlossaryTerm(
        id: '1',
        term: 'Term',
        definition: 'Def',
        approved: false,
        createdByEmail: 'author@x.com',
      );

      const approved = StudyGlossaryTerm(
        id: '2',
        term: 'Term',
        definition: 'Def',
        approved: true,
        createdByEmail: 'author@x.com',
      );

      // Proposal
      expect(
        canRemoveTerm(proposal, viewerEmail: 'author@x.com', isAdmin: false),
        isTrue,
      );
      expect(
        canRemoveTerm(proposal, viewerEmail: 'other@x.com', isAdmin: false),
        isFalse,
      );
      expect(
        canRemoveTerm(proposal, viewerEmail: 'other@x.com', isAdmin: true),
        isTrue,
      );

      // Approved
      expect(
        canRemoveTerm(approved, viewerEmail: 'author@x.com', isAdmin: false),
        isFalse,
      );
      expect(
        canRemoveTerm(approved, viewerEmail: 'author@x.com', isAdmin: true),
        isTrue,
      );
    });

    test('searchGlossaryTerms handles markdown stripping, casing, and accents',
        () {
      const list = [
        StudyGlossaryTerm(
          id: '1',
          term: 'Accounting Cost vs. Economic Cost',
          definition: 'প্রকাশ্য ব্যয় + অপ্রকাশ্য সুযোগ ব্যয় (`৬ষ্ঠ Q9f`)',
          approved: true,
          createdByEmail: 'admin@x.com',
          chapterId: 'c1',
        ),
        StudyGlossaryTerm(
          id: '2',
          term: 'Aggregate Demand — AD',
          definition: '`AD = C + I + G + [X - M]`',
          approved: true,
          createdByEmail: 'admin@x.com',
          chapterId: 'c2',
        ),
      ];

      expect(searchGlossaryTerms(list, query: 'economic').length, 1);
      expect(searchGlossaryTerms(list, query: '৬ষ্ঠ q9f').length, 1);
      expect(searchGlossaryTerms(list, query: 'AD = C').length, 1);
      expect(searchGlossaryTerms(list, query: 'ad', chapterId: 'c2').length, 1);
      expect(searchGlossaryTerms(list, query: 'ad', chapterId: 'c1').length, 0);
    });
  });
}
