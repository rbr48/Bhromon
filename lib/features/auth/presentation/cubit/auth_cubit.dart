import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/usecases/get_current_profile_usecase.dart';
import '../../domain/usecases/sign_in_email_usecase.dart';
import '../../domain/usecases/verify_otp_usecase.dart';
import '../../domain/usecases/sign_in_google_usecase.dart';
import '../../domain/usecases/sign_out_usecase.dart';
import '../../domain/usecases/update_profile_usecase.dart';
import '../../../../core/entities/explorer_profile.dart';
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
          emit(Authenticated(profile));
        } else {
          emit(const Unauthenticated());
        }
      },
    );
  }

  Future<void> signInWithEmail(String email) async {
    emit(const AuthLoading());
    final result = await _signInEmail(email);
    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (_) => emit(AuthOtpSent(email)),
    );
  }

  Future<void> verifyOtp(String smsCode) async {
    emit(const AuthLoading());
    final result = await _verifyOtp(smsCode);
    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (profile) => emit(Authenticated(profile)),
    );
  }

  Future<void> signInWithGoogle() async {
    emit(const AuthLoading());
    final result = await _signInGoogle();
    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (profile) => emit(Authenticated(profile)),
    );
  }

  Future<void> signOut() async {
    emit(const AuthLoading());
    final result = await _signOut();
    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (_) => emit(const Unauthenticated()),
    );
  }

  Future<void> updateProfile(ExplorerProfile profile) async {
    emit(const AuthLoading());
    final result = await _updateProfile(profile);
    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (updatedProfile) => emit(Authenticated(updatedProfile)),
    );
  }
}
