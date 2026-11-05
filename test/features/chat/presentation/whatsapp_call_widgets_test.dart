import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/chat/presentation/widgets/whatsapp_call_widgets.dart';

void main() {
  group('WhatsAppCallActionBtn', () {
    testWidgets('renders icon, label, and responds to tap', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WhatsAppCallActionBtn(
              icon: Icons.mic_off_rounded,
              label: 'Mute',
              iconColor: Colors.white,
              bgColor: WhatsAppCallTheme.surfaceElevated,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Mute'), findsOneWidget);
      expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);

      await tester.tap(find.byType(WhatsAppCallActionBtn));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('renders end call styling when isEndCall is true',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WhatsAppCallActionBtn(
              icon: Icons.call_end_rounded,
              label: 'End',
              iconColor: Colors.white,
              bgColor: WhatsAppCallTheme.accentRed,
              onTap: () {},
              isEndCall: true,
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.call_end_rounded));
      expect(icon.size, 30);
      expect(find.text('End'), findsOneWidget);
    });
  });

  group('WhatsAppPulsingAvatar', () {
    testWidgets('renders initials when no avatar URL is provided',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WhatsAppPulsingAvatar(
              userName: 'Rahim Khan',
              isRingingOrActive: true,
            ),
          ),
        ),
      );

      expect(find.text('R'), findsOneWidget);
    });

    testWidgets('renders static initials without pulsing rings when inactive',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WhatsAppPulsingAvatar(
              userName: 'Tariq Hasan',
              isRingingOrActive: false,
            ),
          ),
        ),
      );

      expect(find.text('T'), findsOneWidget);
      final avatarTransforms = find.descendant(
        of: find.byType(WhatsAppPulsingAvatar),
        matching: find.byType(Transform),
      );
      expect(avatarTransforms, findsNothing);
    });

    testWidgets(
        'dynamically activates pulsing ripples when state changes to active',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WhatsAppPulsingAvatar(
              userName: 'Nadia Chowdhury',
              isRingingOrActive: false,
            ),
          ),
        ),
      );

      final avatarTransforms = find.descendant(
        of: find.byType(WhatsAppPulsingAvatar),
        matching: find.byType(Transform),
      );
      expect(avatarTransforms, findsNothing);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WhatsAppPulsingAvatar(
              userName: 'Nadia Chowdhury',
              isRingingOrActive: true,
            ),
          ),
        ),
      );

      // Now animated ripple rings are added to tree inside avatar
      expect(avatarTransforms, findsNWidgets(2));
    });
  });
}
