import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/network/turn_config.dart';

void main() {
  test('without build defines only the STUN servers are configured', () {
    expect(TurnConfig.hasRelay, isFalse);
    final servers = TurnConfig.iceServers;
    expect(servers, hasLength(1));
    expect(servers.single['urls'], everyElement(startsWith('stun:')));
    expect(servers.single.containsKey('credential'), isFalse);
  });
}
