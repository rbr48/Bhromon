import 'package:bhromon/features/tour_group/data/tour_media_uploader.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _failure(DioExceptionType type, {int? status}) {
  final options = RequestOptions(path: '/upload');
  return DioException(
    requestOptions: options,
    type: type,
    response: status == null
        ? null
        : Response<void>(requestOptions: options, statusCode: status),
  );
}

DioException _refusal(int status, Object body) {
  final options = RequestOptions(path: '/upload');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<Object>(
        requestOptions: options, statusCode: status, data: body),
  );
}

void main() {
  group('isTourStorageFull', () {
    test('recognises the quota refusal from the media server', () {
      final e = _refusal(413, {
        'detail': {'error': 'quota_exceeded', 'limitBytes': 10737418240},
      });
      expect(isTourStorageFull(e), isTrue);
    });

    test('is not a size refusal or a different error', () {
      expect(
        isTourStorageFull(_refusal(
            413, {'detail': 'File exceeds maximum allowed size (10 MB)'})),
        isFalse,
      );
      expect(
        isTourStorageFull(_refusal(409, {
          'detail': {'error': 'quota_exceeded'}
        })),
        isFalse,
      );
      expect(isTourStorageFull(_failure(DioExceptionType.connectionError)),
          isFalse);
    });
  });

  group('isRetryableUploadError', () {
    test('retries dropped connections and timeouts', () {
      for (final type in [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(isRetryableUploadError(_failure(type)), isTrue, reason: '$type');
      }
    });

    test('retries a briefly unavailable gateway', () {
      for (final code in [502, 503, 504]) {
        expect(
          isRetryableUploadError(
              _failure(DioExceptionType.badResponse, status: code)),
          isTrue,
          reason: '$code',
        );
      }
    });

    test('does not retry a refused upload or a cancellation', () {
      expect(
        isRetryableUploadError(
            _failure(DioExceptionType.badResponse, status: 413)),
        isFalse,
      );
      expect(
        isRetryableUploadError(
            _failure(DioExceptionType.badResponse, status: 409)),
        isFalse,
      );
      expect(
          isRetryableUploadError(_failure(DioExceptionType.cancel)), isFalse);
    });

    test('allows three attempts in total', () {
      expect(kUploadAttempts, 3);
    });
  });
}
