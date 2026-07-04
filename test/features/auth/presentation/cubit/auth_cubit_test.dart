import '../../../../helpers/bloc_test_helper.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:bhromon/core/entities/explorer_profile.dart';
import 'package:bhromon/core/errors/failures.dart';
import 'package:bhromon/core/value_objects/explorer_score.dart';
import 'package:bhromon/core/value_objects/trust_tier.dart';
import 'package:bhromon/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:bhromon/features/auth/domain/usecases/get_current_profile_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/sign_in_email_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/verify_otp_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/sign_in_google_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/update_profile_usecase.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_state.dart';

import 'auth_cubit_test.mocks.dart';

@GenerateMocks([IAuthRepository])
void main() {
  // ────────────────────────────────────────────────────
  // Shared fixtures
  // ────────────────────────────────────────────────────
  late MockIAuthRepository mockRepo;
  late GetCurrentProfileUseCase getCurrentProfile;
  late SignInEmailUseCase signInEmail;
  late VerifyOtpUseCase verifyOtp;
  late SignInGoogleUseCase signInGoogle;
  late SignOutUseCase signOut;
  late UpdateProfileUseCase updateProfile;

  final tProfile = ExplorerProfile(
    uid: 'uid-cubit-test',
    displayName: 'Cubit Test Explorer',
    explorerScore: const ExplorerScore(value: 250, tier: TrustTier.verified),
    tier: TrustTier.verified,
    badges: const ['verified_explorer'],
    division: 'Chittagong',
    createdAt: DateTime(2024, 3, 15),
    isPioneer: false,
    isRegionExpert: false,
    avatarUrl: 'https://example.com/avatar.jpg',
    bio: 'Cubit test profile',
    coverUrl: null,
  );

  const tEmail = 'cubit_test@bhromon.app';
  const tOtpCode = '654321';
  const tAuthError = AuthFailure('Sign-in failed');

  /// Helper: build a fresh AuthCubit from the current mock repo.
  AuthCubit buildCubit() => AuthCubit(
        getCurrentProfile,
        signInEmail,
        verifyOtp,
        signInGoogle,
        signOut,
        updateProfile,
      );

  setUp(() {
    mockRepo = MockIAuthRepository();
    getCurrentProfile = GetCurrentProfileUseCase(mockRepo);
    signInEmail = SignInEmailUseCase(mockRepo);
    verifyOtp = VerifyOtpUseCase(mockRepo);
    signInGoogle = SignInGoogleUseCase(mockRepo);
    signOut = SignOutUseCase(mockRepo);
    updateProfile = UpdateProfileUseCase(mockRepo);
  });

  // ────────────────────────────────────────────────────
  // checkAuthStatus
  // ────────────────────────────────────────────────────
  group('checkAuthStatus', () {
    blocTest<AuthCubit, AuthState>(
      'emits [AuthLoading, Authenticated] when current profile is found',
      build: () {
        when(mockRepo.getCurrentProfile())
            .thenAnswer((_) async => Right(tProfile));
        return buildCubit();
      },
      act: (cubit) => cubit.checkAuthStatus(),
      expect: () => [const AuthLoading(), Authenticated(tProfile)],
      verify: (_) => verify(mockRepo.getCurrentProfile()).called(1),
    );

    blocTest<AuthCubit, AuthState>(
      'emits [AuthLoading, Unauthenticated] when no profile exists (null)',
      build: () {
        when(mockRepo.getCurrentProfile())
            .thenAnswer((_) async => const Right(null));
        return buildCubit();
      },
      act: (cubit) => cubit.checkAuthStatus(),
      expect: () => [const AuthLoading(), const Unauthenticated()],
    );

    blocTest<AuthCubit, AuthState>(
      'emits [AuthLoading, Unauthenticated] when repository returns failure',
      build: () {
        when(mockRepo.getCurrentProfile())
            .thenAnswer((_) async => const Left(tAuthError));
        return buildCubit();
      },
      act: (cubit) => cubit.checkAuthStatus(),
      expect: () => [const AuthLoading(), const Unauthenticated()],
    );
  });

  // ────────────────────────────────────────────────────
  // signInWithEmail
  // ────────────────────────────────────────────────────
  group('signInWithEmail', () {
    blocTest<AuthCubit, AuthState>(
      'emits [AuthLoading, AuthOtpSent(email)] on success',
      build: () {
        when(mockRepo.signInWithEmail(tEmail))
            .thenAnswer((_) async => const Right('verif-id-123'));
        return buildCubit();
      },
      act: (cubit) => cubit.signInWithEmail(tEmail),
      // The cubit passes the email as the verificationId (see cubit source)
      expect: () => [const AuthLoading(), const AuthOtpSent(tEmail)],
      verify: (_) => verify(mockRepo.signInWithEmail(tEmail)).called(1),
    );

    blocTest<AuthCubit, AuthState>(
      'emits [AuthLoading, AuthError] on failure',
      build: () {
        when(mockRepo.signInWithEmail(tEmail))
            .thenAnswer((_) async => const Left(tAuthError));
        return buildCubit();
      },
      act: (cubit) => cubit.signInWithEmail(tEmail),
      expect: () => [
        const AuthLoading(),
        AuthError(tAuthError.message),
      ],
    );
  });

  // ────────────────────────────────────────────────────
  // verifyOtp
  // ────────────────────────────────────────────────────
  group('verifyOtp', () {
    blocTest<AuthCubit, AuthState>(
      'emits [AuthLoading, Authenticated] on successful OTP verification',
      build: () {
        when(mockRepo.verifyOtp(tOtpCode))
            .thenAnswer((_) async => Right(tProfile));
        return buildCubit();
      },
      act: (cubit) => cubit.verifyOtp(tOtpCode),
      expect: () => [const AuthLoading(), Authenticated(tProfile)],
      verify: (_) => verify(mockRepo.verifyOtp(tOtpCode)).called(1),
    );

    blocTest<AuthCubit, AuthState>(
      'emits [AuthLoading, AuthError] on OTP failure',
      build: () {
        when(mockRepo.verifyOtp(tOtpCode))
            .thenAnswer((_) async => const Left(tAuthError));
        return buildCubit();
      },
      act: (cubit) => cubit.verifyOtp(tOtpCode),
      expect: () => [
        const AuthLoading(),
        AuthError(tAuthError.message),
      ],
    );
  });

  // ────────────────────────────────────────────────────
  // signInWithGoogle
  // ────────────────────────────────────────────────────
  group('signInWithGoogle', () {
    blocTest<AuthCubit, AuthState>(
      'emits [AuthLoading, Authenticated] on successful Google sign-in',
      build: () {
        when(mockRepo.signInWithGoogle())
            .thenAnswer((_) async => Right(tProfile));
        return buildCubit();
      },
      act: (cubit) => cubit.signInWithGoogle(),
      expect: () => [const AuthLoading(), Authenticated(tProfile)],
      verify: (_) => verify(mockRepo.signInWithGoogle()).called(1),
    );

    blocTest<AuthCubit, AuthState>(
      'emits [AuthLoading, AuthError] when Google sign-in fails',
      build: () {
        when(mockRepo.signInWithGoogle())
            .thenAnswer((_) async => const Left(tAuthError));
        return buildCubit();
      },
      act: (cubit) => cubit.signInWithGoogle(),
      expect: () => [
        const AuthLoading(),
        AuthError(tAuthError.message),
      ],
    );
  });

  // ────────────────────────────────────────────────────
  // signOut
  // ────────────────────────────────────────────────────
  group('signOut', () {
    blocTest<AuthCubit, AuthState>(
      'emits [AuthLoading, Unauthenticated] on successful sign-out',
      build: () {
        when(mockRepo.signOut()).thenAnswer((_) async => const Right(unit));
        return buildCubit();
      },
      act: (cubit) => cubit.signOut(),
      expect: () => [const AuthLoading(), const Unauthenticated()],
      verify: (_) => verify(mockRepo.signOut()).called(1),
    );

    blocTest<AuthCubit, AuthState>(
      'emits [AuthLoading, AuthError] when sign-out fails',
      build: () {
        when(mockRepo.signOut())
            .thenAnswer((_) async => const Left(tAuthError));
        return buildCubit();
      },
      act: (cubit) => cubit.signOut(),
      expect: () => [
        const AuthLoading(),
        AuthError(tAuthError.message),
      ],
    );
  });

  // ────────────────────────────────────────────────────
  // updateProfile
  // ────────────────────────────────────────────────────
  group('updateProfile', () {
    blocTest<AuthCubit, AuthState>(
      'emits [AuthLoading, Authenticated(updated)] when update succeeds',
      build: () {
        final updated = tProfile.copyWith(bio: 'Updated bio');
        when(mockRepo.updateProfile(updated))
            .thenAnswer((_) async => Right(updated));
        return buildCubit();
      },
      act: (cubit) =>
          cubit.updateProfile(tProfile.copyWith(bio: 'Updated bio')),
      expect: () => [
        const AuthLoading(),
        Authenticated(tProfile.copyWith(bio: 'Updated bio')),
      ],
      verify: (_) => verify(
        mockRepo.updateProfile(tProfile.copyWith(bio: 'Updated bio')),
      ).called(1),
    );

    blocTest<AuthCubit, AuthState>(
      'emits [AuthLoading, AuthError] when update fails',
      build: () {
        when(mockRepo.updateProfile(tProfile))
            .thenAnswer((_) async => const Left(tAuthError));
        return buildCubit();
      },
      act: (cubit) => cubit.updateProfile(tProfile),
      expect: () => [
        const AuthLoading(),
        AuthError(tAuthError.message),
      ],
    );
  });
}
