import 'package:equatable/equatable.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/errors/failures.dart';

sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthOtpSent extends AuthState {
  final String verificationId;
  const AuthOtpSent(this.verificationId);

  @override
  List<Object?> get props => [verificationId];
}

class Authenticated extends AuthState {
  final ExplorerProfile profile;
  const Authenticated(this.profile);

  @override
  List<Object?> get props => [profile];
}

class Unauthenticated extends AuthState {
  const Unauthenticated();
}

class AuthError extends AuthState {
  /// Technical detail for the logs. The sign-in screen does not show it.
  final String message;

  /// Why sign-in failed. The sign-in screen words its message from this.
  final AuthFailureReason reason;

  const AuthError(this.message, {this.reason = AuthFailureReason.unknown});

  @override
  List<Object?> get props => [message, reason];
}
