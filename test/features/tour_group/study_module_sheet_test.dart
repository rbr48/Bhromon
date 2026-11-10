import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_module_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The module settings card: its title and buttons stay in view while the list scrolls, every live module
// is an option, the modules not built yet are disabled and marked coming soon, a book module has no posting
// policy, and Cancel and Save behave as their names say.

const _comingLabels = [
  'Past papers',
  'Assignments',
];

Future<void> _open(
  WidgetTester tester,
  Map<StudyModuleKey, StudyModuleSettings> current,
  void Function(List<StudyModuleSettings>? result) onResult,
) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => onResult(
              await showStudyModuleSheet(context, current: current),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  // The localizations load asynchronously, so the page is built only after the frames settle.
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the title and the buttons stay in view while the list scrolls',
      (tester) async {
    await _open(tester, const {}, (_) {});

    expect(find.text('Modules'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Modules'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets(
      'every module not built yet is an option: disabled, and marked coming soon',
      (tester) async {
    await _open(tester, const {}, (_) {});

    for (final label in _comingLabels) {
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, label),
      );
      expect(tile.onChanged, isNull, reason: label);
      expect(tile.value, isFalse, reason: label);
    }
    expect(find.text('Coming soon'), findsNWidgets(_comingLabels.length));
  });

  testWidgets(
      'a book module has no posting policy, and says that it opens the subject\'s book',
      (tester) async {
    await _open(tester, const {}, (_) {});

    // The five modules that keep their own posts have a policy; the five book modules do not.
    expect(find.text('Who can post'), findsNWidgets(5));
    expect(find.textContaining('open this book'), findsNWidgets(5));
    for (final label in [
      'Discussion',
      'Glossary',
      'Flashcards',
      'Quizzes',
      'Study plan'
    ]) {
      expect(find.widgetWithText(SwitchListTile, label), findsOneWidget,
          reason: label);
    }
  });

  testWidgets('Cancel closes the card without a result', (tester) async {
    var closed = false;
    List<StudyModuleSettings>? result;
    await _open(tester, const {}, (r) {
      closed = true;
      result = r;
    });

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, isNull);
    expect(find.text('Modules'), findsNothing);
  });

  testWidgets('Save returns every live module with its switch and its name',
      (tester) async {
    List<StudyModuleSettings>? result;
    await _open(
      tester,
      {
        StudyModuleKey.tips: const StudyModuleSettings(
          key: StudyModuleKey.tips,
          enabled: true,
          name: 'Exam tips',
          postPolicy: StudyPostPolicy.members,
        ),
      },
      (r) => result = r,
    );

    // The tile sits below the fold of the card, so bring it into view before the tap.
    final problems = find.widgetWithText(SwitchListTile, 'Problem solving');
    await tester.ensureVisible(problems);
    await tester.pump();
    await tester.tap(problems);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    final byKey = {for (final s in result!) s.key: s};
    expect(byKey[StudyModuleKey.tips]!.enabled, isTrue);
    expect(byKey[StudyModuleKey.tips]!.name, 'Exam tips');
    expect(byKey[StudyModuleKey.problems]!.enabled, isTrue);
    expect(byKey[StudyModuleKey.problems]!.name, 'Problem solving');
    // A module not built yet is never part of what gets saved.
    expect(byKey.containsKey(StudyModuleKey.papers), isFalse);
  });
}
