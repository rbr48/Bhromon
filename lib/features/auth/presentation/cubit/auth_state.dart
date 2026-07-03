import 'package:equatable/equatable.dart';
import '../../../../core/entities/explorer_profile.dart';

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
  final String message;
  const AuthError(this.message);

  @override
  List<Object?> get props => [message];
}
