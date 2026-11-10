import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_formatting_toolbar.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The study text field's markup menu: the "Aa" button shows the chat's formatting menu, without a table button.

Future<void> _pump(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home:
        Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: page)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('study text has a markup button and no table action',
      (tester) async {
    await _pump(tester, StudyTextField(controller: TextEditingController()));

    expect(find.text('Aa'), findsOneWidget);
    expect(find.byIcon(Icons.table_chart_outlined), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(ChatFormattingToolbar), findsNothing);
  });

  testWidgets(
      'the markup button shows the formatting menu without a table button',
      (tester) async {
    final controller = TextEditingController();
    await _pump(tester, StudyTextField(controller: controller));

    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();

    final menu = tester
        .widget<ChatFormattingToolbar>(find.byType(ChatFormattingToolbar));
    expect(menu.showTable, isFalse);

    // Bold puts an empty pair of markers in at the cursor, as the chat composers do.
    // The bold tap focuses the field, and its cursor blinks, so one frame is pumped rather than waiting to settle.
    await tester.tap(find.text('B'));
    await tester.pump();
    expect(controller.text, '****');
  });

  testWidgets('the markup button hides the menu when tapped again',
      (tester) async {
    await _pump(tester, StudyTextField(controller: TextEditingController()));

    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatFormattingToolbar), findsOneWidget);

    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatFormattingToolbar), findsNothing);
  });
}
