import 'dart:io';

import 'package:bhromon/features/tour_group/data/study_offline_vault.dart';
import 'package:bhromon/features/tour_group/domain/models/study_material_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_offline_vault_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('study_offline_vault_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(StudyOfflineVault.boxName);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('StudyOfflinePackage serialization', () {
    test('serializes and deserializes cleanly with all fields', () {
      final pkg = StudyOfflinePackage(
        tourId: 'tour_123',
        bookId: 'book_lpgb',
        bookTitle: 'Laws & Practice of General Banking',
        cachedAt: DateTime(2026, 11, 10, 14, 30),
        totalSizeBytes: 1250000,
        chapters: const [
          StudyChapter(
            id: 'chap_1',
            number: 1,
            title: '96th BPE (May 2023)',
            guide: ['Q1', 'Q2'],
          ),
          StudyChapter(
            id: 'chap_2',
            number: 2,
            title: '97th BPE (Nov 2023)',
          ),
        ],
        materials: const [
          StudyMaterial(
            id: 'mat_en',
            title: '96th BPE Solution (English)',
            kind: StudyMaterialKind.file,
            bookId: 'book_lpgb',
            chapterId: 'chap_1',
            fileName: '96th_lpgb_en.md',
            sizeBytes: 45000,
          ),
          StudyMaterial(
            id: 'mat_bn',
            title: '৯৬তম BPE সমাধান (বাংলা)',
            kind: StudyMaterialKind.note,
            bookId: 'book_lpgb',
            chapterId: 'chap_1',
            body: '# ৯৬তম BPE সমাধান\n\nপ্রশ্ন ১ এর উত্তর...',
            sizeBytes: 85000,
          ),
        ],
        contents: const {
          'mat_en': '# 96th BPE Solution\n\nAnswer to Question 1...',
          'mat_bn': '# ৯৬তম BPE সমাধান\n\nপ্রশ্ন ১ এর উত্তর...',
        },
      );

      final json = pkg.toJson();
      final roundTrip = StudyOfflinePackage.fromJson(json);

      expect(roundTrip, isNotNull);
      expect(roundTrip!.tourId, 'tour_123');
      expect(roundTrip.bookId, 'book_lpgb');
      expect(roundTrip.bookTitle, 'Laws & Practice of General Banking');
      expect(roundTrip.totalSizeBytes, 1250000);
      expect(roundTrip.formattedSize, '1.2 MB');
      expect(roundTrip.chapterCount, 2);
      expect(roundTrip.materialCount, 2);
      expect(roundTrip.contentFor('mat_en'), contains('Answer to Question 1'));
      expect(roundTrip.contentFor('mat_bn'), contains('প্রশ্ন ১ এর উত্তর'));
    });

    test('handles empty or malformed json gracefully', () {
      expect(StudyOfflinePackage.fromJson(const {}), isNull);
      expect(StudyOfflinePackage.fromJson({'tourId': ''}), isNull);
      expect(
          StudyOfflinePackage.fromJson({'tourId': 't', 'bookId': ''}), isNull);
    });

    test('formattedSize scales correctly across byte units', () {
      StudyOfflinePackage createPkg(int bytes) => StudyOfflinePackage(
            tourId: 't',
            bookId: 'b',
            bookTitle: 'Test',
            cachedAt: DateTime.now(),
            totalSizeBytes: bytes,
            chapters: const [],
            materials: const [],
            contents: const {},
          );

      expect(createPkg(0).formattedSize, '0 B');
      expect(createPkg(512).formattedSize, '512 B');
      expect(createPkg(45000).formattedSize, '44 KB');
      expect(createPkg(2500000).formattedSize, '2.4 MB');
    });
  });

  group('StudyOfflineVault storage operations', () {
    test('saves, retrieves, checks, and removes packages', () async {
      final vault = StudyOfflineVault();

      expect(await vault.isCached('tour_1', 'book_1'), isFalse);
      expect(await vault.getPackage('tour_1', 'book_1'), isNull);

      final pkg1 = StudyOfflinePackage(
        tourId: 'tour_1',
        bookId: 'book_1',
        bookTitle: 'LPGB',
        cachedAt: DateTime(2026, 11, 10, 10),
        totalSizeBytes: 500000,
        chapters: const [
          StudyChapter(id: 'c1', number: 1, title: 'Chapter 1'),
        ],
        materials: const [],
        contents: const {'m1': 'content 1'},
      );

      final pkg2 = StudyOfflinePackage(
        tourId: 'tour_1',
        bookId: 'book_2',
        bookTitle: 'POE',
        cachedAt: DateTime(2026, 11, 10, 12),
        totalSizeBytes: 700000,
        chapters: const [
          StudyChapter(id: 'c2', number: 1, title: 'Chapter 2'),
        ],
        materials: const [],
        contents: const {'m2': 'content 2'},
      );

      await vault.savePackage(pkg1);
      await vault.savePackage(pkg2);

      expect(await vault.isCached('tour_1', 'book_1'), isTrue);
      expect(await vault.isCached('tour_1', 'book_2'), isTrue);
      expect(await vault.isCached('tour_1', 'book_3'), isFalse);

      final loaded1 = await vault.getPackage('tour_1', 'book_1');
      expect(loaded1, isNotNull);
      expect(loaded1!.bookTitle, 'LPGB');
      expect(loaded1.contentFor('m1'), 'content 1');

      final list = await vault.listPackages('tour_1');
      expect(list.length, 2);
      expect(list.first.bookTitle, 'POE'); // sorted by cachedAt descending

      final totalBytes = await vault.totalCachedBytes('tour_1');
      expect(totalBytes, 1200000);

      await vault.removePackage('tour_1', 'book_1');
      expect(await vault.isCached('tour_1', 'book_1'), isFalse);
      expect(await vault.isCached('tour_1', 'book_2'), isTrue);

      await vault.clearAll('tour_1');
      expect(await vault.listPackages('tour_1'), isEmpty);
    });
  });
}
