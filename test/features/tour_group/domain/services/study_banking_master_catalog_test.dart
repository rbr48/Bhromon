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

    test('resolves all 14 AIBB subject codes accurately', () {
      final aibbCases = <String, String>{
        'Risk Management in Financial Institutions (RMFI)':
            StudyBankingMasterCatalog.codeRMFI,
        'RMFI-201': StudyBankingMasterCatalog.codeRMFI,
        'ঝুঁকি ব্যবস্থাপনা': StudyBankingMasterCatalog.codeRMFI,
        'Credit Operations and Management (COM)':
            StudyBankingMasterCatalog.codeCOM,
        '202 (COM)': StudyBankingMasterCatalog.codeCOM,
        'ক্রেডিট অপারেশন ও ম্যানেজমেন্ট': StudyBankingMasterCatalog.codeCOM,
        'Trade Finance and Foreign Exchange (TFFE)':
            StudyBankingMasterCatalog.codeTFFE,
        'TFFE 203': StudyBankingMasterCatalog.codeTFFE,
        'ট্রেড ফাইন্যান্স ও বৈদেশিক বাণিজ্য':
            StudyBankingMasterCatalog.codeTFFE,
        'Information & Communication Technology in Financial Institutions (ICTFI)':
            StudyBankingMasterCatalog.codeICTFI,
        'ICTFI-204': StudyBankingMasterCatalog.codeICTFI,
        'আর্থিক প্রতিষ্ঠানে আইসিটি': StudyBankingMasterCatalog.codeICTFI,
        'Governance in Financial Institutions (GFI)':
            StudyBankingMasterCatalog.codeGFI,
        'GFI-205': StudyBankingMasterCatalog.codeGFI,
        'Treasury Management in Financial Institutions (TMFI)':
            StudyBankingMasterCatalog.codeTMFI,
        'TMFI 206': StudyBankingMasterCatalog.codeTMFI,
        'ট্রেজারি ম্যানেজমেন্ট': StudyBankingMasterCatalog.codeTMFI,
        'Financial Crime and Compliance (FCC)':
            StudyBankingMasterCatalog.codeFCC,
        'FCC-207': StudyBankingMasterCatalog.codeFCC,
        'আর্থিক অপরাধ ও কমপ্লায়েন্স': StudyBankingMasterCatalog.codeFCC,
        'Agriculture and Microfinance (AM)': StudyBankingMasterCatalog.codeAM,
        'AM-208': StudyBankingMasterCatalog.codeAM,
        'কৃষি ও ক্ষুদ্রঋণ ব্যাংকিং': StudyBankingMasterCatalog.codeAM,
        'Marketing and Branding in Financial Services (MBFS)':
            StudyBankingMasterCatalog.codeMBFS,
        'MBFS 209': StudyBankingMasterCatalog.codeMBFS,
        'মার্কেটিং ও ব্র্যান্ডিং': StudyBankingMasterCatalog.codeMBFS,
        'Sustainable Finance (SF)': StudyBankingMasterCatalog.codeSF,
        'SF-210': StudyBankingMasterCatalog.codeSF,
        'সাসটেইনেবল ফাইন্যান্স ও গ্রিন ব্যাংকিং':
            StudyBankingMasterCatalog.codeSF,
        'Shariah-Based Banking (SBB)': StudyBankingMasterCatalog.codeSBB,
        'SBB 211': StudyBankingMasterCatalog.codeSBB,
        'শরীয়াহ ভিত্তিক ব্যাংকিং': StudyBankingMasterCatalog.codeSBB,
        'Investment Banking (IB)': StudyBankingMasterCatalog.codeIB,
        'IB-212': StudyBankingMasterCatalog.codeIB,
        'ইনভেস্টমেন্ট ব্যাংকিং': StudyBankingMasterCatalog.codeIB,
        'Accounting for Financial Institutions (AFI)':
            StudyBankingMasterCatalog.codeAFI,
        'AFI 206A': StudyBankingMasterCatalog.codeAFI,
        'আর্থিক প্রতিষ্ঠানের হিসাববিজ্ঞান': StudyBankingMasterCatalog.codeAFI,
        'Management Accounting (MA)': StudyBankingMasterCatalog.codeMA,
        'MA-208A': StudyBankingMasterCatalog.codeMA,
        'ব্যবস্থাপনা হিসাববিজ্ঞান': StudyBankingMasterCatalog.codeMA,
      };

      for (final entry in aibbCases.entries) {
        final subject = StudySubject(
          id: 'test_aibb_sub',
          title: entry.key,
          code: entry.key,
        );
        expect(
          StudyBankingMasterCatalog.resolveSubjectCode(subject),
          equals(entry.value),
          reason: 'Failed to resolve AIBB code for: ${entry.key}',
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

    test(
        'contains comprehensive, examiner-grade content for all 20 banking subjects (JAIBB & AIBB)',
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
