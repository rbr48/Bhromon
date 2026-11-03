import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // The chat menu's "Your groups" item once pushed /tour-groups, which the
  // router never defined, so users saw a "Page not found" error.
  test('the chat menu opens the group hub, and the router has an error page',
      () {
    final chatList =
        File('lib/features/chat/presentation/pages/chats_list_screen.dart')
            .readAsStringSync();
    final router = File('lib/app/router.dart').readAsStringSync();

    expect(chatList, contains("context.push('/group-hub')"));
    expect(chatList, isNot(contains("'/tour-groups'")));
    expect(router, contains("path: '/group-hub',"));
    expect(router, contains('errorBuilder:'));
  });
}
