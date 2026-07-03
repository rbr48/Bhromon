// ignore_for_file: inference_failure_on_function_invocation

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:bhromon/core/entities/explorer_profile.dart';
import 'package:bhromon/core/errors/failures.dart';
import 'package:bhromon/core/value_objects/explorer_score.dart';
import 'package:bhromon/core/value_objects/trust_tier.dart';
import 'package:bhromon/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:bhromon/features/auth/domain/usecases/sign_in_email_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/verify_otp_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/sign_in_google_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/get_current_profile_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/update_profile_usecase.dart';

import 'auth_usecases_test.mocks.dart';

@GenerateMocks([IAuthRepository])
void main() {
  // ────────────────────────────────────────────────────
  // Shared fixtures
  // ────────────────────────────────────────────────────
  late MockIAuthRepository mockRepo;

  /// A fully-populated ExplorerProfile reused across all test groups.
  final tProfile = ExplorerProfile(
    uid: 'uid-test-001',
    displayName: 'Test Explorer',
    explorerScore: const ExplorerScore(value: 120, tier: TrustTier.community),
    tier: TrustTier.community,
    badges: const ['first_trip'],
    division: 'Dhaka',
    createdAt: DateTime(2024, 1, 1),
    isPioneer: false,
    isRegionExpert: false,
    avatarUrl: null,
    bio: 'A test explorer',
    coverUrl: null,
  );

  const tEmail = 'explorer@bhromon.app';
  const tOtpCode = '123456';
  const tVerificationId = 'verif-abc-123';
  const tAuthFailure = AuthFailure('Authentication failed');

  setUp(() {
    mockRepo = MockIAuthRepository();
  });

  // ────────────────────────────────────────────────────
  // SignInEmailUseCase
  // ────────────────────────────────────────────────────
  group('SignInEmailUseCase', () {
    late SignInEmailUseCase useCase;

    setUp(() => useCase = SignInEmailUseCase(mockRepo));

    test('happy path: returns Right(verificationId) when sign-in succeeds',
        () async {
      when(mockRepo.signInWithEmail(tEmail))
          .thenAnswer((_) async => const Right(tVerificationId));

      final result = await useCase(tEmail);

      expect(result, const Right<Failure, String>(tVerificationId));
      verify(mockRepo.signInWithEmail(tEmail)).called(1);
      verifyNoMoreInteractions(mockRepo);
    });

    test('failure path: returns Left(AuthFailure) when sign-in fails',
        () async {
      when(mockRepo.signInWithEmail(tEmail))
          .thenAnswer((_) async => const Left(tAuthFailure));

      final result = await useCase(tEmail);

      expect(result, const Left<Failure, String>(tAuthFailure));
      verify(mockRepo.signInWithEmail(tEmail)).called(1);
    });
  });

  // ────────────────────────────────────────────────────
  // VerifyOtpUseCase
  // ────────────────────────────────────────────────────
  group('VerifyOtpUseCase', () {
    late VerifyOtpUseCase useCase;

    setUp(() => useCase = VerifyOtpUseCase(mockRepo));

    test('happy path: returns Right(ExplorerProfile) when OTP is valid',
        () async {
      when(mockRepo.verifyOtp(tOtpCode))
          .thenAnswer((_) async => Right(tProfile));

      final result = await useCase(tOtpCode);

      expect(result, Right<Failure, ExplorerProfile>(tProfile));
      verify(mockRepo.verifyOtp(tOtpCode)).called(1);
      verifyNoMoreInteractions(mockRepo);
    });

    test('failure path: returns Left(AuthFailure) when OTP is invalid',
        () async {
      when(mockRepo.verifyOtp(tOtpCode))
          .thenAnswer((_) async => const Left(tAuthFailure));

      final result = await useCase(tOtpCode);

      expect(result, const Left<Failure, ExplorerProfile>(tAuthFailure));
    });
  });

  // ────────────────────────────────────────────────────
  // SignInGoogleUseCase
  // (implements NoParamsUseCase — call() takes no arguments)
  // ────────────────────────────────────────────────────
  group('SignInGoogleUseCase', () {
    late SignInGoogleUseCase useCase;

    setUp(() => useCase = SignInGoogleUseCase(mockRepo));

    test('happy path: returns Right(ExplorerProfile) when Google sign-in succeeds',
        () async {
      when(mockRepo.signInWithGoogle())
          .thenAnswer((_) async => Right(tProfile));

      final result = await useCase();

      expect(result, Right<Failure, ExplorerProfile>(tProfile));
      verify(mockRepo.signInWithGoogle()).called(1);
      verifyNoMoreInteractions(mockRepo);
    });

    test('failure path: returns Left(AuthFailure) when Google sign-in fails',
        () async {
      when(mockRepo.signInWithGoogle())
          .thenAnswer((_) async => const Left(tAuthFailure));

      final result = await useCase();

      expect(result, const Left<Failure, ExplorerProfile>(tAuthFailure));
    });
  });

  // ────────────────────────────────────────────────────
  // SignOutUseCase
  // (implements NoParamsUseCase)
  // ────────────────────────────────────────────────────
  group('SignOutUseCase', () {
    late SignOutUseCase useCase;

    setUp(() => useCase = SignOutUseCase(mockRepo));

    test('happy path: returns Right(unit) when sign-out succeeds', () async {
      when(mockRepo.signOut())
          .thenAnswer((_) async => const Right(unit));

      final result = await useCase();

      expect(result, const Right<Failure, Unit>(unit));
      verify(mockRepo.signOut()).called(1);
      verifyNoMoreInteractions(mockRepo);
    });

    test('failure path: returns Left(AuthFailure) when sign-out fails',
        () async {
      when(mockRepo.signOut())
          .thenAnswer((_) async => const Left(tAuthFailure));

      final result = await useCase();

      expect(result, const Left<Failure, Unit>(tAuthFailure));
    });
  });

  // ────────────────────────────────────────────────────
  // GetCurrentProfileUseCase
  // (implements NoParamsUseCase)
  // ────────────────────────────────────────────────────
  group('GetCurrentProfileUseCase', () {
    late GetCurrentProfileUseCase useCase;

    setUp(() => useCase = GetCurrentProfileUseCase(mockRepo));

    test('happy path: returns Right(profile) when a logged-in user exists',
        () async {
      when(mockRepo.getCurrentProfile())
          .thenAnswer((_) async => Right(tProfile));

      final result = await useCase();

      expect(result, Right<Failure, ExplorerProfile?>(tProfile));
      verify(mockRepo.getCurrentProfile()).called(1);
      verifyNoMoreInteractions(mockRepo);
    });

    test('happy path: returns Right(null) when no user is signed in',
        () async {
      when(mockRepo.getCurrentProfile())
          .thenAnswer((_) async => const Right(null));

      final result = await useCase();

      expect(result, const Right<Failure, ExplorerProfile?>(null));
    });

    test('failure path: returns Left(AuthFailure) on repository error',
        () async {
      when(mockRepo.getCurrentProfile())
          .thenAnswer((_) async => const Left(tAuthFailure));

      final result = await useCase();

      expect(result, const Left<Failure, ExplorerProfile?>(tAuthFailure));
    });
  });

  // ────────────────────────────────────────────────────
  // UpdateProfileUseCase
  // (implements UseCase<ExplorerProfile, ExplorerProfile>)
  // ────────────────────────────────────────────────────
  group('UpdateProfileUseCase', () {
    late UpdateProfileUseCase useCase;

    setUp(() => useCase = UpdateProfileUseCase(mockRepo));

    test('happy path: returns Right(updatedProfile) when update succeeds',
        () async {
      final updatedProfile = tProfile.copyWith(bio: 'Updated bio');
      when(mockRepo.updateProfile(updatedProfile))
          .thenAnswer((_) async => Right(updatedProfile));

      final result = await useCase(updatedProfile);

      expect(result, Right<Failure, ExplorerProfile>(updatedProfile));
      verify(mockRepo.updateProfile(updatedProfile)).called(1);
      verifyNoMoreInteractions(mockRepo);
    });

    test('failure path: returns Left(AuthFailure) when update fails',
        () async {
      when(mockRepo.updateProfile(tProfile))
          .thenAnswer((_) async => const Left(tAuthFailure));

      final result = await useCase(tProfile);

      expect(result, const Left<Failure, ExplorerProfile>(tAuthFailure));
    });
  });
}
