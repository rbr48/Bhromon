import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

class PerfTracer {
  /// Wraps [operation] in a Firebase Performance trace named [name].
  /// On web, the operation runs unwrapped since firebase_performance
  /// does not support web.
  static Future<T> trace<T>(
    String name,
    Future<T> Function() operation,
  ) async {
    if (kIsWeb) return operation();
    final trace = FirebasePerformance.instance.newTrace(name);
    await trace.start();
    try {
      final result = await operation();
      return result;
    } finally {
      await trace.stop();
    }
  }
}
