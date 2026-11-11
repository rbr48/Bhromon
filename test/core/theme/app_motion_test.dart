import 'package:bhromon/core/theme/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({required bool reduced}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) => AppMotion.pageTransition(
            context,
            const AlwaysStoppedAnimation<double>(0.5),
            const Text('page'),
          ),
        ),
      ),
    );
  }

  testWidgets('a page fades and slides in', (tester) async {
    await tester.pumpWidget(host(reduced: false));
    expect(find.byType(FadeTransition), findsOneWidget);
    expect(find.byType(SlideTransition), findsOneWidget);
  });

  testWidgets('a page does not move with reduced motion on', (tester) async {
    await tester.pumpWidget(host(reduced: true));
    expect(find.byType(FadeTransition), findsNothing);
    expect(find.byType(SlideTransition), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('FadeIn ends fully visible', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FadeIn(child: Text('x'))));
    await tester.pumpAndSettle();
    final fade = tester.widget<FadeTransition>(find.descendant(
      of: find.byType(FadeIn),
      matching: find.byType(FadeTransition),
    ));
    expect(fade.opacity.value, 1);
  });
}
