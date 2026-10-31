import 'dart:convert';

import 'package:bangla_pdf/extract.dart';
import 'package:bangla_pdf/widgets.dart' as pw;
import 'package:bhromon/features/tour_group/data/tour_export_images.dart';
import 'package:bhromon/features/tour_group/data/tour_export_pdf.dart';
import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_activity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_export_data.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

TourPdfLabels _bnLabels() => TourPdfLabels(
      text: (key, {args}) {
        switch (key) {
          case 'pdf_section_checklist':
            return 'প্যাকিং চেকলিস্ট';
          case 'pdf_section_money':
            return 'হিসাব ও খরচ';
          case 'pdf_section_stories':
            return 'স্টোরিজ';
          case 'pdf_section_transport':
            return 'পরিবহন';
          case 'pdf_section_feed':
            return 'ফিড';
          case 'pdf_col_from_to':
            return 'কার থেকে — কাকে';
          case 'pdf_video':
            return 'ভিডিও';
          case 'pdf_open':
            return 'বাকি';
          case 'pdf_done':
            return 'সম্পন্ন';
          case 'check_item_id_copy':
            return 'জাতীয় পরিচয়পত্র / পাসপোর্টের ফটোকপি';
          case 'check_cat_documents':
            return 'ডকুমেন্টস';
          case 'fund_cat_food':
            return 'খাবার';
          default:
            return key;
        }
      },
      number: (n) => '$n',
      date: (d) => '${d.year}-${d.month}-${d.day}',
      dateTime: (d) => '${d.year}-${d.month}-${d.day} ${d.hour}:${d.minute}',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Bangla text shaping produces /ActualText in PDF', () async {
    const text = 'সংক্ষিপ্ত বিবরণ ও পরিবহন নিরাপত্তা';
    final doc = pw.Document(compress: false);
    doc.addPage(
      pw.Page(
        build: (context) => pw.Text(text),
      ),
    );
    final bytes = await doc.save();
    final latin = latin1.decode(bytes, allowInvalid: true);
    expect(latin.contains('/ActualText'), isTrue);
    final extracted = BanglaPdfExtractor.extract(bytes).text;
    expect(extracted, contains('সংক্ষিপ্ত বিবরণ'));
  });

  test('Checklist default items resolve titles and categories in PDF export',
      () async {
    final group = TourGroup(
      id: 't_check',
      name: 'বান্দরবান ভ্রমণ',
      ownerEmail: 'owner@bhromon.fun',
      inviteCode: 'BNDR2026',
      destination: 'Bandarban',
      originCity: 'Dhaka',
      startDate: DateTime(2026, 11, 10),
      endDate: DateTime(2026, 11, 14),
      tourType: TourType.hill,
      modules: const TourModules(),
      createdAt: DateTime(2026, 10, 1),
    );

    final checklistItem = ChecklistItem.fromMap('default_0', {
      'checkedBy': ['owner@bhromon.fun'],
    });

    final data = TourExportData(
      group: group,
      exportedAt: DateTime.now(),
      members: const [],
      notices: const [],
      checkpoints: const [],
      checklist: [checklistItem],
      expenses: const [],
      deposits: const [],
      transfers: const [],
      vehicles: const [],
      vehicleSeats: const {},
      coachSeats: const [],
      hotelRooms: const [],
      safetyAlerts: const [],
      posts: const [],
      comments: const {},
      stories: const [],
      highlights: const [],
    );

    final images = TourExportImages(
        client: MockClient((_) async => http.Response('', 404)));

    final bytes = await buildTourPdf(
      data: data,
      images: images,
      labels: _bnLabels(),
      compress: false,
    );

    final extracted = BanglaPdfExtractor.extract(bytes).text;
    expect(extracted, contains('জাতীয় পরিচয়পত্র / পাসপোর্টের ফটোকপি'));
    expect(extracted, contains('ডকুমেন্টস'));
    expect(extracted, contains('সম্পন্ন'));
  });

  test('Video story is rendered without failing image decoder', () async {
    final group = TourGroup(
      id: 't_story',
      name: 'কক্সবাজার ট্যুর',
      ownerEmail: 'owner@bhromon.fun',
      inviteCode: 'COXB2026',
      destination: "Cox's Bazar",
      originCity: 'Dhaka',
      startDate: DateTime(2026, 11, 10),
      endDate: DateTime(2026, 11, 14),
      tourType: TourType.beach,
      modules: const TourModules(),
      createdAt: DateTime(2026, 10, 1),
    );

    final story = TourStoryItem(
      id: 's_vid_1',
      authorEmail: 'traveler@bhromon.fun',
      authorName: 'Traveler',
      mediaUrl: 'https://example.com/video_story.mp4',
      createdAt: DateTime.now(),
      isVideo: true,
      caption: 'Sunset beach video',
    );

    final data = TourExportData(
      group: group,
      exportedAt: DateTime.now(),
      members: const [],
      notices: const [],
      checkpoints: const [],
      checklist: const [],
      expenses: const [],
      deposits: const [],
      transfers: const [],
      vehicles: const [],
      vehicleSeats: const {},
      coachSeats: const [],
      hotelRooms: const [],
      safetyAlerts: const [],
      posts: const [],
      comments: const {},
      stories: [story],
      highlights: const [],
    );

    final images = TourExportImages(
        client: MockClient((_) async => http.Response('', 404)));

    final bytes = await buildTourPdf(
      data: data,
      images: images,
      labels: _bnLabels(),
      compress: false,
    );

    final extracted = BanglaPdfExtractor.extract(bytes).text;
    expect(extracted, contains('ভিডিও'));
    expect(extracted, contains('Sunset beach video'));
  });

  test('Transfers use em-dash and expense categories are localized', () async {
    final group = TourGroup(
      id: 't_money',
      name: 'ট্যুর ফান্ড',
      ownerEmail: 'owner@bhromon.fun',
      inviteCode: 'FUND2026',
      destination: 'Sylhet',
      originCity: 'Dhaka',
      startDate: DateTime(2026, 11, 10),
      endDate: DateTime(2026, 11, 14),
      tourType: TourType.nature,
      modules: const TourModules(),
      createdAt: DateTime(2026, 10, 1),
    );

    final expense = ExpenseItem(
      id: 'e1',
      tourId: 't_money',
      title: 'দুপুরের খাবার',
      category: 'Food',
      amountPaisa: 150000,
      paidById: 'rahim@bhromon.fun',
      paidByName: 'Rahim',
      date: DateTime(2026, 11, 11),
      addedByEmail: 'rahim@bhromon.fun',
    );

    final transfer = TransferItem(
      id: 'tr1',
      tourId: 't_money',
      fromId: 'rahim@bhromon.fun',
      fromName: 'Rahim',
      toId: 'karim@bhromon.fun',
      toName: 'Karim',
      amountPaisa: 50000,
      date: DateTime(2026, 11, 12),
      addedByEmail: 'rahim@bhromon.fun',
    );

    final data = TourExportData(
      group: group,
      exportedAt: DateTime.now(),
      members: const [],
      notices: const [],
      checkpoints: const [],
      checklist: const [],
      expenses: [expense],
      deposits: const [],
      transfers: [transfer],
      vehicles: const [],
      vehicleSeats: const {},
      coachSeats: const [],
      hotelRooms: const [],
      safetyAlerts: const [],
      posts: const [],
      comments: const {},
      stories: const [],
      highlights: const [],
    );

    final images = TourExportImages(
        client: MockClient((_) async => http.Response('', 404)));

    final bytes = await buildTourPdf(
      data: data,
      images: images,
      labels: _bnLabels(),
      compress: false,
    );

    final extracted = BanglaPdfExtractor.extract(bytes).text;
    expect(extracted, contains('Rahim — Karim'));
    expect(extracted, contains('খাবার'));
    // Ensure no arrow tofu symbol exists in transfers
    expect(extracted.contains('→'), isFalse);
  });
}
