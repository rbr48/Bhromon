import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:bhromon/core/entities/explorer_profile.dart';
import 'package:bhromon/core/errors/failures.dart';
import 'package:bhromon/core/value_objects/explorer_score.dart';
import 'package:bhromon/core/value_objects/trust_tier.dart';
import 'package:bhromon/features/auth/domain/usecases/get_current_profile_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/sign_in_email_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/sign_in_google_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/update_profile_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/verify_otp_usecase.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_state.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';

import 'auth_cubit_test.mocks.dart';

/// Counts the group calls the cubit makes, without touching Firestore.
class _FakeGroups extends TourGroupRepository {
  int syncs = 0;
  int resets = 0;
  bool failSync = false;
  bool failReset = false;

  @override
  Future<int> syncMyMemberProfile() async {
    syncs++;
    if (failSync) throw StateError('member write refused');
    return 0;
  }

  @override
  Future<void> resetSessionCaches() async {
    resets++;
    if (failReset) throw StateError('cache reset refused');
  }
}

void main() {
  final tProfile = ExplorerProfile(
    uid: 'uid-group-sync',
    displayName: 'Group Sync Explorer',
    explorerScore: const ExplorerScore(value: 250, tier: TrustTier.verified),
    tier: TrustTier.verified,
    badges: const ['verified_explorer'],
    division: 'Dhaka',
    createdAt: DateTime(2024, 3, 15),
    isPioneer: false,
    isRegionExpert: false,
    avatarUrl: 'https://example.com/avatar.jpg',
    bio: 'Group sync test profile',
    coverUrl: null,
  );
  const tEmail = 'group_sync@bhromon.app';
  const tCode = '135790';
  const tFailure = AuthFailure('Sign-in failed');

  late MockIAuthRepository repo;
  late _FakeGroups groups;

  AuthCubit buildCubit() {
    final cubit = AuthCubit(
      GetCurrentProfileUseCase(repo),
      SignInEmailUseCase(repo),
      VerifyOtpUseCase(repo),
      SignInGoogleUseCase(repo),
      SignOutUseCase(repo),
      UpdateProfileUseCase(repo),
    );
    cubit.groupRepository = () => groups;
    return cubit;
  }

  setUp(() {
    repo = MockIAuthRepository();
    groups = _FakeGroups();
  });

  group('member rows follow the profile', () {
    test('a Google sign-in syncs once and signs the person in', () async {
      when(repo.signInWithGoogle()).thenAnswer((_) async => Right(tProfile));
      final cubit = buildCubit();

      await cubit.signInWithGoogle();

      expect(cubit.state, isA<Authenticated>());
      expect(groups.syncs, 1);
      expect(groups.resets, 0);
      await cubit.close();
    });

    test('a verified code syncs once and signs the person in', () async {
      when(repo.verifyOtp(tCode)).thenAnswer((_) async => Right(tProfile));
      final cubit = buildCubit();

      await cubit.verifyOtp(tCode);

      expect(cubit.state, isA<Authenticated>());
      expect(groups.syncs, 1);
      await cubit.close();
    });

    test('a saved profile syncs once', () async {
      when(repo.updateProfile(tProfile))
          .thenAnswer((_) async => Right(tProfile));
      final cubit = buildCubit();

      await cubit.updateProfile(tProfile);

      expect(cubit.state, isA<Authenticated>());
      expect(groups.syncs, 1);
      await cubit.close();
    });

    test('sending a code does not sync, because nobody is signed in yet',
        () async {
      when(repo.signInWithEmail(tEmail))
          .thenAnswer((_) async => const Right(tEmail));
      final cubit = buildCubit();

      await cubit.signInWithEmail(tEmail);

      expect(cubit.state, isA<AuthOtpSent>());
      expect(groups.syncs, 0);
      await cubit.close();
    });

    test('a failed sign-in does not sync', () async {
      when(repo.signInWithGoogle())
          .thenAnswer((_) async => const Left(tFailure));
      final cubit = buildCubit();

      await cubit.signInWithGoogle();

      expect(cubit.state, isA<AuthError>());
      expect(groups.syncs, 0);
      await cubit.close();
    });

    test('a failed member write is logged and never blocks the sign-in',
        () async {
      groups.failSync = true;
      when(repo.signInWithGoogle()).thenAnswer((_) async => Right(tProfile));
      final cubit = buildCubit();

      await cubit.signInWithGoogle();
      await pumpEventQueue();

      expect(cubit.state, isA<Authenticated>());
      expect(groups.syncs, 1);
      await cubit.close();
    });
  });

  group('a saved session syncs the member rows at start', () {
    test('starting with a saved profile syncs once and signs the person in',
        () async {
      when(repo.getCurrentProfile()).thenAnswer((_) async => Right(tProfile));
      final cubit = buildCubit();

      await cubit.checkAuthStatus();

      expect(cubit.state, isA<Authenticated>());
      expect(groups.syncs, 1);
      await cubit.close();
    });

    test('starting with no saved session does not sync', () async {
      when(repo.getCurrentProfile()).thenAnswer((_) async => const Right(null));
      final cubit = buildCubit();

      await cubit.checkAuthStatus();

      expect(cubit.state, isA<Unauthenticated>());
      expect(groups.syncs, 0);
      await cubit.close();
    });

    test('a failed start does not sync', () async {
      when(repo.getCurrentProfile())
          .thenAnswer((_) async => const Left(tFailure));
      final cubit = buildCubit();

      await cubit.checkAuthStatus();

      expect(cubit.state, isA<Unauthenticated>());
      expect(groups.syncs, 0);
      await cubit.close();
    });

    test('a failed member write at start is logged and the session still opens',
        () async {
      groups.failSync = true;
      when(repo.getCurrentProfile()).thenAnswer((_) async => Right(tProfile));
      final cubit = buildCubit();

      await cubit.checkAuthStatus();
      await pumpEventQueue();

      expect(cubit.state, isA<Authenticated>());
      expect(groups.syncs, 1);
      await cubit.close();
    });
  });

  group('sign-out resets the group caches', () {
    test('a sign-out resets once and signs the person out', () async {
      when(repo.signOut()).thenAnswer((_) async => const Right(unit));
      final cubit = buildCubit();

      await cubit.signOut();
      await pumpEventQueue();

      expect(cubit.state, isA<Unauthenticated>());
      expect(groups.resets, 1);
      expect(groups.syncs, 0);
      await cubit.close();
    });

    test('a failed sign-out does not reset the caches', () async {
      when(repo.signOut()).thenAnswer((_) async => const Left(tFailure));
      final cubit = buildCubit();

      await cubit.signOut();

      expect(cubit.state, isA<AuthError>());
      expect(groups.resets, 0);
      await cubit.close();
    });

    test('a failed reset is logged and the person still signs out', () async {
      groups.failReset = true;
      when(repo.signOut()).thenAnswer((_) async => const Right(unit));
      final cubit = buildCubit();

      await cubit.signOut();
      await pumpEventQueue();

      expect(cubit.state, isA<Unauthenticated>());
      expect(groups.resets, 1);
      await cubit.close();
    });
  });
}
