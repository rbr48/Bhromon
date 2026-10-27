import 'package:bhromon/core/services/push_device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pushDeviceId', () {
    test('is the same for the same token, and a 64-character hex id', () {
      final id = pushDeviceId('token-abc');
      expect(pushDeviceId('token-abc'), id);
      expect(id, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('differs between tokens, and is safe as a document id', () {
      final a = pushDeviceId('phone:with/slashes.and.dots');
      final b = pushDeviceId('tablet');
      expect(a, isNot(b));
      expect(a, isNot(contains('/')));
      expect(a, isNot(contains('.')));
    });
  });
}
