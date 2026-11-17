import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/theme.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_composer_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatComposerCard & borderlessComposerDecoration', () {
    testWidgets(
        'text field spans full panel width above actions and suppresses InputDecorationTheme borders',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('bn')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatComposerCard(
                backgroundColor: Colors.white,
                textField: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 6,
                  decoration: borderlessComposerDecoration(hintText: 'Message'),
                ),
                leadingActions: [
                  ComposerFormatButton(
                    active: false,
                    inactiveColor: Colors.grey,
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: () {},
                  ),
                ],
                trailingAction: IconButton(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Suppresses global OutlineInputBorder + fillColor even when focused.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final textField = tester.widget<TextField>(find.byType(TextField));
      final decoration = textField.decoration!;
      expect(decoration.filled, isFalse);
      expect(decoration.border, InputBorder.none);
      expect(decoration.enabledBorder, InputBorder.none);
      expect(decoration.focusedBorder, InputBorder.none);
      expect(decoration.disabledBorder, InputBorder.none);
      expect(decoration.errorBorder, InputBorder.none);
      expect(decoration.focusedErrorBorder, InputBorder.none);

      // TextField takes full width (400 - 8 outer - 24 inner = 368) and action buttons sit below it.
      final fieldRect = tester.getRect(find.byType(TextField));
      final attachRect = tester.getRect(find.byIcon(Icons.attach_file));
      final sendRect = tester.getRect(find.byIcon(Icons.send_rounded));

      expect(fieldRect.width, greaterThanOrEqualTo(360));
      expect(attachRect.top, greaterThanOrEqualTo(fieldRect.bottom));
      expect(sendRect.top, greaterThanOrEqualTo(fieldRect.bottom));
      expect(sendRect.left, greaterThan(attachRect.right));
    });
  });
}
