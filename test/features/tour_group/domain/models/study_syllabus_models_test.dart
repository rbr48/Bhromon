import 'package:bhromon/features/tour_group/domain/models/study_syllabus_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StudySyllabusCatalog', () {
    test(
        'resolves official modules for all 7 IBB JAIBB subjects by acronym and title',
        () {
      final subjects = [
        ('LPGB', 'Laws & Practice of General Banking'),
        ('POE', 'Principles of Economics'),
        ('MAFS', 'Management Accounting for Financial Services'),
        ('OM', 'Organization & Management'),
        ('GFI', 'Governance in Financial Institutions'),
        ('BCFI', 'Business Communication in Financial Institutions'),
        ('BA', 'Business Analytics in Banking'),
      ];

      for (final (code, title) in subjects) {
        final modulesByCode = StudySyllabusCatalog.modulesFor(code);
        final modulesByTitle = StudySyllabusCatalog.modulesFor(title);

        expect(modulesByCode.length, 5, reason: 'Expected 5 modules for $code');
        expect(modulesByTitle.length, 5,
            reason: 'Expected 5 modules for $title');

        final codes = modulesByCode.map((m) => m.code).toList();
        expect(codes, equals(['A', 'B', 'C', 'D', 'E']));
      }
    });

    test(
        'accurately identifies syllabus module from question text using keyword matching',
        () {
      // LPGB Question test: Bank Company Act
      final mod1 = StudySyllabusCatalog.identifyModule(
        'LPGB',
        'What are the restrictions on loans and advances under the Bank Company Act 1991?',
      );
      expect(mod1?.code, 'A');

      // LPGB Question test: Banker-Customer / KYC
      final mod2 = StudySyllabusCatalog.identifyModule(
        'LPGB',
        'Describe the KYC and Customer Due Diligence (CDD) procedures for opening an account.',
      );
      expect(mod2?.code, 'B');

      // LPGB Question test: Cheque / Crossing
      final mod3 = StudySyllabusCatalog.identifyModule(
        'LPGB',
        'Explain the legal effects of special crossing and not negotiable crossing on a cheque.',
      );
      expect(mod3?.code, 'C');

      // LPGB Question test: Mortgage / Artha Rin
      final mod4 = StudySyllabusCatalog.identifyModule(
        'LPGB',
        'Distinguish between mortgage and pledge. What are the recovery provisions under Artha Rin Adalat Act?',
      );
      expect(mod4?.code, 'D');

      // LPGB Question test: Letter of Credit / UCP 600
      final mod5 = StudySyllabusCatalog.identifyModule(
        'LPGB',
        'Explain the rights and liabilities of issuing bank under Letter of Credit as per UCP 600.',
      );
      expect(mod5?.code, 'E');
    });

    test('accurately identifies syllabus module from Bengali question text',
        () {
      // Bengali LPGB Question test: গার্নিশি অর্ডার (Garnishee order) -> Module B
      final modB = StudySyllabusCatalog.identifyModule(
        'LPGB',
        'গার্নিশি অর্ডার (Garnishee Order) বলতে কী বুঝায়? ব্যাংকারের করণীয় ব্যাখ্যা করুন।',
      );
      expect(modB?.code, 'B');

      // Bengali LPGB Question test: অর্থ ঋণ আদালত -> Module D
      final modD = StudySyllabusCatalog.identifyModule(
        'LPGB',
        'অর্থ ঋণ আদালত আইন অনুযায়ী ঋণখেলাপিদের বিরুদ্ধে মামলা দায়েরের প্রক্রিয়া কী?',
      );
      expect(modD?.code, 'D');
    });

    test('returns empty list for unrecognized non-banking subjects', () {
      final modules = StudySyllabusCatalog.modulesFor('UNKNOWN_SUBJECT_XYZ');
      expect(modules, isEmpty);

      final identified = StudySyllabusCatalog.identifyModule(
        'UNKNOWN_SUBJECT_XYZ',
        'Some arbitrary question content',
      );
      expect(identified, isNull);
    });

    test(
        'avoids false-positive partial substring matches using boundary isolation',
        () {
      // "action" must not falsely match keyword "act", and "current" must not match "crr"
      final mod = StudySyllabusCatalog.identifyModule(
        'LPGB',
        'The candidate took immediate action to practice general routines without banking regulation.',
      );
      expect(mod, isNull);
    });

    test('a short code matches only as a whole word', () {
      // "OM" sits inside "INCOME" and "COMMERCE", and "BA" inside "BANGLA" and "DATABASE".
      for (final title in [
        'Income Tax',
        'Computer Science',
        'Comprehensive Finance',
        'Commerce',
        'Economic Geography',
        'Bangla',
        'Database Systems',
        'Bangladesh Studies',
      ]) {
        expect(StudySyllabusCatalog.modulesFor(title), isEmpty, reason: title);
      }

      expect(
        StudySyllabusCatalog.identifyModule(
          'Income Tax',
          'What is the income tax rate for a salary?',
        ),
        isNull,
      );
    });

    test(
        'Basic Accounting is the BA course, and Management Accounting stays MAFS',
        () {
      expect(
        StudySyllabusCatalog.modulesFor('Basic Accounting').map((m) => m.id),
        StudySyllabusCatalog.modulesFor('BA').map((m) => m.id),
      );
      expect(
        StudySyllabusCatalog.modulesFor('Management Accounting')
            .map((m) => m.id),
        StudySyllabusCatalog.modulesFor('MAFS').map((m) => m.id),
      );
    });
  });
}
