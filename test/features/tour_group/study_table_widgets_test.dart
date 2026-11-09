import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_table_widget.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_rich_text.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_table_editor.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Tables in study text: the text field adds a table at the cursor or edits the one under it, the editor saves a
// grid, study text draws a table as a table, and no text field caps its length.

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

/// The cell fields of the open table editor, in reading order: the header first.
Finder _cells(WidgetTester tester) => find.descendant(
      of: find.byType(StudyTableEditor),
      matching: find.byType(TextField),
    );

void main() {
  testWidgets('the table action adds a new table at the cursor',
      (tester) async {
    final controller = TextEditingController(text: 'Before the table');
    controller.selection =
        const TextSelection.collapsed(offset: 'Before the table'.length);
    await _pump(tester, StudyTextField(controller: controller));

    await tester.tap(find.widgetWithText(TextButton, 'Table'));
    await tester.pumpAndSettle();
    expect(find.text('New table'), findsOneWidget);

    // A new table is a header and one body row, two columns each.
    expect(_cells(tester), findsNWidgets(4));
    await tester.enterText(_cells(tester).at(0), 'Date');
    await tester.enterText(_cells(tester).at(1), 'Amount');
    await tester.enterText(_cells(tester).at(2), '1 Jan');
    await tester.enterText(_cells(tester).at(3), '40,000');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
        controller.text,
        'Before the table\n'
        '| Date | Amount |\n'
        '| --- | --- |\n'
        '| 1 Jan | 40,000 |');
  });

  testWidgets(
      'the table action edits the table the cursor is in, and does not add another',
      (tester) async {
    const existing = 'Intro\n| a | b |\n| --- | --- |\n| 1 | 2 |\nOutro';
    final controller = TextEditingController(text: existing);
    controller.selection =
        TextSelection.collapsed(offset: existing.indexOf('1 |'));
    await _pump(tester, StudyTextField(controller: controller));

    await tester.tap(find.widgetWithText(TextButton, 'Table'));
    await tester.pumpAndSettle();
    expect(find.text('Edit table'), findsOneWidget);
    // The editor opens on the table's cells.
    expect(
        tester.widget<TextField>(_cells(tester).at(2)).controller!.text, '1');

    await tester.enterText(_cells(tester).at(2), '9');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
        controller.text, 'Intro\n| a | b |\n| --- | --- |\n| 9 | 2 |\nOutro');
    expect(controller.text.split('| --- | --- |').length, 2,
        reason: 'one table, not two');
  });

  testWidgets('the text field has no length limit', (tester) async {
    final controller = TextEditingController();
    await _pump(tester, StudyTextField(controller: controller));

    expect(tester.widget<TextField>(find.byType(TextField)).maxLength, isNull);
    final long = 'x' * 5000;
    controller.text = long;
    expect(controller.text.length, 5000);
  });

  testWidgets('study text draws a markdown table as a table', (tester) async {
    await _pump(
      tester,
      const StudyRichText(
          'Balance:\n| Date | Amount |\n| --- | --- |\n| 1 Jan | 40,000 |'),
    );
    expect(find.byType(ChatTableWidget), findsOneWidget);
  });

  testWidgets('study text without a table is shown as text', (tester) async {
    await _pump(tester, const StudyRichText('A plain note with no table.'));
    expect(find.byType(ChatTableWidget), findsNothing);
    expect(find.byType(StudyRichText), findsOneWidget);
  });
}
