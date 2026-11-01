sealed class Failure {
  final String message;
  const Failure(this.message);
}

final class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

final class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

final class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

/// Why a sign-in failed. On the sign-in screen the message is replaced by text
/// for this reason. The failure's message is technical and is for the logs.
enum AuthFailureReason {
  unknown,
  cancelled,
  network,
  googlePlayServices,
  popupBlocked,
}

final class AuthFailure extends Failure {
  final AuthFailureReason reason;
  const AuthFailure(super.message, {this.reason = AuthFailureReason.unknown});
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

final class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}

final class LocationFailure extends Failure {
  const LocationFailure(super.message);
}

final class NotFoundFailure extends Failure {
  final String resourceId;
  const NotFoundFailure(super.message, {required this.resourceId});
}

final class ConflictFailure extends Failure {
  final Map<String, dynamic> localVersion;
  final Map<String, dynamic> serverVersion;
  const ConflictFailure(super.message,
      {required this.localVersion, required this.serverVersion});
}

extension FailureMessage on Failure {
  String toUserMessage() => switch (this) {
        NetworkFailure() => 'No internet. Changes saved offline.',
        CacheFailure() => 'Could not load saved data. Restart the app.',
        AuthFailure() => 'Session expired. Please sign in again.',
        ValidationFailure() => message,
        PermissionFailure() => 'You need a higher trust level to do this.',
        ConflictFailure() =>
          'Your changes conflict with a newer version. Please review.',
        NotFoundFailure() => 'This content no longer exists.',
        ServerFailure() => message,
        LocationFailure() => message,
      };
}
