@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:bhromon/features/chat/data/web_paste_listener.dart';
import 'package:bhromon/features/share_intake/domain/shared_file.dart';

/// The web paste listener against a real browser paste event, in Chrome:
///   flutter test --platform chrome test/features/chat/web_paste_listener_browser_test.dart
void main() {
  final stops = <void Function()>[];

  tearDown(() {
    for (final stop in stops) {
      stop();
    }
    stops.clear();
  });

  test(
      'a paste of files is taken, each as a blob-backed file in the order copied',
      () {
    final received = <SharedFile>[];
    stops.add(attachWebPasteListener(
      accept: () => true,
      onFiles: (files) => received.addAll(files),
    ));

    final event = _paste([
      _file('screenshot.png', 'image/png', 'png bytes'),
      _file('notes.pdf', 'application/pdf', 'pdf bytes'),
    ]);
    web.document.dispatchEvent(event);

    expect(received.map((file) => file.name), ['screenshot.png', 'notes.pdf']);
    expect(received.first.mimeType, 'image/png');
    expect(received.first.sizeBytes, 'png bytes'.length);
    expect(received.first.path, startsWith('blob:'));
    expect(event.defaultPrevented, isTrue,
        reason: 'the browser must not paste the files itself');
  });

  test('a text paste is left to the browser', () {
    final received = <SharedFile>[];
    stops.add(attachWebPasteListener(
      accept: () => true,
      onFiles: (files) => received.addAll(files),
    ));

    final event = _paste([], text: 'a plain line of text');
    web.document.dispatchEvent(event);

    expect(received, isEmpty);
    expect(event.defaultPrevented, isFalse);
  });

  test('a file paste the chat refuses is left to the browser', () {
    var asked = false;
    final received = <SharedFile>[];
    stops.add(attachWebPasteListener(
      accept: () {
        asked = true;
        return false;
      },
      onFiles: (files) => received.addAll(files),
    ));

    final event = _paste([_file('a.png', 'image/png', 'png bytes')]);
    web.document.dispatchEvent(event);

    expect(asked, isTrue,
        reason: 'the chat decides whether a paste is its own');
    expect(received, isEmpty);
    expect(event.defaultPrevented, isFalse);
  });

  test('after the listener is stopped, a file paste is no longer taken', () {
    final received = <SharedFile>[];
    final stop = attachWebPasteListener(
      accept: () => true,
      onFiles: (files) => received.addAll(files),
    );
    stop();

    web.document.dispatchEvent(_paste([_file('a.png', 'image/png', 'x')]));

    expect(received, isEmpty);
  });
}

/// A file as the clipboard holds it: bytes with a name and a type.
web.File _file(String name, String type, String content) => web.File(
      <JSAny>[content.toJS].toJS,
      name,
      web.FilePropertyBag(type: type),
    );

/// A paste event carrying [files], and [text] as a text item when given.
web.ClipboardEvent _paste(List<web.File> files, {String? text}) {
  final data = web.DataTransfer();
  for (final file in files) {
    data.items.add(file);
  }
  if (text != null) data.items.add(text.toJS, 'text/plain');
  return web.ClipboardEvent(
    'paste',
    web.ClipboardEventInit(
      bubbles: true,
      cancelable: true,
      clipboardData: data,
    ),
  );
}
