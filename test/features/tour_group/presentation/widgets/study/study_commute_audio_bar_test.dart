import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/domain/services/study_tts_controller.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_commute_audio_bar.dart';

Widget buildTestApp({
  required Widget child,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudyTtsController controller;

  setUp(() {
    controller = StudyTtsController(isTestMode: true);
    controller.setTracks([
      const StudyAudioTrack(
        index: 0,
        title: 'Question 1: Succession Planning',
        rawText: 'Raw 1',
        spokenText: 'Spoken 1',
        isBengali: false,
      ),
      const StudyAudioTrack(
        index: 1,
        title: 'Question 2: Negotiable Instruments',
        rawText: 'Raw 2',
        spokenText: 'Spoken 2',
        isBengali: false,
      ),
    ]);
  });

  tearDown(() {
    controller.dispose();
  });

  testWidgets('renders track title, track counter, and playback buttons',
      (tester) async {
    bool closed = false;

    await tester.pumpWidget(
      buildTestApp(
        child: StudyCommuteAudioBar(
          controller: controller,
          onClose: () => closed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('Question 1: Succession Planning'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    expect(find.text('1.0x'), findsOneWidget);

    // Tap play
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    expect(controller.stateNotifier.value, StudyAudioState.playing);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    // Tap next
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pumpAndSettle();
    expect(controller.currentIndexNotifier.value, 1);
    expect(find.text('2/2'), findsOneWidget);
    expect(find.text('Question 2: Negotiable Instruments'), findsOneWidget);

    // Tap close
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(controller.stateNotifier.value, StudyAudioState.stopped);
  });

  testWidgets('renders correctly in Bengali locale', (tester) async {
    controller.setTracks([
      const StudyAudioTrack(
        index: 0,
        title: 'প্রশ্ন ১: ঋণ শ্রেণীকরণ ও প্রভিশনিং',
        rawText: 'Raw',
        spokenText: 'Spoken',
        isBengali: true,
      ),
    ]);

    await tester.pumpWidget(
      buildTestApp(
        locale: const Locale('bn'),
        child: StudyCommuteAudioBar(
          controller: controller,
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1/1'), findsOneWidget);
    expect(find.text('প্রশ্ন ১: ঋণ শ্রেণীকরণ ও প্রভিশনিং'), findsOneWidget);
    expect(find.text('1.0x'), findsOneWidget);
  });
}
