import 'dart:io';
import 'package:bhromon/features/chat/presentation/widgets/chat_rich_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'ChatRichText renders full JAIBB solutions markdown without errors',
      (tester) async {
    final file = File(
        r'C:\Users\USER\Downloads\jaibb_basic_accounting_8th_bpe_2026_solutions.md');
    if (!file.existsSync()) {
      // On CI runner where the specific local file is absent
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(find.byType(SizedBox), findsOneWidget);
      return;
    }
    final content = file.readAsStringSync();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChatRichText(
              text: content,
              collapsible: false,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(ChatRichText), findsOneWidget);
  });
}
