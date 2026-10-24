import 'package:connectivity_plus/connectivity_plus.dart';

/// Reports whether the device currently has any network route.
///
/// Repositories take one of these instead of calling the plugin directly so
/// tests can run without the platform channel.
typedef OnlineCheck = Future<bool> Function();

Future<bool> deviceIsOnline() async {
  final results = await Connectivity().checkConnectivity();
  return !(results.isNotEmpty && results.first == ConnectivityResult.none);
}
