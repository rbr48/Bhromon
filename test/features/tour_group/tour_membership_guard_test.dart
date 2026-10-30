import 'dart:async';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/tour_membership_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _MembershipRepository extends TourGroupRepository {
  final membership = StreamController<bool>.broadcast();
  final cleared = <String>[];

  @override
  Stream<bool> watchIsMember(String tourId) => membership.stream;

  @override
  Future<void> clearLocalTourData(String tourId) async {
    cleared.add(tourId);
  }
}

Future<void> _pumpTour(WidgetTester tester, _MembershipRepository repo) async {
  final router = GoRouter(
    initialLocation: '/group/tour_a/feed',
    routes: [
      GoRoute(
        path: '/group/:tourId/feed',
        builder: (context, state) => TourMembershipGuard(
          tourId: state.pathParameters['tourId']!,
          repository: repo,
          child: const Text('feed page'),
        ),
      ),
      GoRoute(
        path: '/group-hub',
        builder: (context, state) => const Scaffold(body: Text('hub page')),
      ),
    ],
  );

  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a tour screen stays open while the membership is confirmed',
      (tester) async {
    final repo = _MembershipRepository();
    addTearDown(repo.membership.close);
    await _pumpTour(tester, repo);

    repo.membership.add(true);
    await tester.pumpAndSettle();

    expect(find.text('feed page'), findsOneWidget);
    expect(repo.cleared, isEmpty);
  });

  testWidgets('a removed member goes to the hub and the tour is cleared',
      (tester) async {
    final repo = _MembershipRepository();
    addTearDown(repo.membership.close);
    await _pumpTour(tester, repo);

    repo.membership.add(true);
    await tester.pumpAndSettle();
    repo.membership.add(false);
    await tester.pumpAndSettle();

    expect(find.text('hub page'), findsOneWidget);
    expect(find.text('feed page'), findsNothing);
    expect(repo.cleared, ['tour_a']);
    expect(find.text('You are no longer a member of this tour group.'),
        findsOneWidget);
  });

  testWidgets('a membership answer never confirmed does not close the tour',
      (tester) async {
    final repo = _MembershipRepository();
    addTearDown(repo.membership.close);
    await _pumpTour(tester, repo);

    repo.membership.add(false);
    await tester.pumpAndSettle();

    expect(find.text('feed page'), findsOneWidget);
    expect(repo.cleared, isEmpty);
  });
}
