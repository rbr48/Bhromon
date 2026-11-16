import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/core/web/web_external_scripts.dart';

void main() {
  group('web_external_scripts (VM/native stubs)', () {
    test('ensureMapLibreLoaded and ensurePdfJsLoaded complete without throwing',
        () async {
      await ensureMapLibreLoaded();
      await ensurePdfJsLoaded();
    });

    test('ensureVideoTranscoderLoaded returns false off Web', () async {
      expect(await ensureVideoTranscoderLoaded(), isFalse);
    });
  });
}
