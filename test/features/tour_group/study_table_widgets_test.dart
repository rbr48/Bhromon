import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_table_widget.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_rich_text.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Tables in study text: study text draws a markdown table as a table, and no text field caps its length. The
// text field has no table action; its markup menu is tested in study_markup_menu_test.dart.

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
