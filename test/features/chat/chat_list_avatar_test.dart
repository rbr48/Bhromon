import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/chat/presentation/pages/chats_list_screen.dart';

void main() {
  group('chatAvatarUrl', () {
    test('the chat keeps its own photo when it has one', () {
      expect(chatAvatarUrl('chat.jpg', 'profile.jpg'), 'chat.jpg');
      expect(
        chatAvatarUrl('chat.jpg', 'profile.jpg', fallback: 'google.jpg'),
        'chat.jpg',
      );
    });

    test('the live profile fills in when the chat copy has no photo', () {
      expect(chatAvatarUrl(null, 'profile.jpg'), 'profile.jpg');
      expect(chatAvatarUrl('', 'profile.jpg'), 'profile.jpg');
      expect(
        chatAvatarUrl(null, 'profile.jpg', fallback: 'google.jpg'),
        'profile.jpg',
      );
    });

    test(
        'fallback (Google photo) fills in when chat copy and profile have no photo',
        () {
      expect(
        chatAvatarUrl(
          null,
          null,
          fallback: 'https://lh3.googleusercontent.com/photo.jpg',
        ),
        'https://lh3.googleusercontent.com/photo.jpg',
      );
      expect(
        chatAvatarUrl(
          '',
          '',
          fallback: 'https://lh3.googleusercontent.com/photo.jpg',
        ),
        'https://lh3.googleusercontent.com/photo.jpg',
      );
    });

    test('no photo anywhere gives null, so the row shows initials', () {
      expect(chatAvatarUrl(null, null), isNull);
      expect(chatAvatarUrl('', ''), isNull);
      expect(chatAvatarUrl(null, null, fallback: null), isNull);
      expect(chatAvatarUrl('', '', fallback: ''), isNull);
    });
  });
}
