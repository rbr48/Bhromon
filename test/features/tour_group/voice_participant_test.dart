import 'package:bhromon/features/tour_group/data/voice_room_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a seat keeps its session and reads back the same', () {
    final seat = VoiceParticipant(
      email: 'Asha@X.com',
      displayName: 'Asha',
      uid: 'u1',
      joinedAt: DateTime(2026),
      sessionId: 's1',
    );

    final map = seat.toMap();
    expect(map['email'], 'asha@x.com');
    expect(map['sessionId'], 's1');

    final back = VoiceParticipant.fromMap(map);
    expect(back.email, 'asha@x.com');
    expect(back.sessionId, 's1');
  });

  test('a seat without a session leaves the field out', () {
    final seat = VoiceParticipant(
      email: 'a@x.com',
      displayName: 'A',
      joinedAt: DateTime(2026),
    );

    expect(seat.toMap().containsKey('sessionId'), isFalse);
  });
}
