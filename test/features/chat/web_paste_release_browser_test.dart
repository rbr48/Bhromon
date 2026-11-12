@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:bhromon/features/chat/data/web_paste_listener.dart';
import 'package:bhromon/features/share_intake/domain/shared_file.dart';

/// Releasing a pasted file frees its object URL, so the browser stops resolving it. Run in Chrome:
///   flutter test --platform chrome test/features/chat/web_paste_release_browser_test.dart
void main() {
  test('releasing a pasted file ends its object URL', () async {
    final received = <SharedFile>[];
    final stop = attachWebPasteListener(
      accept: () => true,
      onFiles: (files) => received.addAll(files),
    );
    web.document.dispatchEvent(_paste([_png('a.png')]));
    stop();
    final path = received.single.path!;

    final held = await web.window.fetch(path.toJS).toDart;
    expect(held.ok, isTrue, reason: 'the object URL resolves while it is held');

    releasePastedFiles(received);
    await expectLater(
      web.window.fetch(path.toJS).toDart,
      throwsA(anything),
      reason: 'a released object URL no longer resolves',
    );
  });

  test('releasing leaves a path that is not an object URL alone', () {
    expect(
      () => releasePastedFiles([
        const SharedFile(
          name: 'a.png',
          sizeBytes: 1,
          path: '/cache/a.png',
          mimeType: 'image/png',
        ),
      ]),
      returnsNormally,
    );
  });
}

web.File _png(String name) => web.File(
      <JSAny>['png bytes'.toJS].toJS,
      name,
      web.FilePropertyBag(type: 'image/png'),
    );

web.ClipboardEvent _paste(List<web.File> files) {
  final data = web.DataTransfer();
  for (final file in files) {
    data.items.add(file);
  }
  return web.ClipboardEvent(
    'paste',
    web.ClipboardEventInit(
      bubbles: true,
      cancelable: true,
      clipboardData: data,
    ),
  );
}
