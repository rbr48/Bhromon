import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/game_zone/data/card29_api.dart';
import 'package:bhromon/features/game_zone/data/teen_patti_api.dart';

void main() {
  group('Card29Api VPS calls', () {
    late Dio dio;
    late List<RequestOptions> capturedRequests;

    setUp(() {
      capturedRequests = [];
      dio = Dio(BaseOptions(baseUrl: 'https://bhromon.fun/api/games'));
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequests.add(options);
          final path = options.path;

          if (path.endsWith('/card29Start')) {
            handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'result': {'status': 'started'}
              },
            ));
          } else if (path.endsWith('/card29Act')) {
            if (options.data is Map &&
                options.data['action']?['type'] == 'illegal') {
              handler.reject(DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 400,
                  data: {
                    'error': {
                      'message': 'Cannot play trump before reveal.',
                      'status': 'INVALID_ARGUMENT',
                    },
                  },
                ),
                type: DioExceptionType.badResponse,
              ));
            } else {
              handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'result': {'status': 'acted'}
                },
              ));
            }
          } else if (path.endsWith('/card29Advance')) {
            handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'result': {'status': 'bot'}
              },
            ));
          } else if (path.endsWith('/card29Leave')) {
            handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'result': {'status': 'left'}
              },
            ));
          } else {
            handler.next(options);
          }
        },
      ));
    });

    test('start, act, advance, leave execute through VPS endpoints', () async {
      final api = Card29Api(
        dio: dio,
        baseUrl: 'https://bhromon.fun/api/games',
      );

      // start
      await api.start(tourId: 't1', gameId: 'g1');
      expect(capturedRequests.last.path, contains('/card29Start'));
      expect(capturedRequests.last.data, {'tourId': 't1', 'gameId': 'g1'});

      // act
      await api.act(
        tourId: 't1',
        gameId: 'g1',
        action: {'type': 'bid', 'bid': 16},
        expectedStep: 3,
      );
      expect(capturedRequests.last.path, contains('/card29Act'));

      // advance
      final status =
          await api.advance(tourId: 't1', gameId: 'g1', expectedStep: 4);
      expect(status, 'bot');
      expect(capturedRequests.last.path, contains('/card29Advance'));

      // leave
      await api.leave(tourId: 't1', gameId: 'g1');
      expect(capturedRequests.last.path, contains('/card29Leave'));
    });

    test('maps rejected server response into FirebaseFunctionsException',
        () async {
      final api = Card29Api(
        dio: dio,
        baseUrl: 'https://bhromon.fun/api/games',
      );

      try {
        await api.act(
          tourId: 't1',
          gameId: 'g1',
          action: {'type': 'illegal'},
          expectedStep: 1,
        );
        fail('Should have thrown FirebaseFunctionsException');
      } on FirebaseFunctionsException catch (e) {
        expect(e.message, 'Cannot play trump before reveal.');
        expect(e.code, 'invalid-argument');
      }
    });
  });

  group('TeenPattiApi VPS calls', () {
    late Dio dio;
    late List<RequestOptions> capturedRequests;

    setUp(() {
      capturedRequests = [];
      dio = Dio(BaseOptions(baseUrl: 'https://bhromon.fun/api/games'));
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequests.add(options);
          final path = options.path;

          if (path.endsWith('/teenPattiStart')) {
            handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'result': {'status': 'started'}
              },
            ));
          } else if (path.endsWith('/teenPattiAct')) {
            if (options.data is Map &&
                options.data['action']?['type'] == 'insufficient_balance') {
              handler.reject(DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 400,
                  data: {
                    'error': {
                      'message': 'Insufficient chips to chaal.',
                      'status': 'FAILED_PRECONDITION',
                    },
                  },
                ),
                type: DioExceptionType.badResponse,
              ));
            } else {
              handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'result': {'status': 'acted'}
                },
              ));
            }
          } else if (path.endsWith('/teenPattiAdvance')) {
            handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'result': {'status': 'auto'}
              },
            ));
          } else if (path.endsWith('/teenPattiLeave')) {
            handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'result': {'status': 'left'}
              },
            ));
          } else {
            handler.next(options);
          }
        },
      ));
    });

    test('start, act, advance, leave execute through VPS endpoints', () async {
      final api = TeenPattiApi(
        dio: dio,
        baseUrl: 'https://bhromon.fun/api/games',
      );

      await api.start(tourId: 't2', gameId: 'g2');
      expect(capturedRequests.last.path, contains('/teenPattiStart'));

      await api.act(
        tourId: 't2',
        gameId: 'g2',
        action: {'type': 'chaal', 'amount': 10},
        expectedStep: 2,
      );
      expect(capturedRequests.last.path, contains('/teenPattiAct'));

      final status =
          await api.advance(tourId: 't2', gameId: 'g2', expectedStep: 2);
      expect(status, 'auto');
      expect(capturedRequests.last.path, contains('/teenPattiAdvance'));

      await api.leave(tourId: 't2', gameId: 'g2');
      expect(capturedRequests.last.path, contains('/teenPattiLeave'));
    });

    test('maps rejected server response into FirebaseFunctionsException',
        () async {
      final api = TeenPattiApi(
        dio: dio,
        baseUrl: 'https://bhromon.fun/api/games',
      );

      try {
        await api.act(
          tourId: 't2',
          gameId: 'g2',
          action: {'type': 'insufficient_balance'},
          expectedStep: 1,
        );
        fail('Should have thrown FirebaseFunctionsException');
      } on FirebaseFunctionsException catch (e) {
        expect(e.message, 'Insufficient chips to chaal.');
        expect(e.code, 'failed-precondition');
      }
    });
  });
}
