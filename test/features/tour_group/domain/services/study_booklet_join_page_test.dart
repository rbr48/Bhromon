import 'dart:convert';
import 'dart:typed_data';

import 'package:bhromon/features/tour_group/domain/services/invite_join_link.dart';
import 'package:bhromon/features/tour_group/domain/services/study_booklet_pdf_generator.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/invite_qr_code.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pages in a PDF: each page is written as `/Type /Page`, and the page tree as `/Type /Pages`.
int _pageCount(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page(?!s)').allMatches(latin1.decode(bytes)).length;

/// A one-chapter booklet, with a join code unless [inviteCode] is null.
StudyBookletContent _booklet({String? inviteCode, int chapters = 1}) {
  return StudyBookletContent(
    subjectTitle: 'Laws and Practice of General Banking',
    subjectCode: 'LPGB',
    tourName: 'JAIBB Diploma Study Circle',
    inviteCode: inviteCode,
    chapters: [
      for (var n = 1; n <= chapters; n++)
        StudyBookletChapterItem(
          number: n,
          title: '96th BPE (May 2023)',
          questions: const [
            StudyBookletQuestionItem(
              questionNumber: '1',
              title: 'প্রশ্ন ১ [মান: ১০]',
              pieces: [
                StudyBookletText(
                  'ব্যাংক কোম্পানি আইন ১৯৯১ অনুসারে তফসিলি ব্যাংকের লাইসেন্সিং প্রক্রিয়া সম্পন্ন হয়।',
                ),
              ],
            ),
          ],
        ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const generator = StudyBookletPdfGenerator();

  group('the watermark name', () {
    test('keeps a short name and joins its spaces into one line', () {
      expect(
        StudyBookletPdfGenerator.watermarkGroupName('  Trip \n  Circle  '),
        'Trip Circle',
      );
      expect(StudyBookletPdfGenerator.watermarkGroupName(''), '');
    });

    test('cuts a long name at a word break, with an ellipsis', () {
      const name =
          'Sonali Bank JAIBB Diploma Study Circle for the Dhaka Branch Officers';
      final cut = StudyBookletPdfGenerator.watermarkGroupName(name);

      expect(cut.endsWith('…'), isTrue);
      expect(cut.length, lessThanOrEqualTo(41));
      final head = cut.substring(0, cut.length - 1);
      expect(name.startsWith(head), isTrue);
      expect(name[head.length], ' ', reason: 'the cut falls on a word break');
    });

    test('cuts a name with no space at its maximum length', () {
      const name = 'Averyveryverylongsinglewordgroupnamewithoutanyspacesatall';
      final cut = StudyBookletPdfGenerator.watermarkGroupName(name);

      expect(cut, '${name.substring(0, 40)}…');
    });
  });

  group('the join code', () {
    test('is trimmed, in capitals, and absent when the group has none', () {
      expect(
        StudyBookletPdfGenerator.joinCodeOf(_booklet(inviteCode: ' ab12cd34 ')),
        'AB12CD34',
      );
      expect(
        StudyBookletPdfGenerator.joinCodeOf(_booklet(inviteCode: '   ')),
        isNull,
      );
      expect(StudyBookletPdfGenerator.joinCodeOf(_booklet()), isNull);
    });
  });

  group('the join QR code', () {
    test('is the same matrix the app draws on screen', () {
      final printed = StudyBookletPdfGenerator.inviteJoinQr('ab12cd34');
      final onScreen = inviteQrImage(inviteJoinLink('AB12CD34'));

      expect(printed.moduleCount, onScreen.moduleCount);
      for (var row = 0; row < onScreen.moduleCount; row++) {
        for (var col = 0; col < onScreen.moduleCount; col++) {
          expect(
            printed.isDark(row, col),
            onScreen.isDark(row, col),
            reason: 'module $row,$col',
          );
        }
      }
    });
  });

  group('the booklet pages', () {
    test('a booklet with no chapters is a cover and a closing page', () async {
      final bytes = await generator.generateBookletPdf(
        _booklet(inviteCode: 'AB12CD34', chapters: 0),
        isBengali: false,
      );

      expect(_pageCount(bytes), 2);
    });

    test('the join code adds no page: cover, chapters and closing page only',
        () async {
      final withCode = await generator.generateBookletPdf(
        _booklet(inviteCode: 'AB12CD34'),
        isBengali: true,
      );
      final withoutCode = await generator.generateBookletPdf(
        _booklet(),
        isBengali: true,
      );

      expect(_pageCount(withCode), _pageCount(withoutCode));
      expect(_pageCount(withCode), greaterThanOrEqualTo(3));
    });

    test('an English booklet with a join code builds', () async {
      final bytes = await generator.generateBookletPdf(
        _booklet(inviteCode: 'AB12CD34'),
        isBengali: false,
      );

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
