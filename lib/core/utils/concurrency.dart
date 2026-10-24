import 'dart:async';

/// Runs [task] for every item with at most [limit] running at once and
/// returns the results in input order.
///
/// Uploading photos one after another leaves the connection idle between
/// files; a small pool keeps it busy without starting dozens at once.
Future<List<R>> mapWithConcurrency<T, R>(
  List<T> items,
  int limit,
  Future<R> Function(T item, int index) task,
) async {
  assert(limit > 0);
  final results = List<R?>.filled(items.length, null);
  var next = 0;

  Future<void> worker() async {
    while (next < items.length) {
      final index = next++;
      results[index] = await task(items[index], index);
    }
  }

  await Future.wait([
    for (var i = 0; i < limit && i < items.length; i++) worker(),
  ]);
  return results.cast<R>();
}
