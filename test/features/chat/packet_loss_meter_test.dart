import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/domain/call_quality.dart';
import 'package:bhromon/features/chat/presentation/widgets/packet_loss_meter.dart';

void main() {
  Widget buildTestWidget({
    required ValueNotifier<CallNetworkQuality> qualityNotifier,
    required ValueNotifier<CallLinkSample?> sampleNotifier,
    bool initiallyExpanded = false,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: Scaffold(
        body: Center(
          child: CallQualityHud(
            qualityNotifier: qualityNotifier,
            sampleNotifier: sampleNotifier,
            initiallyExpanded: initiallyExpanded,
          ),
        ),
      ),
    );
  }

  testWidgets('renders HD quality badge when link is good', (tester) async {
    final qualityNotifier = ValueNotifier(CallNetworkQuality.good);
    final sampleNotifier = ValueNotifier<CallLinkSample?>(null);

    await tester.pumpWidget(buildTestWidget(
      qualityNotifier: qualityNotifier,
      sampleNotifier: sampleNotifier,
    ));
    await tester.pumpAndSettle();

    expect(find.text('HD'), findsOneWidget);
  });

  testWidgets('displays loss percentage and expands RTT / bitrate HUD on tap',
      (tester) async {
    final qualityNotifier = ValueNotifier(CallNetworkQuality.good);
    const sample = CallLinkSample(
      roundTripMs: 42,
      lossRatio: 0.02,
      outboundKbps: 380,
    );
    final sampleNotifier = ValueNotifier<CallLinkSample?>(sample);

    await tester.pumpWidget(buildTestWidget(
      qualityNotifier: qualityNotifier,
      sampleNotifier: sampleNotifier,
    ));
    await tester.pumpAndSettle();

    expect(find.text('· 2% loss'), findsOneWidget);
    // Initially collapsed
    expect(find.text('42 ms'), findsNothing);

    // Tap to expand
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(find.text('42 ms'), findsOneWidget);
    expect(find.text('2.0%'), findsOneWidget);
    expect(find.text('380 k'), findsOneWidget);

    // Tap again to collapse
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(find.text('42 ms'), findsNothing);
  });

  testWidgets('adapts label when quality changes to fair or weak',
      (tester) async {
    final qualityNotifier = ValueNotifier(CallNetworkQuality.fair);
    final sampleNotifier = ValueNotifier<CallLinkSample?>(null);

    await tester.pumpWidget(buildTestWidget(
      qualityNotifier: qualityNotifier,
      sampleNotifier: sampleNotifier,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Fair'), findsOneWidget);

    qualityNotifier.value = CallNetworkQuality.poor;
    await tester.pumpAndSettle();

    expect(find.text('Weak'), findsOneWidget);
  });
}
