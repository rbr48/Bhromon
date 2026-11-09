import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// What came of an admin's reminder to the members who have not answered a notice.
enum NoticePingStatus {
  /// The reminder went out.
  sent,

  /// A reminder went out recently; [NoticePingResult.retryAfter] says how long to wait.
  tooSoon,

  /// Everyone has answered, so there is nobody to remind.
  nobodyWaiting,

  /// The notice no longer takes answers: it is archived, gone, or never asked for one.
  closed,

  /// The request failed: no connection, no permission, or a server error.
  failed,
}

/// The outcome of [NoticePingClient.ping].
class NoticePingResult {
  const NoticePingResult(
    this.status, {
    this.waiting = 0,
    this.retryAfter = Duration.zero,
  });

  final NoticePingStatus status;

  /// How many members were reminded, when [status] is [NoticePingStatus.sent].
  final int waiting;

  /// How long until the next reminder may go out, when [status] is
  /// [NoticePingStatus.tooSoon].
  final Duration retryAfter;

  /// Reads the media server's answer to `POST /notify/notice/ping`
  /// (`media-server/main.py`, `ping_notice`).
  static NoticePingResult fromResponse(int? statusCode, Object? data) {
    if (statusCode == 200) {
      final waiting = data is Map ? data['waiting'] : null;
      return NoticePingResult(NoticePingStatus.sent,
          waiting: waiting is int ? waiting : 0);
    }
    final detail = data is Map ? data['detail'] : null;
    final reason = detail is Map ? detail['reason'] : null;
    if (statusCode == 429) {
      final seconds = detail is Map ? detail['retryAfter'] : null;
      return NoticePingResult(NoticePingStatus.tooSoon,
          retryAfter: Duration(seconds: seconds is int ? seconds : 0));
    }
    if (reason == 'nobody_waiting') {
      return const NoticePingResult(NoticePingStatus.nobodyWaiting);
    }
    if (reason == 'archived' ||
        reason == 'not_found' ||
        reason == 'no_answer_needed') {
      return const NoticePingResult(NoticePingStatus.closed);
    }
    return const NoticePingResult(NoticePingStatus.failed);
  }
}

/// Asks the media server to remind a notice's waiting members now. Only an owner or
/// admin of the group may; the server checks that, and sends one reminder per notice
/// every 30 minutes at most.
class NoticePingClient {
  NoticePingClient({Dio? dio, Future<String?> Function()? idToken})
      : _dio = dio ?? Dio(),
        _idToken = idToken ??
            (() async => FirebaseAuth.instance.currentUser?.getIdToken());

  static const String url = 'https://bhromon.fun/api/media/notify/notice/ping';

  final Dio _dio;
  final Future<String?> Function() _idToken;

  Future<NoticePingResult> ping({
    required String tourId,
    required String noticeId,
  }) async {
    try {
      final token = await _idToken();
      final response = await _dio.post<Object?>(
        url,
        data: {'tourId': tourId, 'noticeId': noticeId},
        options: Options(
          headers: {
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
          // Refusals carry their reason in the body, so read them instead of throwing.
          validateStatus: (_) => true,
        ),
      );
      return NoticePingResult.fromResponse(response.statusCode, response.data);
    } on Exception {
      return const NoticePingResult(NoticePingStatus.failed);
    }
  }
}
