import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/app/route_not_found_screen.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/notifications/presentation/pages/notification_center_screen.dart';
import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/channel_media_viewer.dart';

void main() {
  group('Group Module Navigation Audit & PopScope Tests', () {
    testWidgets('RouteNotFoundScreen has PopScope and top back button',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        home: RouteNotFoundScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(RouteNotFoundScreen), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is PopScope),
          findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets(
        'NotificationCenterScreen has PopScope and top leading back button',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        home: NotificationCenterScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationCenterScreen), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is PopScope),
          findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('Channel media viewer shows top back button and pops cleanly',
        (tester) async {
      const attachment = ChannelAttachment(
        url: 'https://example.com/photo.jpg',
        fileName: 'photo.jpg',
        fileSizeBytes: 1024,
      );

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showChannelMediaViewer(context, attachment),
              child: const Text('Open Viewer'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Open media viewer
      await tester.tap(find.text('Open Viewer'));
      await tester.pumpAndSettle();

      // Check PopScope and back button exist
      expect(find.byWidgetPredicate((w) => w is PopScope),
          findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Verifies viewer is popped and base page restored
      expect(find.text('Open Viewer'), findsOneWidget);
    });
  });
}
