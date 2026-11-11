import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bhromon/core/utils/app_logger.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:injectable/injectable.dart';
import '../../domain/usecases/get_current_profile_usecase.dart';
import '../../domain/usecases/sign_in_email_usecase.dart';
import '../../domain/usecases/verify_otp_usecase.dart';
import '../../domain/usecases/sign_in_google_usecase.dart';
import '../../domain/usecases/sign_out_usecase.dart';
import '../../domain/usecases/update_profile_usecase.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/errors/failures.dart';
import 'auth_state.dart';

/// One instance app-wide: the router's refresh stream and the widget tree
/// must observe the same cubit (as a factory, the router got its own
/// instance that never emitted, so redirects missed sign-in/sign-out).
@lazySingleton
class AuthCubit extends Cubit<AuthState> {
  final GetCurrentProfileUseCase _getCurrentProfile;
  final SignInEmailUseCase _signInEmail;
  final VerifyOtpUseCase _verifyOtp;
  final SignInGoogleUseCase _signInGoogle;
  final SignOutUseCase _signOut;
  final UpdateProfileUseCase _updateProfile;

  /// The group repository that the cubit syncs member rows with and resets at sign-out.
  /// A field rather than a constructor parameter, so injection is unchanged. Tests
  /// replace it.
  @visibleForTesting
  TourGroupRepository Function() groupRepository = () => TourGroupRepository();

  AuthCubit(
    this._getCurrentProfile,
    this._signInEmail,
    this._verifyOtp,
    this._signInGoogle,
    this._signOut,
    this._updateProfile,
  ) : super(const AuthInitial());

  Future<void> checkAuthStatus() async {
    emit(const AuthLoading());
    final result = await _getCurrentProfile();
    result.fold(
      (failure) => emit(const Unauthenticated()),
      (profile) {
        if (profile != null) {
          // A saved session starts here, so the member rows are brought up to date
          // with the saved name and photo. A row written before the photo existed, or
          // a save that failed offline, heals at the next start.
          _syncGroupMembership();
          emit(Authenticated(profile));
        } else {
          emit(const Unauthenticated());
        }
      },
    );
  }

  /// The state after a failed call. Backing out of the Google account window
  /// is the user's own choice, so it returns to the sign-in form with no
  /// message.
  AuthState _failedState(Failure failure) {
    final reason =
        failure is AuthFailure ? failure.reason : AuthFailureReason.unknown;
    if (reason == AuthFailureReason.cancelled) return const Unauthenticated();
    return AuthError(failure.message, reason: reason);
  }

  /// Keeps the signed-in person's group member rows in step with their profile. A
  /// failure is logged; it never blocks sign-in or the profile save.
  void _syncGroupMembership() {
    unawaited(groupRepository()
        .syncMyMemberProfile()
        .catchError((Object e, StackTrace st) {
      logWarning('[AuthCubit] group member sync failed', e, st);
      return 0;
    }));
  }

  Future<void> signInWithEmail(String email) async {
    emit(const AuthLoading());
    final result = await _signInEmail(email);
    result.fold(
      (failure) => emit(_failedState(failure)),
      (_) => emit(AuthOtpSent(email)),
    );
  }

  Future<void> verifyOtp(String smsCode) async {
    emit(const AuthLoading());
    final result = await _verifyOtp(smsCode);
    result.fold(
      (failure) => emit(_failedState(failure)),
      (profile) {
        _syncGroupMembership();
        emit(Authenticated(profile));
      },
    );
  }

  Future<void> signInWithGoogle() async {
    emit(const AuthLoading());
    final result = await _signInGoogle();
    result.fold(
      (failure) => emit(_failedState(failure)),
      (profile) {
        _syncGroupMembership();
        emit(Authenticated(profile));
      },
    );
  }

  Future<void> signOut() async {
    emit(const AuthLoading());
    final result = await _signOut();
    result.fold(
      (failure) => emit(_failedState(failure)),
      (_) {
        unawaited(groupRepository().resetSessionCaches().catchError(
            (Object e, StackTrace st) =>
                logWarning('[AuthCubit] group cache reset failed', e, st)));
        emit(const Unauthenticated());
      },
    );
  }

  /// Saves the profile and returns whether the server accepted it. When the server
  /// refuses the save, the signed-in state goes back to the profile from before the
  /// edit, so the rest of the app keeps the signed-in person's uid.
  Future<bool> updateProfile(ExplorerProfile profile) async {
    final before = state;
    emit(const AuthLoading());
    final result = await _updateProfile(profile);
    return result.fold(
      (failure) {
        if (before is Authenticated) {
          emit(Authenticated(before.profile));
        } else {
          emit(_failedState(failure));
        }
        return false;
      },
      (updatedProfile) {
        _syncGroupMembership();
        emit(Authenticated(updatedProfile));
        return true;
      },
    );
  }
}
