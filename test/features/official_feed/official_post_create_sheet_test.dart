import 'package:bhromon/features/official_feed/data/official_feed_repository.dart';
import 'package:bhromon/features/official_feed/presentation/official_post_create_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePublishRepository extends OfficialFeedRepository {
  List<int>? lastFileBytes;
  String? lastFileName;
  String? lastCaption;

  @override
  Future<Map<String, dynamic>> publishOfficialPost({
    required List<int> fileBytes,
    required String fileName,
    String caption = '',
    int? durationSeconds,
    List<int>? coverBytes,
    String? coverName,
    required String idToken,
    String? baseUrl,
  }) async {
    lastFileBytes = fileBytes;
    lastFileName = fileName;
    lastCaption = caption;
    return {'status': 'success', 'id': 'test-1'};
  }
}

void main() {
  Widget buildApp(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  testWidgets('renders video and photo options', (tester) async {
    final repo = _FakePublishRepository();
    await tester
        .pumpWidget(buildApp(OfficialPostCreateSheet(repository: repo)));

    expect(find.text('অফিসিয়াল পোস্ট পাবলিশ করুন'), findsOneWidget);
    expect(find.text('রিল ভিডিও'), findsOneWidget);
    expect(find.text('ছবি / ব্যানার'), findsOneWidget);
    expect(find.text('পাবলিশ করুন'), findsOneWidget);

    // Switch to photo mode
    await tester.tap(find.text('ছবি / ব্যানার'));
    await tester.pumpAndSettle();

    expect(find.text('ছবি নির্বাচন করুন (৯:১৬ রেশিও সেরা)'), findsOneWidget);
  });

  testWidgets(
      'shows validation message when publishing without selecting media',
      (tester) async {
    final repo = _FakePublishRepository();
    await tester
        .pumpWidget(buildApp(OfficialPostCreateSheet(repository: repo)));

    await tester.tap(find.text('পাবলিশ করুন'));
    await tester.pumpAndSettle();

    expect(find.text('অনুগ্রহ করে একটি ছবি বা ভিডিও সিলেক্ট করুন'),
        findsOneWidget);
  });
}
