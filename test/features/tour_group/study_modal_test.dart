import 'package:bhromon/features/tour_group/presentation/widgets/study/study_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Study modals open as a card in the middle of the screen, and return what they pop.

void main() {
  testWidgets('a study modal is a card in the middle of the screen',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showStudyModal<void>(
                context: context,
                builder: (_) => const Center(child: Text('the form')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final card = tester.getCenter(find.byType(Dialog));
    final screen = tester.getCenter(find.byType(Scaffold));
    expect((card.dx - screen.dx).abs(), lessThan(1));
    expect((card.dy - screen.dy).abs(), lessThan(1));
    expect(find.text('the form'), findsOneWidget);
  });

  testWidgets('the value the modal pops is what the caller receives',
      (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await showStudyModal<String>(
                  context: context,
                  builder: (sheetContext) => Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop('saved'),
                      child: const Text('save'),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(result, 'saved');
    expect(find.byType(Dialog), findsNothing);
  });
}
