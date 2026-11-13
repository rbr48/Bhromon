import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_module_posts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockTourRepo extends TourGroupRepository {
  _MockTourRepo({this.posts = const []});

  final List<StudyPost> posts;
  final List<String> addedTitles = [];

  @override
  String get currentEmail => 'student@test.com';

  @override
  Future<TourRole?> myRole(String tourId) async => TourRole.admin;

  @override
  Stream<List<StudyPost>> watchStudyPosts(
    String tourId,
    String subjectId,
    StudyModuleKey moduleKey,
  ) =>
      Stream.value(posts);

  @override
  Future<String> addStudyPost(
    String tourId,
    String subjectId,
    StudyModuleKey moduleKey, {
    required String text,
    String? title,
    String? url,
    bool shown = true,
  }) async {
    addedTitles.add(title ?? '');
    return 'new-post-id';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleSubject = StudySubject(
    id: 'sub-poe',
    title: 'Principles of Economics (POE)',
    code: '103',
    bookId: 'ah9qgOp1e7uA2qcV6a7B',
  );

  const sampleSettings = StudyModuleSettings(
    key: StudyModuleKey.charts,
    name: 'চার্ট ও গ্রাফ',
    enabled: true,
    postPolicy: StudyPostPolicy.members,
  );

  Widget createWidget({required TourGroupRepository repo, List<StudyPost> posts = const []}) {
    return MaterialApp(
      locale: const Locale('bn'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: StudyModulePostsScreen(
        tourId: 'tour-123',
        subject: sampleSubject,
        moduleKey: StudyModuleKey.charts,
        settings: sampleSettings,
        repository: repo,
      ),
    );
  }

  testWidgets('StudyModulePostsScreen shows Quick Atlas Banner for POE subject charts module', (tester) async {
    final repo = _MockTourRepo();
    await tester.pumpWidget(createWidget(repo: repo));
    await tester.pumpAndSettle();

    // Banner card exists
    expect(find.text('ডাইনামিক ভেক্টর গ্রাফ অ্যাটলাস (৯৫টি চার্ট)'), findsOneWidget);
    expect(find.text('ব্রাউজ করুন'), findsOneWidget);
    expect(find.text('অ্যাটলাস থেকে প্রকাশ'), findsOneWidget);

    // App bar actions for Atlas
    expect(find.byIcon(Icons.auto_graph_rounded), findsWidgets);
    expect(find.byIcon(Icons.publish_rounded), findsOneWidget);
  });

  testWidgets('StudyModulePostsScreen empty state displays Atlas banner with friendly guidance', (tester) async {
    final repo = _MockTourRepo(posts: []);
    await tester.pumpWidget(createWidget(repo: repo));
    await tester.pumpAndSettle();

    expect(find.text('ডাইনামিক ভেক্টর গ্রাফ অ্যাটলাস (৯৫টি চার্ট)'), findsOneWidget);
    expect(
      find.text('এখনো কোনো চার্ট প্রকাশিত হয়নি। উপরের বোতাম চেপে অ্যাটলাস থেকে চার্ট প্রকাশ করুন।'),
      findsOneWidget,
    );
  });
}
