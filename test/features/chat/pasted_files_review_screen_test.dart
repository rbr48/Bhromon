import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/presentation/pages/pasted_files_review_screen.dart';
import 'package:bhromon/features/share_intake/domain/shared_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The review a pasted file is shown in before it is sent. The paths do not exist: documents and
// voice notes are not read, and a photo that cannot be read shows a placeholder.

SharedFile _file(String name, {int size = 2048}) => SharedFile(
      name: name,
      sizeBytes: size,
      path: '/no/such/folder/$name',
      mimeType: null,
    );

/// Opens the review from a button, the way the screens open it, and keeps what it returns.
class _Host {
  PastedReview? result;
  bool returned = false;
}

Future<_Host> _open(
  WidgetTester tester, {
  required List<SharedFile> files,
  bool allowCaption = true,
}) async {
  final host = _Host();
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
        body: TextButton(
          onPressed: () async {
            host.result = await Navigator.of(context).push<PastedReview>(
              MaterialPageRoute(
                builder: (_) => PastedFilesReviewScreen(
                  files: files,
                  allowCaption: allowCaption,
                  captionMaxLength: 1000,
                ),
              ),
            );
            host.returned = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  // The localisations load after the first frame, so the home screen is settled before it is used.
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return host;
}

void main() {
  testWidgets('shows a tile for each file and how many will be sent',
      (tester) async {
    await _open(tester, files: [_file('notes.pdf'), _file('voice.m4a')]);

    expect(find.text('2 to send'), findsOneWidget);
    expect(find.text('notes.pdf'), findsOneWidget);
    expect(find.text('voice.m4a'), findsOneWidget);
  });

  testWidgets('a file taken out is not sent, and the others are',
      (tester) async {
    final host = await _open(
      tester,
      files: [_file('notes.pdf'), _file('report.docx')],
    );

    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();
    expect(find.text('1 to send'), findsOneWidget);

    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(host.result, isNotNull);
    expect(host.result!.files.map((file) => file.name), ['report.docx']);
  });

  testWidgets('Send returns the caption, trimmed', (tester) async {
    final host = await _open(tester, files: [_file('notes.pdf')]);

    await tester.enterText(find.byType(TextField), '  the notes  ');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(host.result!.caption, 'the notes');
  });

  testWidgets('a review with no caption field returns an empty caption',
      (tester) async {
    final host = await _open(
      tester,
      files: [_file('notes.pdf')],
      allowCaption: false,
    );

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(host.result!.caption, '');
  });

  testWidgets('closing the review returns nothing, and sends nothing',
      (tester) async {
    final host = await _open(tester, files: [_file('notes.pdf')]);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(host.returned, isTrue);
    expect(host.result, isNull);
  });

  testWidgets('with nothing left, Send is off and the screen says so',
      (tester) async {
    await _open(tester, files: [_file('notes.pdf')]);

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing left to send'), findsOneWidget);
    final send = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(send.onPressed, isNull);
  });
}
