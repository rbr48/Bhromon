import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bhromon/core/entities/explorer_profile.dart';
import 'package:bhromon/core/value_objects/explorer_score.dart';
import 'package:bhromon/core/value_objects/trust_tier.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_state.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/join_group_screen.dart';

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTourGroupRepo extends TourGroupRepository {
  final Exception? errorToThrow;
  String? lastJoinedCode;

  _FakeTourGroupRepo({this.errorToThrow});

  @override
  String get currentEmail => 'traveler@bhromon.fun';

  @override
  Future<TourGroup> joinGroupWithCode(String code) async {
    lastJoinedCode = code;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return TourGroup(
      id: 'test-tour-id',
      name: 'Sajek Adventure 2026',
      description: 'Fun trip',
      destination: 'Sajek',
      startDate: DateTime(2026, 12, 1),
      endDate: DateTime(2026, 12, 5),
      tourType: TourType.nature,
      originCity: 'Dhaka',
      ownerEmail: 'owner@bhromon.fun',
      inviteCode: code,
      createdAt: DateTime(2026, 11, 1),
    );
  }
}

Widget _wrapScreen({
  required Widget child,
  required AuthCubit authCubit,
  Locale locale = const Locale('bn'),
}) {
  return BlocProvider<AuthCubit>.value(
    value: authCubit,
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('bn'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    ),
  );
}

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('bhromon_join_test').path);
  });

  final testProfile = ExplorerProfile(
    uid: 'user-123',
    displayName: 'Shohag Rana',
    explorerScore: const ExplorerScore(value: 300, tier: TrustTier.verified),
    tier: TrustTier.verified,
    badges: const ['verified'],
    division: 'Dhaka',
    createdAt: DateTime(2024, 1, 1),
    isPioneer: false,
    isRegionExpert: false,
    avatarUrl: null,
    bio: '',
    coverUrl: null,
  );

  testWidgets(
      'JoinGroupScreen renders invitation details and sign in button when unauthenticated',
      (tester) async {
    final fakeRepo = _FakeTourGroupRepo();
    final authCubit = _FakeAuthCubit(const Unauthenticated());

    await tester.pumpWidget(
      _wrapScreen(
        child: JoinGroupScreen(
          inviteCode: '3K7MNP9X',
          repository: fakeRepo,
        ),
        authCubit: authCubit,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bhromon'), findsOneWidget);
    expect(find.text('3K7MNP9X'), findsOneWidget);
    expect(find.text('গ্রুপে আমন্ত্রণ'), findsOneWidget);
    expect(find.text('সাইন-ইন করে যোগ দিন'), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    expect(find.byIcon(Icons.link_rounded), findsOneWidget);
  });

  testWidgets(
      'JoinGroupScreen shows current account and allows joining when authenticated',
      (tester) async {
    final fakeRepo = _FakeTourGroupRepo();
    final authCubit = _FakeAuthCubit(Authenticated(testProfile));

    await tester.pumpWidget(
      _wrapScreen(
        child: JoinGroupScreen(
          inviteCode: '3K7MNP9X',
          repository: fakeRepo,
        ),
        authCubit: authCubit,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3K7MNP9X'), findsOneWidget);
    expect(find.text('আমন্ত্রণ গ্রহণ করে যোগ দিন'), findsOneWidget);
    expect(find.textContaining('traveler@bhromon.fun'), findsOneWidget);

    // Tap Join
    await tester.tap(find.text('আমন্ত্রণ গ্রহণ করে যোগ দিন'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 200));

    expect(fakeRepo.lastJoinedCode, equals('3K7MNP9X'));
  });

  testWidgets(
      'JoinGroupScreen displays English translations properly when locale is English',
      (tester) async {
    final fakeRepo = _FakeTourGroupRepo();
    final authCubit = _FakeAuthCubit(Authenticated(testProfile));

    await tester.pumpWidget(
      _wrapScreen(
        locale: const Locale('en'),
        child: JoinGroupScreen(
          inviteCode: '3K7MNP9X',
          repository: fakeRepo,
        ),
        authCubit: authCubit,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Group Invitation'), findsOneWidget);
    expect(find.text('Accept Invitation & Join'), findsOneWidget);
    expect(find.text('Signed in: traveler@bhromon.fun'), findsOneWidget);
    expect(find.text('Go to Group Hub'), findsOneWidget);
  });

  testWidgets(
      'JoinGroupScreen displays error message when joinGroupWithCode fails',
      (tester) async {
    final fakeRepo = _FakeTourGroupRepo(
      errorToThrow: Exception('The group is already full'),
    );
    final authCubit = _FakeAuthCubit(Authenticated(testProfile));

    await tester.pumpWidget(
      _wrapScreen(
        child: JoinGroupScreen(
          inviteCode: '3K7MNP9X',
          repository: fakeRepo,
        ),
        authCubit: authCubit,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('আমন্ত্রণ গ্রহণ করে যোগ দিন'));
    await tester.pump();

    expect(find.textContaining('The group is already full'), findsOneWidget);
  });
}
