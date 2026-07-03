/// DI environment identifiers used with injectable's environment-aware
/// registration. Pass these to [configureDependencies] in main.dart.
abstract class Env {
  /// Full Firebase connectivity — production mode.
  static const prod = 'prod';

  /// Firebase unavailable (e.g. blocked by adblocker or no network on first boot).
  /// Mock repositories are registered for IAuthRepository / ITripLogRepository.
  static const offline = 'offline';

  /// Automated tests — in-memory mocks for all external dependencies.
  static const test = 'test';
}
