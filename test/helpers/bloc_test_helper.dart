import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal drop-in replacement for `blocTest` from package:bloc_test.
///
/// bloc_test cannot resolve against Flutter 3.44's flutter_test (its `test`
/// dependency needs an analyzer major that freezed 2.x forbids), so this
/// helper replicates the subset of its API the suite uses:
/// [build], [seed], [act], [wait], [expect], [verify], [skip].
void blocTest<B extends BlocBase<State>, State>(
  String description, {
  required B Function() build,
  State Function()? seed,
  FutureOr<void> Function(B bloc)? act,
  Duration? wait,
  int skip = 0,
  dynamic Function()? expect,
  FutureOr<void> Function(B bloc)? verify,
}) {
  test(description, () async {
    final bloc = build();
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    if (seed != null) bloc.emit(seed());

    final states = <State>[];
    final subscription = bloc.stream.skip(skip).listen(states.add);

    try {
      if (act != null) await act(bloc);
      if (wait != null) await Future<void>.delayed(wait);
      // Let any queued microtasks/emissions settle.
      await Future<void>.delayed(Duration.zero);

      if (expect != null) {
        final dynamic expected = expect();
        expectLater(states, wrapMatcher(expected));
      }
      if (verify != null) await verify(bloc);
    } finally {
      await subscription.cancel();
      await bloc.close();
    }
  });
}
