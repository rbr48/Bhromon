import 'dart:convert';
import 'dart:typed_data';

import 'package:bhromon/features/tour_group/data/tour_export_images.dart';
import 'package:bhromon/features/tour_group/data/tour_export_pdf.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_export_data.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

TourPdfLabels _labels() => TourPdfLabels(
      text: (key, {args}) => key,
      number: (n) => '$n',
      date: (d) => '${d.year}-${d.month}-${d.day}',
      dateTime: (d) => '${d.year}-${d.month}-${d.day} ${d.hour}:${d.minute}',
    );

TourGroup _group() => TourGroup(
      id: 't1',
      name: 'Sajek Trek',
      ownerEmail: 'owner@example.com',
      inviteCode: 'SJ8K2026',
      destination: 'Sajek',
      originCity: 'Dhaka',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 4),
      tourType: TourType.hill,
      modules: const TourModules(),
      createdAt: DateTime(2026, 10, 1),
    );

TourExportData _data({
  List<TourMember> members = const [],
  List<TourPostItem> posts = const [],
  Map<String, List<TourCommentItem>> comments = const {},
}) {
  return TourExportData(
    group: _group(),
    exportedAt: DateTime(2026, 10, 30),
    members: members,
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
    posts: posts,
    comments: comments,
    stories: const [],
    highlights: const [],
  );
}

TourExportImages _offlineImages() {
  return TourExportImages(
    client: MockClient((_) async => http.Response('', 404)),
  );
}

/// Counts the page objects in a PDF. The page tree (`/Type /Pages`) is not a page.
int _pageCount(Uint8List bytes) {
  return RegExp(r'/Type\s*/Page(?!s)').allMatches(latin1.decode(bytes)).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an empty tour still makes a PDF with a cover and contents', () async {
    final bytes = await buildTourPdf(
      data: _data(),
      images: _offlineImages(),
      labels: _labels(),
    );

    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    expect(latin1.decode(bytes.sublist(bytes.length - 16)), contains('%%EOF'));
    expect(_pageCount(bytes), greaterThanOrEqualTo(2));
  });

  test('a long member list flows onto more pages instead of being cut',
      () async {
    final members = [
      for (var i = 0; i < 150; i++)
        TourMember(
          tourId: 't1',
          email: 'member$i@example.com',
          displayName: 'Member $i',
          role: TourRole.member,
          status: TourMemberStatus.active,
          joinedAt: DateTime(2026, 10, 1),
          familyCount: 1,
        ),
    ];
    final bytes = await buildTourPdf(
      data: _data(members: members),
      images: _offlineImages(),
      labels: _labels(),
    );

    expect(_pageCount(bytes), greaterThan(3));
  });

  test('a post with a missing picture and a comment still lays out', () async {
    final post = TourPostItem.fromMap('p1', {
      'tourId': 't1',
      'authorEmail': 'rahim@example.com',
      'authorName': 'Rahim',
      'caption': 'Sunrise at Sajek 🌄',
      'images': ['https://example.com/missing.jpg'],
      'createdAt': DateTime(2026, 11, 2, 6, 30),
    });
    final comment = TourCommentItem.fromMap('c1', {
      'authorEmail': 'karim@example.com',
      'authorName': 'Karim',
      'text': 'Amazing view',
      'createdAt': DateTime(2026, 11, 2, 6, 45),
    });

    final bytes = await buildTourPdf(
      data: _data(posts: [
        post
      ], comments: {
        'p1': [comment]
      }),
      images: _offlineImages(),
      labels: _labels(),
    );

    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    expect(_pageCount(bytes), greaterThanOrEqualTo(3));
  });

  test('a picture that cannot be fetched is left out, not fatal', () async {
    final images = _offlineImages();
    const url = 'https://example.com/missing.jpg';

    await images.prefetch([url]);

    expect(images.ready(url), isNull);
  });
}
