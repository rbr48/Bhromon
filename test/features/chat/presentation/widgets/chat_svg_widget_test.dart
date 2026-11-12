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

const _headingSvg =
    '''<svg viewBox="0 0 400 240" xmlns="http://www.w3.org/2000/svg">
  <text x="200" y="230" font-size="14">Quantity</text>
  <text x="200" y="16" font-size="16" font-weight="bold">Demand and supply</text>
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

Future<void> _pumpIn(
  WidgetTester tester, {
  required ThemeData theme,
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
    theme: theme,
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

  testWidgets('the diagram sits on a white page, in dark mode too',
      (tester) async {
    await _pumpIn(
      tester,
      theme: ThemeData(brightness: Brightness.dark),
      child: const ChatSvgWidget(svg: _sampleSvg),
    );
    await tester.pumpAndSettle();

    final page = find.ancestor(
      of: find.byType(SvgPicture),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color == Colors.white,
      ),
    );
    expect(page, findsOneWidget);
  });

  testWidgets(
      'the title is the heading, not an axis name, when there is no title element',
      (tester) async {
    await _pump(tester, child: const ChatSvgWidget(svg: _headingSvg));
    await tester.pumpAndSettle();

    expect(find.text('Demand and supply'), findsOneWidget);
    expect(find.text('Quantity'), findsNothing);
  });

  testWidgets('the card draws the diagram at its own proportions',
      (tester) async {
    await _pump(tester, child: const ChatSvgWidget(svg: _sampleSvg));
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(SvgPicture));
    expect(size.aspectRatio, closeTo(2.0, 0.01));
    expect(size.height, lessThan(380));
  });

  group('diagram proportions', () {
    test(
        'the ratio comes from the viewBox, with commas or spaces between the numbers',
        () {
      expect(
        svgAspectRatio('<svg viewBox="0 0 400 240">'),
        closeTo(400 / 240, 1e-9),
      );
      expect(svgAspectRatio('<svg viewBox="0,0,200,100">'), 2.0);
      expect(svgAspectRatio('<svg viewBox="-10 -5 20 10">'), 2.0);
    });

    test(
        'without a usable viewBox the width and height give it, and a stroke width does not',
        () {
      expect(svgAspectRatio('<svg width="300px" height="150">'), 2.0);
      expect(
        svgAspectRatio('<svg stroke-width="5" width="100" height="50">'),
        2.0,
      );
    });

    test('a diagram with no size gives no ratio', () {
      expect(svgAspectRatio('<svg>'), isNull);
      expect(svgAspectRatio('<svg viewBox="0 0 10 0">'), isNull);
      expect(svgAspectRatio('<p>not a diagram</p>'), isNull);
    });
  });

  group('diagram title', () {
    test('the title element wins', () {
      expect(svgDiagramTitle(_sampleSvg), 'Indifference Curve Test');
    });

    test(
        'a bold label beats a larger plain one, and a larger label beats a smaller one',
        () {
      expect(svgDiagramTitle(_headingSvg), 'Demand and supply');
      expect(
        svgDiagramTitle(
          '<svg><text font-size="20">Big</text>'
          '<text font-size="12" font-weight="bold">Bold</text></svg>',
        ),
        'Bold',
      );
      expect(
        svgDiagramTitle(
          '<svg><text font-size="12">Small</text>'
          '<text font-size="20">Large</text></svg>',
        ),
        'Large',
      );
    });

    test(
        'ties go to the label that comes first, and a diagram with no words has no title',
        () {
      expect(
        svgDiagramTitle('<svg><text>First</text><text>Second</text></svg>'),
        'First',
      );
      expect(
        svgDiagramTitle('<svg><rect width="1" height="1"/></svg>'),
        isNull,
      );
    });

    test(
        'entities are decoded, and a label too long for a title is passed over',
        () {
      expect(
        svgDiagramTitle('<svg><title>Cost &amp; Benefit</title></svg>'),
        'Cost & Benefit',
      );
      final long = 'x' * 95;
      expect(
        svgDiagramTitle(
          '<svg><text font-size="30">$long</text><text>Short</text></svg>',
        ),
        'Short',
      );
    });
  });

  group('diagram font', () {
    test('the app font is set on the root element, once', () {
      final once = svgWithDiagramFont(
        '<svg viewBox="0 0 10 10"><text>A</text></svg>',
      );
      expect(
        once,
        '<svg font-family="NotoSansBengali" viewBox="0 0 10 10"><text>A</text></svg>',
      );
      expect(svgWithDiagramFont(once), once);
    });

    test(
        'a diagram that names its own font keeps it, and text with no diagram is left alone',
        () {
      const named = '<svg font-family="Arial"><text>A</text></svg>';
      expect(svgWithDiagramFont(named), named);
      expect(
        svgWithDiagramFont('<p>not a diagram</p>'),
        '<p>not a diagram</p>',
      );
    });
  });
}
