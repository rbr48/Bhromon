import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/group_back_button.dart';
import 'package:bhromon/features/tour_group/presentation/tour_routes.dart';

void main() {
  group('GroupBackButton & GroupPopScope Tests', () {
    testWidgets(
        'GroupBackButton renders arrow_back icon and calls custom callback if provided',
        (tester) async {
      bool customBackCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              leading: GroupBackButton(
                tourId: 'tour-123',
                onCustomBack: () {
                  customBackCalled = true;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      await tester.tap(find.byType(GroupBackButton));
      await tester.pump();

      expect(customBackCalled, isTrue);
    });

    testWidgets('GroupBackButton pops when navigator canPop is true',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          appBar: PreferredSize(
                            preferredSize: Size.fromHeight(kToolbarHeight),
                            child: GroupBackButton(tourId: 'tour-123'),
                          ),
                          body: Text('Second Page'),
                        ),
                      ),
                    );
                  },
                  child: const Text('Go Next'),
                ),
              ),
            ),
          ),
        ),
      );

      // Navigate to second page
      await tester.tap(find.text('Go Next'));
      await tester.pumpAndSettle();
      expect(find.text('Second Page'), findsOneWidget);

      // Tap GroupBackButton
      await tester.tap(find.byType(GroupBackButton));
      await tester.pumpAndSettle();

      // Second page popped, first page back
      expect(find.text('Go Next'), findsOneWidget);
      expect(find.text('Second Page'), findsNothing);
    });

    testWidgets(
        'GroupPopScope intercepts back pop and executes onCustomPop when provided',
        (tester) async {
      bool customPopCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: GroupPopScope(
            tourId: 'tour-123',
            onCustomPop: () {
              customPopCalled = true;
            },
            child: const Scaffold(
              body: Text('Content with custom pop'),
            ),
          ),
        ),
      );

      expect(find.text('Content with custom pop'), findsOneWidget);

      // Simulate system back gesture/key
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pump();

      expect(customPopCalled, isTrue);
    });

    testWidgets(
        'navigateBackOrToGroup falls back to tourHubPath when cannot pop',
        (tester) async {
      String? navigatedLocation;

      final router = GoRouter(
        initialLocation: '/some-screen',
        routes: [
          GoRoute(
            path: '/some-screen',
            builder: (context, state) => Scaffold(
              appBar: AppBar(
                leading: const GroupBackButton(tourId: 't123'),
              ),
              body: const Text('Screen 1'),
            ),
          ),
          GoRoute(
            path: '/group-hub',
            builder: (context, state) {
              navigatedLocation = state.uri.toString();
              return const Scaffold(body: Text('Group Hub'));
            },
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('Screen 1'), findsOneWidget);

      // Tap back button with empty navigation stack
      await tester.tap(find.byType(GroupBackButton));
      await tester.pumpAndSettle();

      expect(find.text('Group Hub'), findsOneWidget);
      expect(navigatedLocation, tourHubPath('t123'));
    });
  });
}
