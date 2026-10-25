import 'package:bhromon/features/game_zone/card29/card29_screen.dart';
import 'package:bhromon/features/game_zone/chess/chess_screen.dart';
import 'package:bhromon/features/game_zone/ludo/ludo_screen.dart';
import 'package:bhromon/features/game_zone/teen_patti/teen_patti_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sizes = [Size(320, 568), Size(360, 640), Size(411, 891)];

Future<void> _pumpScreen(WidgetTester tester, Size size, Widget screen) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pump();
}

/// Lets bots and timers run for a while, closing any dialog that pops up.
Future<void> _play(WidgetTester tester, {int steps = 40}) async {
  for (int i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 600));
    final dialogButtons = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(ElevatedButton));
    if (dialogButtons.evaluate().isNotEmpty) {
      await tester.tap(dialogButtons.last);
      await tester.pump();
    }
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  for (final size in _sizes) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('Card 29 lays out and plays without overflow at $label',
        (tester) async {
      await _pumpScreen(tester, size, const Card29Screen());
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        // Pass when asked to bid, pick the first suit, and play the first playable card.
        final pass = find.widgetWithText(OutlinedButton, 'Pass');
        if (pass.evaluate().isNotEmpty) await tester.tap(pass);
        final spades = find.textContaining('♠ Spades');
        if (spades.evaluate().isNotEmpty) await tester.tap(spades.first);
        final playable = find.bySemanticsLabel(RegExp(r', playable$'));
        if (playable.evaluate().isNotEmpty) await tester.tap(playable.first);
        final next = find.text('Next Deal');
        if (next.evaluate().isNotEmpty) await tester.tap(next);
      }
      await _dispose(tester);
    });

    testWidgets('Teen Patti lays out and plays without overflow at $label',
        (tester) async {
      await _pumpScreen(tester, size, const TeenPattiScreen());
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 900));
        final blind = find.textContaining(RegExp(r'^(Blind|Chaal) \('));
        if (blind.evaluate().isNotEmpty) await tester.tap(blind.first);
        final dialogButtons = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(ElevatedButton));
        if (dialogButtons.evaluate().isNotEmpty) {
          await tester.tap(dialogButtons.last);
        }
      }
      await _dispose(tester);
    });

    testWidgets('Ludo lays out and plays without overflow at $label',
        (tester) async {
      await _pumpScreen(tester, size, const LudoScreen());
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 700));
        final dice = find.bySemanticsLabel('Roll dice');
        if (dice.evaluate().isNotEmpty) await tester.tap(dice.first);
        final movable = find.bySemanticsLabel(RegExp(r'can move$'));
        if (movable.evaluate().isNotEmpty) await tester.tap(movable.first);
      }
      await _play(tester, steps: 5);
      await _dispose(tester);
    });

    testWidgets('Chess lays out without overflow at $label', (tester) async {
      await _pumpScreen(tester, size, const ChessScreen());
      // The game is kept between visits, so start fresh through the menu.
      Future<void> settle() async {
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
      }

      await tester.tap(find.byTooltip('Game options'));
      await settle();
      await tester.tap(find.text('New game'));
      await settle();
      final confirm = find.text('Start over');
      if (confirm.evaluate().isNotEmpty) {
        await tester.tap(confirm);
        await settle();
      }
      await tester.tap(find.bySemanticsLabel(RegExp(r'^e2, ')));
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp(r'^e4, empty, legal move')),
          findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp(r'^e4, ')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('thinking'), findsWidgets);
      await _dispose(tester);
    });
  }

  testWidgets('Chess AI answers through a background isolate', (tester) async {
    await _pumpScreen(tester, const Size(411, 891), const ChessScreen());
    Future<void> settle() async {
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await tester.tap(find.byTooltip('Game options'));
    await settle();
    await tester.tap(find.text('New game'));
    await settle();
    final confirm = find.text('Start over');
    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm);
      await settle();
    }
    await tester.tap(find.bySemanticsLabel(RegExp(r'^d2, ')));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel(RegExp(r'^d4, ')));
    await tester.pump(const Duration(milliseconds: 600)); // thinking delay
    var answered = false;
    for (int i = 0; i < 40 && !answered; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      answered = find.text('Your move (White)').evaluate().isNotEmpty;
    }
    expect(answered, isTrue);
    expect(find.textContaining('1. d4 '), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets(
      'Ludo keeps playing after the current colour is switched to a bot',
      (tester) async {
    await _pumpScreen(tester, const Size(411, 891), const LudoScreen());
    await tester.tap(find.byTooltip('Pass & Play Mode'));
    await tester.pumpAndSettle();
    // Make Green human first so Red can be switched to a bot.
    await tester.tap(find.text('Green'));
    await tester.pump();
    await tester.tap(find.text('Red'));
    await tester.pump();
    await tester.tap(find.text('Save & Close'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    // Red is now a bot: it must roll on its own within a second or two.
    var botActed = false;
    for (int i = 0; i < 10 && !botActed; i++) {
      await tester.pump(const Duration(milliseconds: 400));
      botActed = find
          .textContaining(
              RegExp(r'Red bot (rolled|earned)|No valid moves for Red|Green'))
          .evaluate()
          .isNotEmpty;
    }
    expect(botActed, isTrue);
    await _dispose(tester);
  });
}
