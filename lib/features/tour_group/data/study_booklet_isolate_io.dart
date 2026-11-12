import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../domain/services/study_booklet_pdf_generator.dart';

/// Message tags the background isolate sends back.
const int _progressTag = 0;
const int _doneTag = 1;

/// Lays [job] out in a background isolate, so the screen keeps drawing while the booklet is made.
///
/// [onProgress] is told each chapter as it is laid out. When [isCancelled] turns true the isolate
/// is stopped at once, and this throws [StudyBookletCancelled].
Future<Uint8List> layoutBookletJob(
  StudyBookletJob job, {
  bool Function()? isCancelled,
  void Function(int done, int total)? onProgress,
}) async {
  if (isCancelled?.call() ?? false) throw const StudyBookletCancelled();

  final inbox = ReceivePort();
  final laidOut = Completer<Uint8List>();
  Timer? cancelWatch;

  void close() {
    cancelWatch?.cancel();
    inbox.close();
  }

  inbox.listen((message) {
    if (message is List && message.length == 3 && message[0] == _progressTag) {
      onProgress?.call(message[1] as int, message[2] as int);
      return;
    }
    if (!laidOut.isCompleted) {
      if (message is List && message.length == 2 && message[0] == _doneTag) {
        laidOut.complete(message[1] as Uint8List);
      } else {
        // An error from the isolate, or the isolate ended before it sent a booklet.
        laidOut.completeError(
          StateError('The booklet could not be laid out: $message'),
        );
      }
    }
    close();
  });

  final Isolate isolate;
  try {
    isolate = await Isolate.spawn<_Request>(
      _layoutInIsolate,
      _Request(job, inbox.sendPort),
      onError: inbox.sendPort,
      onExit: inbox.sendPort,
    );
  } catch (_) {
    close();
    rethrow;
  }

  if (isCancelled != null) {
    cancelWatch = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (laidOut.isCompleted || !isCancelled()) return;
      isolate.kill(priority: Isolate.immediate);
      laidOut.completeError(const StudyBookletCancelled());
      close();
    });
  }

  try {
    return await laidOut.future;
  } finally {
    close();
  }
}

/// What the background isolate is given: the job, and the port its results go back on.
class _Request {
  const _Request(this.job, this.reply);

  final StudyBookletJob job;
  final SendPort reply;
}

/// Runs on the background isolate: lays the booklet out, reports each chapter, and sends the bytes
/// back. A failure is sent back as well, so the screen can say so instead of waiting.
void _layoutInIsolate(_Request request) {
  final reply = request.reply;
  unawaited(
    StudyBookletPdfGenerator.layoutJob(
      request.job,
      pauseBetweenChapters: false,
      onProgress: (done, total) => reply.send([_progressTag, done, total]),
    ).then<void>(
      (bytes) => reply.send([_doneTag, bytes]),
      onError: (Object error, StackTrace stack) => reply.send(['$error']),
    ),
  );
}
