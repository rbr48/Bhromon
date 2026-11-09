import 'package:bhromon/features/tour_group/data/notice_ping_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// The admin's reminder to a notice's waiting members. The media server answers
// POST /notify/notice/ping (media-server/main.py, ping_notice); here a Dio
// interceptor answers in its place, so nothing leaves the test.

/// A client whose server answers [statusCode] with [data], recording each request.
NoticePingClient _client(
  int statusCode,
  Object? data,
  List<RequestOptions> sent, {
  String? token = 'tok',
}) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    sent.add(options);
    handler.resolve(Response<Object?>(
      requestOptions: options,
      statusCode: statusCode,
      data: data,
    ));
  }));
  return NoticePingClient(dio: dio, idToken: () async => token);
}

void main() {
  test('a sent reminder posts the ids with the ID token and reports who waits',
      () async {
    final sent = <RequestOptions>[];
    final result = await _client(200, {'waiting': 3, 'pushes': 4}, sent)
        .ping(tourId: 't1', noticeId: 'n1');

    expect(result.status, NoticePingStatus.sent);
    expect(result.waiting, 3);
    expect(sent.single.uri.toString(), NoticePingClient.url);
    expect(sent.single.data, {'tourId': 't1', 'noticeId': 'n1'});
    expect(sent.single.headers['Authorization'], 'Bearer tok');
  });

  test('too soon says how long to wait', () async {
    final result = await _client(429, {
      'detail': {'reason': 'too_soon', 'retryAfter': 600}
    }, []).ping(tourId: 't1', noticeId: 'n1');

    expect(result.status, NoticePingStatus.tooSoon);
    expect(result.retryAfter, const Duration(minutes: 10));
  });

  test('each refusal reads as what the admin should be told', () {
    NoticePingStatus of(int code, String reason) =>
        NoticePingResult.fromResponse(code, {
          'detail': {'reason': reason, 'retryAfter': 0}
        }).status;

    expect(of(409, 'nobody_waiting'), NoticePingStatus.nobodyWaiting);
    expect(of(409, 'archived'), NoticePingStatus.closed);
    expect(of(409, 'no_answer_needed'), NoticePingStatus.closed);
    expect(of(404, 'not_found'), NoticePingStatus.closed);
    expect(NoticePingResult.fromResponse(403, {'detail': 'Only admins'}).status,
        NoticePingStatus.failed);
    expect(NoticePingResult.fromResponse(500, 'oops').status,
        NoticePingStatus.failed);
  });

  test('a request with no connection reads as failed, not as a crash',
      () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(DioException.connectionError(
          requestOptions: options, reason: 'offline'));
    }));
    final result = await NoticePingClient(dio: dio, idToken: () async => 'tok')
        .ping(tourId: 't1', noticeId: 'n1');

    expect(result.status, NoticePingStatus.failed);
  });
}
