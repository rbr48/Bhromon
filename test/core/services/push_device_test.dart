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

  group('getOrCreatePushDeviceId', () {
    test('reuses an existing persisted id', () async {
      String? stored = 'stable-device-123';
      final id = await getOrCreatePushDeviceId(
        reader: () async => stored,
        writer: (value) async => stored = value,
      );
      expect(id, 'stable-device-123');
    });

    test('generates and persists an id when missing or blank', () async {
      String? stored = '   ';
      final first = await getOrCreatePushDeviceId(
        reader: () async => stored,
        writer: (value) async => stored = value,
      );
      final second = await getOrCreatePushDeviceId(
        reader: () async => stored,
        writer: (value) async => stored = value,
      );
      expect(first, isNotEmpty);
      expect(second, first);
    });
  });
}
