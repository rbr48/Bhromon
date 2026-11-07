import 'dart:async';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/instafeed/cross_group_share_sheet.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/instafeed/instafeed_share_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockTourGroupRepo extends TourGroupRepository {
  final StreamController<List<TourGroup>> _groupsController =
      StreamController<List<TourGroup>>.broadcast();

  List<TourGroup> groups = [];

  void emitGroups(List<TourGroup> list) {
    groups = list;
    _groupsController.add(list);
  }

  @override
  Stream<List<TourGroup>> watchMyGroups() async* {
    yield groups;
    yield* _groupsController.stream;
  }

  @override
  String get currentEmail => 'traveler@bhromon.fun';

  @override
  String get currentDisplayName => 'Traveler';

  @override
  String? get currentPhotoUrl => null;

  void dispose() {
    _groupsController.close();
  }
}

Widget _testApp(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}

void main() {
  late _MockTourGroupRepo repo;
  final now = DateTime(2026, 11, 7, 12, 0);

  final samplePost = TourPostItem(
    id: 'post_101',
    tourId: 'tour_cox',
    authorEmail: 'author@bhromon.fun',
    authorName: 'Auntie Rina',
    caption: 'Sunset at Inani beach',
    images: const ['https://media.bhromon.fun/media/tour_cox/posts/inani.jpg'],
    createdAt: now,
  );

  final group1 = TourGroup(
    id: 'tour_cox',
    name: 'Cox\'s Bazar Trip',
    ownerEmail: 'traveler@bhromon.fun',
    inviteCode: 'COX12345',
    startDate: now,
    endDate: now.add(const Duration(days: 3)),
    createdAt: now,
  );

  final group2 = TourGroup(
    id: 'tour_family',
    name: 'Izzhan Family Circle',
    ownerEmail: 'traveler@bhromon.fun',
    inviteCode: 'FAM12345',
    startDate: now,
    endDate: now.add(const Duration(days: 3)),
    createdAt: now,
    kind: GroupKind.family,
  );

  setUp(() {
    repo = _MockTourGroupRepo();
  });

  tearDown(() {
    repo.dispose();
  });

  testWidgets('InstafeedShareSheet displays Share to another group option',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        InstafeedShareSheet(
          repository: repo,
          tourId: 'tour_cox',
          post: samplePost,
          group: group1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Share to another group'), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz_rounded), findsOneWidget);
  });

  testWidgets(
      'CrossGroupShareSheet displays empty state when no other groups exist',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        CrossGroupShareSheet(
          repository: repo,
          sourceTourId: 'tour_cox',
          sourceTourName: 'Cox\'s Bazar Trip',
          post: samplePost,
        ),
      ),
    );

    // Emit only the source tour
    repo.emitGroups([group1]);
    await tester.pumpAndSettle();

    expect(find.text('Share to Group'), findsOneWidget);
    expect(find.text('You do not belong to any other groups'), findsOneWidget);
    expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
  });

  testWidgets(
      'CrossGroupShareSheet filters out source group and lets user select target group',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        CrossGroupShareSheet(
          repository: repo,
          sourceTourId: 'tour_cox',
          sourceTourName: 'Cox\'s Bazar Trip',
          post: samplePost,
        ),
      ),
    );

    // Emit source group + another group
    repo.emitGroups([group1, group2]);
    await tester.pumpAndSettle();

    // Source group should be filtered out
    expect(find.text('Cox\'s Bazar Trip'), findsNothing);
    // Other group should be listed
    expect(find.text('Izzhan Family Circle'), findsOneWidget);

    // Tap target group
    await tester.tap(find.text('Izzhan Family Circle'));
    await tester.pumpAndSettle();

    // Verify share options view
    expect(find.text('Moments Feed'), findsOneWidget);
    expect(find.text('Repost Now'), findsOneWidget);
    expect(find.text('Group Chat Channel'), findsOneWidget);
    expect(find.text('Sunset at Inani beach'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
  });
}
