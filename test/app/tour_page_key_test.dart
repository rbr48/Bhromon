import 'package:bhromon/app/tour_page_key.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A tour screen that, like the real ones, loads its data in initState.
class _TourProbe extends StatefulWidget {
  const _TourProbe({required this.tourId});

  final String tourId;

  @override
  State<_TourProbe> createState() => _TourProbeState();
}

class _TourProbeState extends State<_TourProbe> {
  static int loads = 0;

  late final String _loadedFor;

  @override
  void initState() {
    super.initState();
    loads++;
    _loadedFor = widget.tourId;
  }

  @override
  Widget build(BuildContext context) {
    return Text('shows ${widget.tourId}, loaded for $_loadedFor');
  }
}

void main() {
  testWidgets(
      'moving from one tour to another on the same page gives the new tour its own screen',
      (tester) async {
    _TourProbeState.loads = 0;
    final router = GoRouter(
      initialLocation: '/group/tour_a/feed',
      routes: [
        GoRoute(
          path: '/group/:tourId/feed',
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: pageKeyFor(state),
            child: _TourProbe(tourId: state.pathParameters['tourId']!),
            transitionDuration: Duration.zero,
            transitionsBuilder: (_, __, ___, child) => child,
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('shows tour_a, loaded for tour_a'), findsOneWidget);

    router.go('/group/tour_b/feed');
    await tester.pumpAndSettle();

    expect(find.text('shows tour_b, loaded for tour_b'), findsOneWidget);
    expect(_TourProbeState.loads, 2);
  });
}
