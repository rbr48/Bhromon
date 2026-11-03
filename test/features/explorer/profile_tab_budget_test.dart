import 'dart:async';

import 'package:bhromon/app/di/injection.dart';
import 'package:bhromon/core/entities/explorer_profile.dart';
import 'package:bhromon/core/errors/failures.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/utils/shared_latest_stream.dart';
import 'package:bhromon/core/value_objects/explorer_score.dart';
import 'package:bhromon/core/value_objects/trust_tier.dart';
import 'package:bhromon/features/auth/domain/usecases/get_current_profile_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/sign_in_email_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/sign_in_google_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/update_profile_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/verify_otp_usecase.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:bhromon/features/explorer/domain/repositories/i_explorer_repository.dart';
import 'package:bhromon/features/explorer/domain/usecases/get_explorer_profile_usecase.dart';
import 'package:bhromon/features/explorer/presentation/pages/explorer_profile_screen.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';

import '../auth/presentation/cubit/auth_cubit_test.mocks.dart';

/// Only the profile lookup is used, and the test replaces that use case.
class _NoExplorerRepository implements IExplorerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGetProfile extends GetExplorerProfileUseCase {
  _FakeGetProfile(this._profile) : super(_NoExplorerRepository());

  final ExplorerProfile _profile;

  @override
  Future<Either<Failure, ExplorerProfile>> call(String params) async =>
      Right(_profile);
}

/// A groups list that behaves like the real one: one shared upstream, the latest value
/// replayed to each new listener, and every call to [watchMyGroups] counted.
class _CountingGroups extends TourGroupRepository {
  _CountingGroups(this.groups);

  final List<TourGroup> groups;
  int watchCalls = 0;
  int upstreamOpens = 0;

  final StreamController<List<TourGroup>> _source =
      StreamController<List<TourGroup>>.broadcast();

  late final SharedLatestStream<List<TourGroup>> _shared =
      SharedLatestStream<List<TourGroup>>(
    _source.stream,
    onUpstreamStart: () {
      upstreamOpens++;
      // The membership answer arrives after the listener is attached, as it does live.
      Future<void>.microtask(() => _source.add(groups));
    },
  );

  @override
  String get currentEmail => 'me@bhromon.fun';

  @override
  String get currentUid => 'uid-budget-me';

  @override
  String get currentDisplayName => 'Budget Explorer';

  @override
  String? get currentPhotoUrl => null;

  @override
  Stream<List<TourGroup>> watchMyGroups() {
    watchCalls++;
    return _shared.stream;
  }

  Future<void> close() => _source.close();
}

final _profile = ExplorerProfile(
  uid: 'uid-budget-me',
  displayName: 'Budget Explorer',
  explorerScore: const ExplorerScore(value: 250, tier: TrustTier.verified),
  tier: TrustTier.verified,
  badges: const ['verified_explorer'],
  division: 'Dhaka',
  createdAt: DateTime(2024, 3, 15),
  isPioneer: false,
  isRegionExpert: false,
  avatarUrl: 'https://example.com/avatar.jpg',
  bio: 'Budget test profile',
  coverUrl: null,
);

final _trip = TourGroup(
  id: 'trip_budget',
  name: 'Sajek budget batch',
  ownerEmail: 'me@bhromon.fun',
  inviteCode: 'BUDGET26',
  destination: 'Sajek',
  originCity: 'Dhaka',
  startDate: DateTime(2026, 11, 1),
  endDate: DateTime(2026, 11, 4),
  tourType: TourType.hill,
  modules: const TourModules(),
  createdAt: DateTime(2026, 10, 1),
);

Future<AuthCubit> _signedInCubit() async {
  final repo = MockIAuthRepository();
  when(repo.getCurrentProfile()).thenAnswer((_) async => Right(_profile));
  final cubit = AuthCubit(
    GetCurrentProfileUseCase(repo),
    SignInEmailUseCase(repo),
    VerifyOtpUseCase(repo),
    SignInGoogleUseCase(repo),
    SignOutUseCase(repo),
    UpdateProfileUseCase(repo),
  );
  await cubit.checkAuthStatus();
  return cubit;
}

void main() {
  setUp(() {
    getIt.registerSingleton<GetExplorerProfileUseCase>(
        _FakeGetProfile(_profile));
  });

  tearDown(() async {
    await getIt.unregister<GetExplorerProfileUseCase>();
  });

  testWidgets(
      'twenty tab taps start no new groups stream, and the groups never empty',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _CountingGroups([_trip]);
    addTearDown(repo.close);
    final auth = await _signedInCubit();
    addTearDown(auth.close);

    // The profile reads the router (its back button checks whether it can pop).
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => BlocProvider<AuthCubit>.value(
            value: auth,
            child: ExplorerProfileScreen(
              uid: _profile.uid,
              repository: repo,
              readProfileData: (uid) async => null,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('bn')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        routerConfig: router,
      ),
    );
    // The profile and the groups load over a few frames. The screen has animations, so
    // the frames are pumped by hand rather than settled.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text(_trip.name), findsWidgets,
        reason: 'the groups list is the default tab');
    final baseline = (repo.watchCalls, repo.upstreamOpens);
    expect(baseline, (1, 1), reason: 'one stream for the screen, one upstream');

    const tabs = ['গ্রুপসমূহ', 'গেমিং', 'স্মৃতি', 'সেটিংস'];
    for (var tap = 0; tap < 20; tap++) {
      final label = tabs[tap % tabs.length];
      await tester.tap(find.text(label).first);
      await tester.pump();
      if (label == tabs.first) {
        expect(find.text(_trip.name), findsWidgets,
            reason:
                'tap $tap: the groups list emptied while it was shown again');
      }
    }

    expect((repo.watchCalls, repo.upstreamOpens), baseline,
        reason: 'twenty tab taps must not start a new groups stream');
  });
}
