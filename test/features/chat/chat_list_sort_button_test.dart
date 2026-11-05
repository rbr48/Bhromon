import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/domain/chat_list_sort.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_list_sort_button.dart';

Future<void> _pump(
  WidgetTester tester, {
  required ChatListSort value,
  required ValueChanged<ChatListSort> onChanged,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('bn')],
    // The same delegates the app registers in lib/main.dart, so Bengali menus build.
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Center(
        child: ChatListSortButton(value: value, onChanged: onChanged),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows Recent by default and reports a switch to Name',
      (tester) async {
    ChatListSort? picked;
    await _pump(tester,
        value: ChatListSort.recent, onChanged: (value) => picked = value);

    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Name'), findsNothing);

    await tester.tap(find.byType(ChatListSortButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();

    expect(picked, ChatListSort.name);
  });

  testWidgets('shows the order in use', (tester) async {
    await _pump(tester, value: ChatListSort.name, onChanged: (_) {});

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Recent'), findsNothing);
  });

  testWidgets('labels the order in Bengali', (tester) async {
    await _pump(
      tester,
      value: ChatListSort.recent,
      onChanged: (_) {},
      locale: const Locale('bn'),
    );

    expect(find.text('সাম্প্রতিক'), findsOneWidget);
  });
}
