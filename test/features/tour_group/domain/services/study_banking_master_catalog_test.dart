import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_banking_master_catalog.dart';

void main() {
  group('StudyBankingMasterCatalog', () {
    test('resolves all 7 JAIBB subject codes accurately', () {
      final cases = <String, String>{
        'Basic Accounting & Business Analytics (BA)':
            StudyBankingMasterCatalog.codeBA,
        '102 (BA)': StudyBankingMasterCatalog.codeBA,
        'বেসিক অ্যাকাউন্টিং ও বিজনেস অ্যানালিটিক্স':
            StudyBankingMasterCatalog.codeBA,
        'Laws and Practice of General Banking (LPGB)':
            StudyBankingMasterCatalog.codeLPGB,
        'LPGB-101': StudyBankingMasterCatalog.codeLPGB,
        'জেনারেল ব্যাংকিং আইন ও প্রয়োগ': StudyBankingMasterCatalog.codeLPGB,
        'Principles of Economics (POE)': StudyBankingMasterCatalog.codePOE,
        'POE 102': StudyBankingMasterCatalog.codePOE,
        'অর্থনীতি নীতিমালা': StudyBankingMasterCatalog.codePOE,
        'Monetary and Financial Systems (MAFS)':
            StudyBankingMasterCatalog.codeMAFS,
        'MAFS': StudyBankingMasterCatalog.codeMAFS,
        'আর্থিক ব্যবস্থা ও মুদ্রানীতি': StudyBankingMasterCatalog.codeMAFS,
        'Governance in Financial Institutions (GFI)':
            StudyBankingMasterCatalog.codeGFI,
        'GFI-102': StudyBankingMasterCatalog.codeGFI,
        'আর্থিক প্রতিষ্ঠানে সুশাসন': StudyBankingMasterCatalog.codeGFI,
        'Organization and Management (OM)': StudyBankingMasterCatalog.codeOM,
        'OM-106': StudyBankingMasterCatalog.codeOM,
        'সংগঠন ও ব্যবস্থাপনা': StudyBankingMasterCatalog.codeOM,
        'Business Communication in Financial Institutions (BCFI)':
            StudyBankingMasterCatalog.codeBCFI,
        'BCFI-105': StudyBankingMasterCatalog.codeBCFI,
        'ব্যবসায়িক যোগাযোগ': StudyBankingMasterCatalog.codeBCFI,
      };

      for (final entry in cases.entries) {
        final subject = StudySubject(
          id: 'test_sub',
          title: entry.key,
          code: entry.key,
        );
        expect(
          StudyBankingMasterCatalog.resolveSubjectCode(subject),
          equals(entry.value),
          reason: 'Failed to resolve code for: ${entry.key}',
        );
      }
    });

    test('returns null for non-banking subjects without IBB leakage', () {
      final nonBankingSubjects = [
        'Advanced Python Programming',
        'Machine Learning & AI',
        'Calculus III',
        'dhh',
        'gyg',
        'Organic Chemistry',
      ];

      for (final title in nonBankingSubjects) {
        final subject = StudySubject(
          id: 'non_bank',
          title: title,
        );
        expect(
          StudyBankingMasterCatalog.resolveSubjectCode(subject),
          isNull,
          reason: 'Expected null for non-banking subject: $title',
        );
        expect(
          StudyBankingMasterCatalog.isBankingSubject(subject),
          isFalse,
        );
      }
    });

    test('contains comprehensive, examiner-grade content for all 7 subjects',
        () {
      for (final code in StudyBankingMasterCatalog.allSubjectCodes) {
        // Tips check
        final tips = StudyBankingMasterCatalog.tipsFor(code);
        expect(tips.isNotEmpty, isTrue, reason: 'Missing tips for $code');
        for (final tip in tips) {
          expect(tip.title.trim().isNotEmpty, isTrue);
          expect(tip.text.trim().length, greaterThan(50));
        }

        // Problems check
        final problems = StudyBankingMasterCatalog.problemsFor(code);
        expect(problems.isNotEmpty, isTrue,
            reason: 'Missing problems for $code');
        for (final problem in problems) {
          expect(problem.title.trim().isNotEmpty, isTrue);
          expect(problem.text.trim().length, greaterThan(30));
          expect(problem.solution.trim().length, greaterThan(50));
        }

        // Past papers check
        final papers = StudyBankingMasterCatalog.pastPapersFor(code);
        expect(papers.isNotEmpty, isTrue,
            reason: 'Missing past papers for $code');
        for (final paper in papers) {
          expect(paper.title.trim().isNotEmpty, isTrue);
          expect(paper.text.trim().length, greaterThan(30));
        }

        // Glossary check
        final glossary = StudyBankingMasterCatalog.glossaryFor(code);
        expect(glossary.isNotEmpty, isTrue,
            reason: 'Missing glossary for $code');
        for (final term in glossary) {
          expect(term.term.trim().isNotEmpty, isTrue);
          expect(term.definition.trim().length, greaterThan(20));
        }
      }
    });
  });
}
