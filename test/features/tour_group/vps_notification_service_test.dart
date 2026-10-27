import 'package:bhromon/features/tour_group/data/vps_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VpsNotificationService', () {
    test('singleton instance is persistent', () {
      final s1 = VpsNotificationService();
      final s2 = VpsNotificationService();
      expect(identical(s1, s2), isTrue);
    });

    test('handles unauthenticated or network failures gracefully', () async {
      final service = VpsNotificationService();
      // Should not throw even without Firebase user signed in
      await expectLater(
        service.notifySos(
          tourId: 't1',
          alertId: 'a1',
          senderName: 'Tester',
        ),
        completes,
      );

      await expectLater(
        service.notifyChannelMessage(
          tourId: 't1',
          channelId: 'emergency',
          messageId: 'm1',
          senderName: 'Tester',
          text: 'Emergency message',
        ),
        completes,
      );
    });
  });
}
