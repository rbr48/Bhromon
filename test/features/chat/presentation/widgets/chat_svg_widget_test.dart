import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_rich_text.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleSvg =
    '''<svg viewBox="0 0 200 100" xmlns="http://www.w3.org/2000/svg">
  <title>Indifference Curve Test</title>
  <rect width="200" height="100" fill="#f0f0f0"/>
  <circle cx="50" cy="50" r="30" fill="#00aa00"/>
</svg>''';

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  ));
}

void main() {
  testWidgets('ChatSvgWidget renders SvgPicture and extracts title',
      (tester) async {
    await _pump(tester, child: const ChatSvgWidget(svg: _sampleSvg));
    await tester.pumpAndSettle();

    expect(find.byType(ChatSvgWidget), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('Indifference Curve Test'), findsOneWidget);
    expect(find.text('SVG'), findsOneWidget);
  });

  testWidgets('ChatRichText renders ChatSvgWidget from ```svg markdown fence',
      (tester) async {
    const markdown = '''
Here is the diagram:

```svg
$_sampleSvg
```

End of diagram.
''';

    await _pump(tester, child: const ChatRichText(text: markdown));
    await tester.pumpAndSettle();

    expect(find.byType(ChatSvgWidget), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('Indifference Curve Test'), findsOneWidget);
  });

  testWidgets('toggle view code shows raw svg code', (tester) async {
    await _pump(tester, child: const ChatSvgWidget(svg: _sampleSvg));
    await tester.pumpAndSettle();

    expect(find.byTooltip('View SVG Code'), findsOneWidget);
    await tester.tap(find.byTooltip('View SVG Code'));
    await tester.pumpAndSettle();

    expect(find.text('Show Diagram'), findsOneWidget);
    expect(find.textContaining('<svg'), findsOneWidget);

    await tester.tap(find.text('Show Diagram'));
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsOneWidget);
  });
}
